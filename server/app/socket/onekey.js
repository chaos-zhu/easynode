const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { readHostList, readSSHRecord, verifyAuthSync, AESDecryptSync, writeOneKeyRecord, throttle } = require('../utils')

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

function disconnectAllExecClient() {
  execClient.forEach((sshClient) => {
    if (sshClient) {
      sshClient.end()
      sshClient.destroy()
      sshClient = null
    }
  })
}

function execShell(socket, sshClient, curRes, resolve) {
  const throttledDataHandler = throttle((data) => {
    curRes.status = execStatusEnum.executing
    curRes.result += data?.toString() || ''
    socket.emit('output', execResult)
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
      .on('close', () => {
        throttledDataHandler.flush()
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
        // curRes.status = execStatusEnum.executing
        // curRes.result += data.toString()
        // socket.emit('output', execResult)
        throttledDataHandler(data)
      })
      .stderr
      .on('data', (data) => {
        // console.log(curRes.host, '命令执行过程中产生错误: ' + data)
        // curRes.status = execStatusEnum.executing
        // curRes.result += data.toString()
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
    let clientIp = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    consola.success('onekey-terminal websocket 已连接')
    if (isExecuting) {
      socket.emit('create_fail', '正在执行中, 请稍后再试')
      socket.disconnect()
      return
    }
    isExecuting = true
    socket.on('create', async ({ hosts, token, command, timeout }) => {
      const { code } = await verifyAuthSync(token, clientIp)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      setTimeout(() => {
        // 超时未执行完成，断开连接
        disconnectAllExecClient()
        const { connecting, executing } = execStatusEnum
        execResult.forEach(item => {
          // 连接中和执行中的状态设定为超时
          if ([connecting, executing].includes(item.status)) {
            item.status = execStatusEnum.execTimeout
          }
        })
        socket.emit('timeout', { reason: `执行超时,已强制终止执行 - 超时时间${ timeout }秒`, result: execResult })
        socket.disconnect()
      }, timeout * 1000)
      console.log('hosts:', hosts)
      // console.log('token:', token)
      console.log('command:', command)
      const hostList = await readHostList()
      const targetHostsInfo = hostList.filter(item => hosts.some(ip => item.host === ip)) || {}
      // console.log('targetHostsInfo:', targetHostsInfo)
      if (!targetHostsInfo.length) return socket.emit('create_fail', `未找到【${ hosts }】服务器信息`)
      // 查找 hostInfo -> 并发执行
      socket.emit('ready')
      let execPromise = targetHostsInfo.map((hostInfo, index) => {
        // eslint-disable-next-line no-async-promise-executor
        return new Promise(async (resolve) => {
          let { authType, host, port, username } = hostInfo
          let authInfo = { host, port, username }
          let curRes = { command, host, name: hostInfo.name, result: '', status: execStatusEnum.connecting, date: Date.now() - (targetHostsInfo.length - index) } // , execStatusEnum
          execResult.push(curRes)
          try {
            if (authType === 'credential') {
              let credentialId = await AESDecryptSync(hostInfo['credential'])
              const sshRecordList = await readSSHRecord()
              const sshRecord = sshRecordList.find(item => item._id === credentialId)
              authInfo.authType = sshRecord.authType
              authInfo[authInfo.authType] = await AESDecryptSync(sshRecord[authInfo.authType])
            } else {
              authInfo[authType] = await AESDecryptSync(hostInfo[authType])
            }
            consola.info('准备连接终端执行一次性指令：', host)
            consola.log('连接信息', { username, port, authType })
            let sshClient = new SSHClient()
            execClient.push(sshClient)
            sshClient
              .on('ready', () => {
                consola.success('连接终端成功：', host)
                // socket.emit('connect_success', `已连接到终端：${ host }`)
                execShell(socket, sshClient, curRes, resolve)
              })
              .on('error', (err) => {
                console.log(err)
                consola.error('onekey终端连接失败:', err.level)
                curRes.status = execStatusEnum.connectFail
                curRes.result += err.message
                resolve(curRes)
              })
              .connect({
                ...authInfo
              // debug: (info) => console.log(info)
              })
          } catch (err) {
            consola.error('创建终端错误:', err.message)
            curRes.status = execStatusEnum.connectFail
            curRes.result += err.message
            resolve(curRes)
          }
        })
      })
      await Promise.all(execPromise)
      consola.success('onekey执行完成')
      socket.emit('exec_complete')
      socket.disconnect()
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
      await writeOneKeyRecord(execResult)
      isExecuting = false
      execResult = []
      execClient = []
    })
  })
}
