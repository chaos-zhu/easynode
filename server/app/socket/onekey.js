const rawPath = require('path')
const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { sendNoticeAsync } = require('../utils/notify')
const { verifyAuthSync } = require('../utils/verify-auth')
const { shellThrottle } = require('../utils/tools')
const { isAllowedIp } = require('../utils/tools')
const { HostListDB, OnekeyDB } = require('../utils/db-class')
const { getConnectionOptions } = require('./terminal')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const hostListDB = new HostListDB().getInstance()
const onekeyDB = new OnekeyDB().getInstance()

const execStatusEnum = {
  connecting: '连接中',
  connectFail: '连接失败',
  executing: '执行中',
  execSuccess: '执行成功',
  execFail: '执行失败',
  execTimeout: '执行超时',
  socketInterrupt: '执行中断'
}

let isExecuting = false
let execResult = []
let execClient = []
let jumpSshClientsPool = []

function disconnectAllExecClient() {
  execClient.forEach((sshClient) => {
    if (sshClient) {
      sshClient.end()
      sshClient.destroy()
      sshClient = null
    }
  })
  jumpSshClientsPool.forEach(jumpSshClients => {
    jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
  })
  jumpSshClientsPool = []
}

function execShell(socket, sshClient, curRes, resolve) {
  const throttledDataHandler = shellThrottle(() => {
    socket.emit('output', execResult)
    // const memoryUsage = process.memoryUsage()
    // const formattedMemoryUsage = {
    //   rss: (memoryUsage.rss / 1024 / 1024).toFixed(2) + ' MB', // Resident Set Size: total memory allocated for the process execution
    //   heapTotal: (memoryUsage.heapTotal / 1024 / 1024).toFixed(2) + ' MB', // Total size of the allocated heap
    //   heapUsed: (memoryUsage.heapUsed / 1024 / 1024).toFixed(2) + ' MB', // Actual memory used during the execution
    //   external: (memoryUsage.external / 1024 / 1024).toFixed(2) + ' MB', // Memory used by "external" components like V8 external memory
    //   arrayBuffers: (memoryUsage.arrayBuffers / 1024 / 1024).toFixed(2) + ' MB' // Memory allocated for ArrayBuffer and SharedArrayBuffer, including all Node.js Buffers
    // }
    // console.log(formattedMemoryUsage)
  }, 500) // 防止内存爆破
  sshClient.exec(curRes.command, function(err, stream) {
    if (err) {
      console.log(curRes.host, '命令执行失败:', err)
      curRes.status = execStatusEnum.execFail
      curRes.result += err.toString()
      socket.emit('output', execResult)
      return
    }
    stream
      .on('close', async () => {
        // shell关闭后，再执行一次输出，防止最后一次节流函数发生在延迟时间内导致终端的输出数据丢失
        await throttledDataHandler.last() // 等待最后一次节流函数执行完成，再执行一次数据输出
        // console.log('onekey终端执行完成, 关闭连接: ', curRes.host)
        if (curRes.status === execStatusEnum.executing) {
          curRes.status = execStatusEnum.execSuccess
        }
        socket.emit('output', execResult)
        resolve(curRes)
        sshClient.end()
      })
      .on('data', (data) => {
        // console.log(curRes.host, '执行中: \n' + data)
        curRes.status = execStatusEnum.executing
        curRes.result += data.toString()
        // socket.emit('output', execResult)
        throttledDataHandler(data)
      })
      .stderr
      .on('data', (data) => {
        // console.log(curRes.host, '命令执行过程中产生错误: ' + data)
        curRes.status = execStatusEnum.executing
        curRes.result += data.toString()
        // socket.emit('output', execResult)
        throttledDataHandler(data)
      })
  })
}

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/onekey',
    cors: {
      origin: '*'
    }
  })
  serverIo.on('connection', (socket) => {
    // 前者兼容nginx反代, 后者兼容nodejs自身服务
    let requestIP = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }
    consola.success('onekey-terminal websocket 已连接')
    if (isExecuting) {
      socket.emit('create_fail', '正在执行中, 请稍后再试')
      socket.disconnect()
      return
    }
    isExecuting = true
    socket.on('ws_onekey', async ({ hostIds, token, command, timeout }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      setTimeout(() => {
        // 超时未执行完成，强制断开连接
        const { connecting, executing } = execStatusEnum
        execResult.forEach(item => {
          // 连接中和执行中的状态设定为超时
          if ([connecting, executing].includes(item.status)) {
            item.status = execStatusEnum.execTimeout
          }
        })
        let reason = `执行超时,已强制终止执行 - 超时时间${ timeout }秒`
        sendNoticeAsync('onekey_complete', '批量指令执行超时', reason)
        socket.emit('timeout', { reason, result: execResult })
        socket.disconnect()
        disconnectAllExecClient()
      }, timeout * 1000)
      console.log('hostIds:', hostIds)
      // console.log('token:', token)
      console.log('command:', command)
      const hostList = await hostListDB.findAsync({})
      const targetHostsInfo = hostList.filter(item => hostIds.some(id => item._id === id)) || {}
      // console.log('targetHostsInfo:', targetHostsInfo)
      if (!targetHostsInfo.length) return socket.emit('create_fail', `未找到【${ hostIds }】服务器信息`)
      // 查找 hostInfo -> 并发执行
      socket.emit('ready')
      // 获取跳板机连接函数
      let { connectByJumpHosts = null } = (await decryptAndExecuteAsync(rawPath.join(__dirname, 'plus.js'))) || {}

      let execPromise = targetHostsInfo.map((hostInfo, index) => {
        // eslint-disable-next-line no-async-promise-executor
        return new Promise(async (resolve, reject) => {
          setTimeout(() => reject('执行超时'), timeout * 1000)
          let { host, port, jumpHosts } = hostInfo
          let curRes = { command, host, port, name: hostInfo.name, result: '', status: execStatusEnum.connecting, date: Date.now() - (targetHostsInfo.length - index) }
          execResult.push(curRes)
          let jumpSshClients = []
          try {
            let { authInfo: targetConnectionOptions } = await getConnectionOptions(hostInfo._id)

            // 处理跳板机连接
            let jumpHostResult = connectByJumpHosts && (await connectByJumpHosts(jumpHosts, targetConnectionOptions.host, targetConnectionOptions.port, socket))
            if (jumpHostResult) {
              targetConnectionOptions.sock = jumpHostResult.sock
              jumpSshClients = jumpHostResult.sshClients
              jumpSshClientsPool.push(jumpSshClients)
              consola.success('Onekey跳板机连接成功')
            }

            consola.info('准备连接终端执行一次性指令：', host)
            consola.log('连接信息', { username: targetConnectionOptions.username, port: targetConnectionOptions.port, authType: hostInfo.authType })

            let sshClient = new SSHClient()
            execClient.push(sshClient)
            sshClient
              .on('ready', () => {
                consola.success('连接终端成功：', host)
                execShell(socket, sshClient, curRes, resolve)
              })
              .on('error', (err) => {
                console.log(err)
                consola.error('onekey终端连接失败:', err.level)
                curRes.status = execStatusEnum.connectFail
                curRes.result += err.message
                socket.emit('output', execResult)
                // 清理跳板机连接
                jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
                resolve(curRes)
              })
              .on('keyboard-interactive', function (name, instructions, instructionsLang, prompts, finish) {
                finish([targetConnectionOptions[hostInfo.authType]])
              })
              .connect({
                tryKeyboard: true,
                ...targetConnectionOptions
              })
          } catch (err) {
            consola.error('创建终端错误:', err.message)
            curRes.status = execStatusEnum.connectFail
            curRes.result += err.message
            socket.emit('output', execResult)
            // 清理跳板机连接
            jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
            resolve(curRes)
          }
        })
      })
      try {
        await Promise.all(execPromise)
        consola.success('onekey执行完成')
        socket.emit('exec_complete')
        sendNoticeAsync('onekey_complete', '批量指令执行完成', '请登录面板查看执行结果')
        socket.disconnect()
      } catch (error) {
        consola.error('onekey执行失败', error)
      }
    })

    socket.on('disconnect', async (reason) => {
      consola.info('onekey终端连接断开:', reason)
      disconnectAllExecClient()
      const { execSuccess, connectFail, execFail, execTimeout } = execStatusEnum
      execResult.forEach(item => {
        // 非服务端手动断开连接且命令执行状态为非完成\失败\超时, 判定为客户端主动中断
        if (reason !== 'server namespace disconnect' && ![execSuccess, execFail, execTimeout, connectFail].includes(item.status)) {
          item.status = execStatusEnum.socketInterrupt
        }
      })
      await onekeyDB.insertAsync(execResult)
      isExecuting = false
      execResult = []
      execClient = []
      jumpSshClientsPool = []
    })
  })
}
