import ssh2Module from 'ssh2'
const { Client: SSHClient } = ssh2Module
import { sendNoticeAsync } from '../utils/notify.js'
import { shellThrottle } from '../utils/tools.js'
import { createSecureWs } from '../utils/ws-tool.js'
import { HostListDB, OnekeyDB } from '../utils/db-class.js'
import { OnekeyExecutionState, execStatusEnum } from '../services/onekey-execution.js'
import { invalidateOnekeyRecordOrder } from '../services/onekey-records.js'
import { getConnectionOptions, handleProxyAndJumpHostConnection } from './terminal.js'

const hostListDB = new HostListDB().getInstance()
const onekeyDB = new OnekeyDB().getInstance()

let activeRun = null

function emitOutput(run) {
  if (run?.socket.connected) run.socket.emit('output', run.state.results)
}

function requestBatchFinish(run, reason, status) {
  if (run.finishReason) return false
  const stoppedCount = run.state.finishPending(status)
  if (!stoppedCount) return false
  run.finishReason = reason
  clearTimeout(run.timeoutTimer)
  return true
}

async function finalizeRun(run) {
  if (run.finalizePromise) return run.finalizePromise
  run.finalizePromise = (async () => {
    clearTimeout(run.timeoutTimer)
    let persisted = true
    try {
      await onekeyDB.insertAsync(run.state.results)
      invalidateOnekeyRecordOrder()
    } catch (error) {
      persisted = false
      logger.error('onekey执行记录保存失败:', error.message)
    } finally {
      if (activeRun === run) activeRun = null
    }
    return persisted
  })()
  return run.finalizePromise
}

function execShell(run, sshClient, curRes) {
  const { state } = run
  const hostId = curRes.hostId
  const throttledDataHandler = shellThrottle(() => emitOutput(run), 1000)

  sshClient.exec(curRes.command, (error, stream) => {
    if (!state.isActive(hostId)) {
      if (stream) state.attachStream(hostId, stream)
      return
    }
    if (error) {
      logger.error(`onekey指令执行失败 ${ curRes.host }:`, error.message)
      state.finishHost(hostId, execStatusEnum.execFail, error.toString())
      return
    }
    if (!state.attachStream(hostId, stream)) return

    stream
      .once('close', () => {
        // 输出已实时写入 result，收尾广播会带上最后一段内容。
        state.finishHost(hostId, execStatusEnum.execSuccess)
      })
      .once('error', (streamError) => {
        logger.error(`onekey指令流异常 ${ curRes.host }:`, streamError.message)
        state.finishHost(hostId, execStatusEnum.execFail, streamError.message)
      })
      .on('data', (data) => {
        if (!state.appendOutput(hostId, data)) return
        throttledDataHandler(data)
      })

    stream.stderr.on('data', (data) => {
      if (!state.appendOutput(hostId, data)) return
      throttledDataHandler(data)
    })
  })
}

async function connectTarget(run, hostInfo) {
  const { state } = run
  const hostId = hostInfo._id
  const curRes = state.getTarget(hostId).result

  try {
    const { authInfo: targetConnectionOptions } = await getConnectionOptions(hostId)
    if (!state.isActive(hostId)) return

    try {
      const result = await handleProxyAndJumpHostConnection({
        hostInfo,
        targetConnectionOptions,
        socket: null,
        logPrefix: 'Onekey '
      })
      const transportAttached = state.attachTransport(hostId, result.targetConnectionOptions?.sock)
      const jumpClientsAttached = state.attachJumpClients(hostId, result.jumpSshClients)
      if (!transportAttached || !jumpClientsAttached) return
    } catch (proxyError) {
      if (state.isActive(hostId)) {
        state.finishHost(hostId, execStatusEnum.connectFail, `代理连接失败: ${ proxyError.message }`)
      }
      return
    }

    if (!state.isActive(hostId)) return
    logger.info('准备连接终端执行一次性指令：', curRes.host)
    logger.info('连接信息', {
      username: targetConnectionOptions.username,
      port: targetConnectionOptions.port,
      authType: hostInfo.authType
    })

    const sshClient = new SSHClient()
    if (!state.attachSshClient(hostId, sshClient)) return
    sshClient
      .once('ready', () => {
        if (!state.isActive(hostId)) return
        logger.info('连接终端成功：', curRes.host)
        execShell(run, sshClient, curRes)
      })
      .on('error', (error) => {
        if (!state.isActive(hostId)) return
        logger.error('onekey终端连接失败:', error.message)
        const status = curRes.status === execStatusEnum.executing
          ? execStatusEnum.execFail
          : execStatusEnum.connectFail
        state.finishHost(hostId, status, error.message)
      })
      .on('keyboard-interactive', (name, instructions, instructionsLang, prompts, finish) => {
        finish([targetConnectionOptions[hostInfo.authType]])
      })
      .connect({
        tryKeyboard: true,
        ...targetConnectionOptions
      })
  } catch (error) {
    if (!state.isActive(hostId)) return
    logger.error('onekey创建终端错误:', error.message)
    state.finishHost(hostId, execStatusEnum.connectFail, error.message)
  }
}

async function executeRun(run, targetHostsInfo) {
  run.timeoutTimer = setTimeout(() => {
    if (!requestBatchFinish(run, 'timeout', execStatusEnum.execTimeout)) return
    logger.error('onekey执行超时')
  }, run.timeout * 1000)

  targetHostsInfo.forEach(hostInfo => {
    connectTarget(run, hostInfo)
  })

  await run.state.waitForAll()
  if (!run.finishReason) run.finishReason = 'complete'
  await finalizeRun(run)

  if (!run.socket.connected) return
  if (run.finishReason === 'complete') {
    logger.info('onekey执行完成')
    run.socket.emit('exec_complete')
    sendNoticeAsync('onekey_complete', '批量指令执行完成', '请登录面板查看执行结果')
  } else if (run.finishReason === 'timeout') {
    const reason = `执行超时,已强制终止执行 - 超时时间${ run.timeout }秒`
    sendNoticeAsync('onekey_complete', '批量指令执行超时', reason)
    run.socket.emit('exec_timeout', { reason, result: run.state.results })
  }
}

export default (httpServer) => {
  const serverIo = createSecureWs(httpServer, '/onekey')

  serverIo.on('connection', (socket) => {
    logger.info('onekey-terminal websocket 已连接')
    let currentRun = null

    socket.on('ws_onekey', async ({ hostIds = [], command = '', timeout = 120 } = {}) => {
      if (activeRun) {
        socket.emit('create_fail', '正在执行中, 请稍后再试')
        if (activeRun.socket !== socket) socket.disconnect()
        return
      }

      const uniqueHostIds = [...new Set(Array.isArray(hostIds) ? hostIds : [])]
      let hostList
      try {
        hostList = await hostListDB.findAsync({})
      } catch (error) {
        logger.error('onekey读取服务器信息失败:', error.message)
        socket.emit('create_fail', '读取服务器信息失败')
        socket.disconnect()
        return
      }
      // 数据库查询期间可能有另一个 Socket 抢先启动任务。
      if (activeRun) {
        socket.emit('create_fail', '正在执行中, 请稍后再试')
        if (activeRun.socket !== socket) socket.disconnect()
        return
      }
      const hostById = new Map(hostList.map(item => [item._id, item]))
      const targetHostsInfo = uniqueHostIds.map(id => hostById.get(id)).filter(Boolean)
      if (!targetHostsInfo.length) {
        socket.emit('create_fail', `未找到【${ uniqueHostIds }】服务器信息`)
        socket.disconnect()
        return
      }

      const numericTimeout = Number(timeout)
      let run = null
      const state = new OnekeyExecutionState({
        emitOutput: () => emitOutput(run)
      })
      const startDate = Date.now()
      const batchId = `${ startDate }-${ socket.id }`
      targetHostsInfo.forEach((hostInfo, index) => {
        state.addTarget({
          batchId,
          batchStartDate: startDate,
          order: index,
          hostId: hostInfo._id,
          command,
          host: hostInfo.host,
          port: hostInfo.port,
          name: hostInfo.name,
          result: '',
          status: execStatusEnum.connecting,
          startDate: startDate + index
        })
      })

      run = {
        socket,
        state,
        finishReason: null,
        finalizePromise: null,
        timeoutTimer: null,
        timeout: Number.isFinite(numericTimeout) && numericTimeout >= 1 ? numericTimeout : 120
      }
      currentRun = run
      activeRun = run
      socket.emit('ready')
      emitOutput(run)

      try {
        await executeRun(run, targetHostsInfo)
      } catch (error) {
        logger.error('onekey执行失败:', error.message)
        requestBatchFinish(run, 'disconnect', execStatusEnum.socketInterrupt)
        await finalizeRun(run)
        if (socket.connected) {
          socket.emit('create_fail', error.message || '批量指令执行失败')
        }
      } finally {
        if (socket.connected && run.finishReason !== 'manual') socket.disconnect()
      }
    })

    socket.on('ws_onekey_stop', async ({ scope, hostId } = {}) => {
      const run = currentRun
      if (!run || activeRun !== run) {
        socket.emit('stop_result', { ok: false, scope, hostId, message: '当前没有可停止的批量任务' })
        return
      }

      if (scope === 'host') {
        const result = run.state.stopHost(hostId)
        socket.emit('stop_result', { ...result, scope, hostId })
        return
      }

      if (scope !== 'all') {
        socket.emit('stop_result', { ok: false, scope, hostId, message: '不支持的停止范围' })
        return
      }

      if (!requestBatchFinish(run, 'manual', execStatusEnum.socketInterrupt)) {
        socket.emit('stop_result', { ok: false, scope, message: '当前批次已结束' })
        return
      }

      const persisted = await finalizeRun(run)
      if (socket.connected) {
        socket.emit('stop_result', {
          ok: true,
          scope: 'all',
          persisted,
          message: persisted ? '已停止当前批次' : '已停止当前批次，但执行记录保存失败'
        })
        socket.disconnect()
      }
    })

    socket.on('disconnect', async (reason) => {
      logger.info('onekey终端连接断开:', reason)
      const run = currentRun
      if (!run || activeRun !== run) return
      requestBatchFinish(run, 'disconnect', execStatusEnum.socketInterrupt)
      await finalizeRun(run)
    })
  })
}
