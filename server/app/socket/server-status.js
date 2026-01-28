const { Client: SSHClient } = require('ssh2')
const { createTerminal } = require('./terminal')
const { createSecureWs } = require('../utils/ws-tool')
const monitorMap = new Map() // key -> { sockets: Set, statusData, stop }
const pendingConnections = new Map() // key -> Promise，跟踪正在创建的连接
const { HostListDB } = require('../utils/db-class')
const hostListDB = new HostListDB().getInstance()

/* eslint-disable no-control-regex */
function stripAnsi(s = '') {
  return s
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '') // CSI
    .replace(/\x1B\][^\x07]*(\x07|\x1B\\)/g, '') // OSC
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '') // 其他控制符
}

const safeDelta = (curr, prev) => (curr >= prev ? curr - prev : 0)

module.exports = (httpServer) => {
  const serverIo = createSecureWs(httpServer, '/server-status')

  let connectionCount = 0

  serverIo.on('connection', async (socket) => {
    connectionCount++
    logger.info(`server-status websocket 已连接 - 当前连接数: ${ connectionCount }`)

    let targetSSHClient = null
    let jumpSshClients = []
    let monitorTimer = null
    let sendDataTimer = null
    let lastNetStats = null // 用于计算网络速率
    let previousCpuStats = null // 用于计算CPU使用率
    let defaultNetInterface = null // 默认网络接口
    let monitorKey = null // 全连接生命周期的主机键

    // 新增持久化 shell相关变量与函数  -----------
    let persistentShell = null // SSH shell stream
    let shellReady = false
    let cmdQueue = [] // [{command, resolve, reject, marker, output}]
    let cmdCounter = 0

    socket.on('ws_server_status', async ({ hostId }) => {
      try {
        const targetHostInfo = await hostListDB.findOneAsync({ _id: hostId })
        if (!targetHostInfo) {
          socket.emit('server_status_error', '主机信息不存在')
          return
        }
        monitorKey = `${ targetHostInfo.host }:${ targetHostInfo.port }`

        // 如果已有监控，直接复用
        if (monitorMap.has(monitorKey)) {
          const entry = monitorMap.get(monitorKey)
          entry.sockets.add(socket)
          // 立即推送现有数据
          socket.emit('server_status_data', entry.statusData)
          // 处理断连
          socket.on('disconnect', () => {
            entry.sockets.delete(socket)
            if (entry.sockets.size === 0) {
              entry.stop() // 停止监控并关闭 SSH
              monitorMap.delete(monitorKey)
            }
          })
          return // 不再往下创建新的 SSH
        }

        // 如果有正在创建的连接，等待它完成
        if (pendingConnections.has(monitorKey)) {
          try {
            logger.info(`等待现有连接创建完成: ${ monitorKey }`)
            await pendingConnections.get(monitorKey)
            // 连接创建完成后，应该能在monitorMap中找到了
            if (monitorMap.has(monitorKey)) {
              const entry = monitorMap.get(monitorKey)
              entry.sockets.add(socket)
              socket.emit('server_status_data', entry.statusData)
              socket.on('disconnect', () => {
                entry.sockets.delete(socket)
                if (entry.sockets.size === 0) {
                  entry.stop()
                  monitorMap.delete(monitorKey)
                }
              })
              return
            }
          } catch (error) {
            logger.error(`等待连接创建失败，继续创建: ${ error.message }`)
          }
        }

        // 创建新连接的Promise
        const createConnectionPromise = (async () => {
          try {
            targetSSHClient = new SSHClient()
            let { jumpSshClients: statusJumpSshClients } = await createTerminal(hostId, socket, targetSSHClient, false)
            jumpSshClients.push(...statusJumpSshClients || [])

            await initPersistentShell()

            // 开始监控
            startMonitoring()

            // 将当前监控放入全局 map
            const stopAll = () => {
              cleanupResources('监控停止')
            }
            const entryObj = { sockets: new Set([socket]), statusData, stop: stopAll }
            monitorMap.set(monitorKey, entryObj)

            // 处理当前 socket 断连
            socket.on('disconnect', (reason) => {
              entryObj.sockets.delete(socket)
              if (entryObj.sockets.size === 0) {
                stopAll()
                monitorMap.delete(monitorKey)
              }
              logger.info(`server-status socket断开: ${ reason }`)
            })

            logger.info(`成功创建服务器监控: ${ monitorKey }`)
            return entryObj

          } finally {
            // 无论成功失败，都要从pending中移除
            pendingConnections.delete(monitorKey)
          }
        })()

        // 将Promise放入pending map
        pendingConnections.set(monitorKey, createConnectionPromise)

        // 等待连接创建完成
        await createConnectionPromise

      } catch (error) {
        logger.error('ws_server_status 事件处理失败:', error.message)
        socket.emit('server_status_error', `连接失败: ${ error.message }`)

        // 全面清理资源，防止泄漏
        cleanupResources('连接失败')

        // 确保从pending中移除
        if (monitorKey) {
          pendingConnections.delete(monitorKey)
        }

        logger.info(`连接失败后已清理资源: ${ monitorKey || 'unknown' }`)
      }
    })

    // 初始化持久化 shell
    const initPersistentShell = async () => {
      return new Promise((resolve, reject) => {
        if (shellReady) return resolve()
        if (!targetSSHClient) return reject(new Error('SSH client not ready'))

        targetSSHClient.exec('/bin/bash --noprofile --norc -i', (err, stream) => {
          if (err) {
            logger.error('创建持久化 shell 失败:', err.message)
            return reject(err)
          }
          persistentShell = stream
          shellReady = true

          persistentShell.write('unset HISTFILE\n')
          logger.info('server-status: 持久化 shell 已就绪')

          let buffer = ''
          const handleData = (data) => {
            buffer += data.toString()
            // 逐行处理，防止分包
            let index
            while ((index = buffer.indexOf('\n')) !== -1) {
              const line = buffer.slice(0, index).trimEnd()
              buffer = buffer.slice(index + 1)
              if (!cmdQueue.length) continue // 无待解析命令
              const current = cmdQueue[0]
              // 判断是否到达结束标记
              if (line === current.marker) {
                // 完整输出拿到了
                cmdQueue.shift()
                current.resolve(stripAnsi(current.output.trim()))
                // 继续处理下一个命令
                if (cmdQueue.length) {
                  sendNextCommand()
                }
              } else {
                current.output += (line + '\n')
              }
            }
          }

          stream.on('data', handleData)
          stream.on('close', () => {
            shellReady = false
            persistentShell = null
            logger.warn('server-status: 持久化 shell 已关闭')
          })
          resolve()
        })
      })
    }

    // 向 shell 发送下一个队列中的命令
    const sendNextCommand = () => {
      if (!cmdQueue.length || !shellReady || !persistentShell) return
      const current = cmdQueue[0]
      persistentShell.write(` ${ current.command }; echo ${ current.marker }\n`) // 每条命令后回显标记
    }

    // --- 修改 executeCommand，使之优先使用持久化 shell -----
    const executeCommand = (command) => {
      // 如果 shell 已就绪，则走队列逻辑
      if (shellReady && persistentShell) {
        return new Promise((resolve, reject) => {
          const marker = `__EZCMD_END_${ ++cmdCounter }__`
          const task = { command, resolve, reject, marker, output: '' }
          cmdQueue.push(task)
          // 如果这是队列里唯一任务，则立即发送
          if (cmdQueue.length === 1) {
            sendNextCommand()
          }
        })
      }
    }

    // 系统信息缓存（只获取一次的信息）
    let staticSystemInfo = {
      cpuCount: null,
      cpuModel: null,
      osInfo: null
    }

    // 服务器状态数据（外层维护，提升及时性）
    let statusData = {
      connect: false,
      cpuInfo: {},
      memInfo: {},
      swapInfo: {},
      drivesInfo: [],
      netstatInfo: {},
      osInfo: {}
    }

    // 统一的资源清理函数
    const cleanupResources = (reason = 'unknown') => {
      // 清理定时器
      if (monitorTimer) {
        clearInterval(monitorTimer)
        monitorTimer = null
      }
      if (sendDataTimer) {
        clearInterval(sendDataTimer)
        sendDataTimer = null
      }

      // 清理持久化 shell
      if (persistentShell) {
        persistentShell.end?.()
        persistentShell = null
      }
      shellReady = false
      cmdQueue.length = 0
      cmdCounter = 0

      // 清理 SSH 连接
      if (targetSSHClient) {
        targetSSHClient.end?.()
        targetSSHClient = null
      }
      jumpSshClients?.forEach(c => c && c.end?.())
      jumpSshClients.length = 0

      // 重置状态变量
      lastNetStats = null
      previousCpuStats = null
      defaultNetInterface = null

      // 清理静态系统信息缓存（可选，如果希望下次重新获取）
      staticSystemInfo = {
        cpuCount: null,
        cpuModel: null,
        osInfo: null
      }

      // 从 pendingConnections 中移除（如果存在）
      if (monitorKey && pendingConnections.has(monitorKey)) {
        pendingConnections.delete(monitorKey)
      }

      logger.info(`已清理服务器监控资源: ${ monitorKey || 'unknown' } - 原因: ${ reason }`)
    }

    // 检查是否是关键的服务器错误
    const isServerCriticalError = (errorMessage) => {
      const criticalErrors = [
        'free: command not found', // free命令不存在
        '/proc/uptime: No such file or directory', // /proc/uptime文件不存在
        '/proc/net/dev: No such file or directory', // /proc/net/dev文件不存在
        '/proc/stat: No such file or directory', // /proc/stat文件不存在
        '/proc/cpuinfo: No such file or directory' // /proc/cpuinfo文件不存在
      ]

      return criticalErrors.some(error => errorMessage.includes(error))
    }

    // 获取静态CPU信息（CPU核心数和型号，只获取一次）
    const getStaticCpuInfo = async () => {
      if (staticSystemInfo.cpuCount !== null && staticSystemInfo.cpuModel !== null) {
        return {
          cpuCount: staticSystemInfo.cpuCount,
          cpuModel: staticSystemInfo.cpuModel
        }
      }

      let cpuCount = 0
      let cpuModel = 'Unknown'

      // 获取CPU核心数
      try {
        const cpuCountResult = await executeCommand('nproc')
        cpuCount = parseInt(cpuCountResult) || 0

        // 如果nproc失败，尝试其他方法
        if (cpuCount === 0) {
          const lscpuResult = await executeCommand('lscpu | grep "^CPU(s):" | head -1')
          const cpuCountMatch = lscpuResult.match(/CPU\(s\):\s*(\d+)/)
          cpuCount = cpuCountMatch ? parseInt(cpuCountMatch[1]) : 0
        }
      } catch (error) {
        logger.warn('获取CPU核心数失败:', error.message)
      }

      // 获取CPU型号
      try {
        const cpuModelResult = await executeCommand('cat /proc/cpuinfo | grep "model name" | head -1')
        const cpuModelMatch = cpuModelResult.match(/model name\s*:\s*(.+)/)
        if (cpuModelMatch) {
          cpuModel = cpuModelMatch[1].trim()
        } else {
          // 如果/proc/cpuinfo失败，尝试lscpu
          const lscpuResult = await executeCommand('lscpu | grep "Model name:" | head -1')
          const lscpuModelMatch = lscpuResult.match(/Model name:\s*(.+)/)
          cpuModel = lscpuModelMatch ? lscpuModelMatch[1].trim() : 'Unknown'
        }
      } catch (error) {
        logger.warn('获取CPU型号失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          logger.error(`执行命令失败：cat /proc/cpuinfo: ${ error.message }`)
          return { cpuCount: 0, cpuModel: 'Unknown' }
        }
      }

      // 缓存结果
      staticSystemInfo.cpuCount = cpuCount
      staticSystemInfo.cpuModel = cpuModel

      return { cpuCount, cpuModel }
    }

    // 解析/proc/stat输出
    const parseProcStat = (procStatOutput) => {
      try {
        const firstLine = procStatOutput.split('\n').find(line => line.startsWith('cpu ')) || ''
        const values = firstLine.trim().split(/\s+/).slice(1).map(Number)
        const idle = values[3] || 0
        const total = values.reduce((a, b) => a + b, 0)
        return { idle, total }
      } catch (error) {
        return null
      }
    }

    // 获取CPU信息（优化的CPU使用率计算）
    const getCpuInfo = async () => {
      let cpuUsage = 0

      try {
        const procStatOutput = await executeCommand('cat /proc/stat')
        const currentCpuStats = parseProcStat(procStatOutput)
        const now = Date.now()

        if (currentCpuStats) {
          if (previousCpuStats && previousCpuStats.timestamp < now) {
            const totalDiff = currentCpuStats.total - previousCpuStats.total
            const idleDiff = currentCpuStats.idle - previousCpuStats.idle
            const timeDiffMs = now - previousCpuStats.timestamp

            // 确保时间差>500ms以获得更准确的计算，避免除零错误
            if (totalDiff > 0 && timeDiffMs > 500) {
              const usageRatio = 1.0 - (idleDiff / totalDiff)
              // 限制在0-100范围内
              cpuUsage = Math.max(0, Math.min(100, usageRatio * 100))
            } else {
              // 时间间隔太短或没有变化，保持上次的值或设为0
              cpuUsage = 0
            }
          } else {
            // 第一次运行，无法计算使用率
            cpuUsage = 0
          }

          // 存储当前统计信息供下次使用
          previousCpuStats = { ...currentCpuStats, timestamp: now }
        }
      } catch (error) {
        logger.warn('获取CPU使用率失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          logger.error(`执行命令失败：cat /proc/stat: ${ error.message }`)
          return { cpuUsage: 0, cpuCount: 0, cpuModel: 'Unknown' }
        }
      }

      // 获取静态CPU信息
      const { cpuCount, cpuModel } = await getStaticCpuInfo()

      // 获取负载平均值
      let loadAvg = [0, 0, 0]
      try {
        const uptimeOutput = await executeCommand('uptime')
        const match = uptimeOutput.match(/load average(?:s)?:\s*([\d.]+)[, ]?\s*([\d.]+)[, ]?\s*([\d.]+)/)
        if (match) {
          loadAvg = [parseFloat(match[1]), parseFloat(match[2]), parseFloat(match[3])]
        }
      } catch (error) {
        // 静默处理负载平均值获取失败
      }

      return {
        cpuUsage: parseFloat(cpuUsage.toFixed(2)),
        cpuCount,
        cpuModel,
        loadAvg
      }
    }

    // 获取内存和交换空间信息（统一处理，支持BusyBox）
    const getMemoryInfo = async () => {
      const defaultReturn = {
        memInfo: { totalMemMb: 0, usedMemMb: 0, freeMemMb: 0, usedMemPercentage: 0, freeMemPercentage: 0 },
        swapInfo: { swapTotal: 0, swapUsed: 0, swapFree: 0, swapPercentage: '0' }
      }

      try {
        // 检查是否为BusyBox环境
        let freeCommand = '\\free -m'
        let isBusyBox = false

        try {
          const busyboxCheck = await executeCommand('busybox --help')
          if (busyboxCheck.includes('BusyBox')) {
            freeCommand = 'free'
            isBusyBox = true
          }
        } catch (err) {
          // 如果检查失败，默认使用 free -m
        }

        const freeOutput = await executeCommand(freeCommand)
        const lines = freeOutput.split('\n')

        // 使用更鲁棒的方式查找内存和交换空间行
        const memLine = lines.find(line => line.trim().startsWith('Mem:'))
        const swapLine = lines.find(line => line.trim().startsWith('Swap:'))

        let memInfo = defaultReturn.memInfo
        let swapInfo = defaultReturn.swapInfo

        // 处理内存信息
        if (memLine) {
          const parts = memLine.trim().split(/\s+/)
          if (parts.length >= 3) {
            let totalVal = parseInt(parts[1], 10)
            let usedVal = parseInt(parts[2], 10)
            let freeVal = parts[3] ? parseInt(parts[3], 10) : (totalVal - usedVal)

            // BusyBox环境下需要从KB转换为MB
            if (isBusyBox) {
              if (!isNaN(totalVal)) totalVal = Math.round(totalVal / 1024)
              if (!isNaN(usedVal)) usedVal = Math.round(usedVal / 1024)
              if (!isNaN(freeVal)) freeVal = Math.round(freeVal / 1024)
            }

            if (!isNaN(totalVal) && !isNaN(usedVal)) {
              const usedMemPercentage = totalVal > 0 ? parseFloat(((usedVal / totalVal) * 100).toFixed(2)) : 0
              const freeMemPercentage = totalVal > 0 ? parseFloat(((freeVal / totalVal) * 100).toFixed(2)) : 0

              memInfo = {
                totalMemMb: totalVal,
                usedMemMb: usedVal,
                freeMemMb: freeVal,
                usedMemPercentage,
                freeMemPercentage
              }
            }
          }
        }

        // 处理交换空间信息
        if (swapLine) {
          const parts = swapLine.trim().split(/\s+/)
          if (parts.length >= 3) {
            let totalVal = parseInt(parts[1], 10)
            let usedVal = parseInt(parts[2], 10)
            let freeVal = parts[3] ? parseInt(parts[3], 10) : (totalVal - usedVal)

            // BusyBox环境下需要从KB转换为MB
            if (isBusyBox) {
              if (!isNaN(totalVal)) totalVal = Math.round(totalVal / 1024)
              if (!isNaN(usedVal)) usedVal = Math.round(usedVal / 1024)
              if (!isNaN(freeVal)) freeVal = Math.round(freeVal / 1024)
            }

            if (!isNaN(totalVal) && !isNaN(usedVal)) {
              const swapPercentage = totalVal > 0 ? ((usedVal / totalVal) * 100).toFixed(1) : '0'

              swapInfo = {
                swapTotal: totalVal,
                swapUsed: usedVal,
                swapFree: freeVal,
                swapPercentage
              }
            }
          }
        } else {
          // 没有交换空间
          swapInfo = { swapTotal: 0, swapUsed: 0, swapFree: 0, swapPercentage: '0' }
        }

        return { memInfo, swapInfo }

      } catch (error) {
        logger.error('获取内存信息失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          logger.error(`执行命令失败：free -m: ${ error.message }`)
        }

        return defaultReturn
      }
    }

    // 获取所有磁盘信息
    const getDrivesInfo = async () => {
      try {
        const dfOutput = await executeCommand('\\df -kP -x tmpfs -x devtmpfs -x proc -x sysfs -x overlay')
        const lines = dfOutput.split('\n').slice(1) // 去掉表头
        const drives = []
        lines.forEach(line => {
          const parts = line.trim().split(/\s+/)
          if (parts.length >= 6) {
            const [filesystem, totalKb, usedKb, freeKb, usedPerc, mountedOn] = parts
            if (!filesystem.startsWith('/dev')) return // 仅物理磁盘
            const totalGb = parseInt(totalKb) / 1024 / 1024
            if (totalGb < 3) return // 过滤掉小于3GB的挂载
            const usedPercentage = parseFloat(usedPerc.replace('%', ''))
            drives.push({
              totalGb: totalGb.toFixed(1),
              filesystem,
              mountedOn,
              usedGb: (parseInt(usedKb) / 1024 / 1024).toFixed(1),
              freeGb: (parseInt(freeKb) / 1024 / 1024).toFixed(1),
              usedPercentage: usedPercentage.toFixed(1),
              freePercentage: (100 - usedPercentage).toFixed(1)
            })
          }
        })
        return drives
      } catch (error) {
        logger.error('获取磁盘信息失败:', error.message)
        return []
      }
    }

    // 获取默认网络接口
    const getDefaultInterface = async () => {
      if (defaultNetInterface) return defaultNetInterface

      try {
        // 尝试从路由表获取默认接口
        const routeOutput = await executeCommand('ip route get 1')
        const match = routeOutput.match(/dev\s+(\S+)/)
        if (match) {
          const iface = match[1].trim()
          if (!iface.match(/^(lo|br-|docker|veth|virbr|tun|tap)/)) {
            defaultNetInterface = iface
            return defaultNetInterface
          }
        }
      } catch (_) {
        // 忽略
      }

      try {
        // 遍历 /sys/class/net 目录，选第一个“真实”设备（存在 device 文件）
        const sysClassOutput = await executeCommand('ls -1 /sys/class/net')
        const interfaces = sysClassOutput.split('\n').map(i => i.trim()).filter(Boolean)

        for (const iface of interfaces) {
          if (iface === 'lo') continue
          // 检查是否是物理接口
          const checkCmd = `test -e /sys/class/net/${ iface }/device && echo yes || echo no`
          const isPhysical = (await executeCommand(checkCmd)).trim() === 'yes'
          if (
            isPhysical &&
            !iface.match(/^(br-|docker|veth|virbr|tun|tap)/)
          ) {
            defaultNetInterface = iface
            return defaultNetInterface
          }
        }
      } catch (_) {
        // 忽略
      }

      try {
        // 取第一个以 enp / ens / eth / eno / wlan 开头的接口
        const netDev = await executeCommand('cat /proc/net/dev')
        const lines = netDev.split('\n').slice(2)
        for (const line of lines) {
          const iface = line.trim().split(':')[0]
          if (iface && iface.match(/^(enp|ens|eth|eno|wlan)/)) {
            defaultNetInterface = iface.trim()
            return defaultNetInterface
          }
        }
      } catch (_) {
        // 忽略
      }

      defaultNetInterface = 'eth0'
      return defaultNetInterface
    }

    // 解析网络设备统计信息
    const parseNetworkStats = async () => {
      try {
        const netDev = await executeCommand('cat /proc/net/dev')
        const lines = netDev.split('\n').slice(2)
        const stats = {}

        for (const line of lines) {
          const parts = line.trim().split(/\s+/)
          if (parts.length < 17) continue

          const iface = parts[0].replace(':', '')

          // 跳过虚拟接口与环回
          if (iface.match(/^(lo|br-|docker|veth|virbr|tun|tap)/)) continue

          const rxBytes = parseInt(parts[1]) || 0
          const txBytes = parseInt(parts[9]) || 0
          stats[iface] = { rxBytes, txBytes }
        }

        return stats
      } catch (error) {
        logger.error('parseNetworkStats 失败:', error.message)
        return null
      }
    }

    // 获取网络信息（优化版）
    const getNetstatInfo = async () => {
      try {
        const currentStats = await parseNetworkStats()
        if (!currentStats) {
          return { total: { inputMb: 0, outputMb: 0 } }
        }

        const defaultInterface = await getDefaultInterface()
        const timestamp = Date.now()
        let netstatInfo = {}

        // 计算总流量（所有接口）
        let totalInput = 0
        let totalOutput = 0
        Object.values(currentStats).forEach(stat => {
          totalInput += stat.rxBytes
          totalOutput += stat.txBytes
        })

        if (lastNetStats && lastNetStats.timestamp < timestamp) {
          const timeDiffSeconds = (timestamp - lastNetStats.timestamp) / 1000

          // 防抖：时间间隔太短或太长（系统卡顿、休眠等）时跳过这次更新
          if (timeDiffSeconds < 0.5 || timeDiffSeconds > 10) {
            return lastNetStats.netstatInfo || { total: { inputMb: '0.000', outputMb: '0.000' } }
          }

          if (timeDiffSeconds > 0.1) {
            // 总流量速率
            netstatInfo.total = {
              inputMb: (safeDelta(totalInput, lastNetStats.totalInput) / timeDiffSeconds / 1024 / 1024).toFixed(3),
              outputMb: (safeDelta(totalOutput, lastNetStats.totalOutput) / timeDiffSeconds / 1024 / 1024).toFixed(3)
            }

            // 默认接口的速率
            if (defaultInterface && currentStats[defaultInterface] && lastNetStats.interfaces[defaultInterface]) {
              const currentRx = currentStats[defaultInterface].rxBytes
              const currentTx = currentStats[defaultInterface].txBytes
              const lastRx = lastNetStats.interfaces[defaultInterface].rxBytes
              const lastTx = lastNetStats.interfaces[defaultInterface].txBytes

              netstatInfo.default = {
                interface: defaultInterface,
                inputMb: (safeDelta(currentRx, lastRx) / timeDiffSeconds / 1024 / 1024).toFixed(3),
                outputMb: (safeDelta(currentTx, lastTx) / timeDiffSeconds / 1024 / 1024).toFixed(3)
              }
            }

            // 各个接口的速率
            Object.keys(currentStats).forEach(interfaceName => {
              if (lastNetStats.interfaces[interfaceName]) {
                const currentInterface = currentStats[interfaceName]
                const lastInterface = lastNetStats.interfaces[interfaceName]

                netstatInfo[interfaceName] = {
                  inputMb: (safeDelta(currentInterface.rxBytes, lastInterface.rxBytes) / timeDiffSeconds / 1024 / 1024).toFixed(3),
                  outputMb: (safeDelta(currentInterface.txBytes, lastInterface.txBytes) / timeDiffSeconds / 1024 / 1024).toFixed(3)
                }
              }
            })
          } else {
            // 时间间隔太短，设为0
            netstatInfo.total = { inputMb: '0.000', outputMb: '0.000' }
            if (defaultInterface) {
              netstatInfo.default = {
                interface: defaultInterface,
                inputMb: '0.000',
                outputMb: '0.000'
              }
            }
          }
        } else {
          // 第一次运行，初始化为0
          netstatInfo.total = { inputMb: '0.000', outputMb: '0.000' }
          if (defaultInterface) {
            netstatInfo.default = {
              interface: defaultInterface,
              inputMb: '0.000',
              outputMb: '0.000'
            }
          }
        }

        // 保存当前状态
        lastNetStats = {
          totalInput,
          totalOutput,
          interfaces: currentStats,
          timestamp,
          netstatInfo
        }

        return netstatInfo
      } catch (error) {
        logger.error('获取网络信息失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          logger.error(`执行命令失败：cat /proc/net/dev: ${ error.message }`)
          return { total: { inputMb: '0.000', outputMb: '0.000' } }
        }

        return { total: { inputMb: '0.000', outputMb: '0.000' } }
      }
    }

    // 获取静态系统信息（只获取一次的信息）
    const getStaticOsInfo = async () => {
      if (staticSystemInfo.osInfo !== null) {
        return staticSystemInfo.osInfo
      }

      const defaultStaticInfo = {
        hostname: 'Unknown',
        type: 'Linux',
        platform: 'linux',
        release: 'Unknown',
        arch: 'Unknown'
      }

      try {
        // 串行执行命令避免并发问题
        let hostname = 'Unknown'
        try {
          hostname = await executeCommand('hostname') || 'Unknown'
        } catch (e) {
          logger.warn('获取hostname失败:', e.message)
        }

        // 通过读取 /etc/os-release 文件获取操作系统信息
        let type = 'Linux'
        let release = 'Unknown'
        let arch = 'Unknown'

        try {
          // 读取 /etc/os-release 文件获取系统信息
          const osReleaseContent = await executeCommand('cat /etc/os-release')
          const osReleaseLines = osReleaseContent.split('\n')

          // 解析系统名称和版本
          osReleaseLines.forEach(line => {
            if (line.startsWith('NAME=')) {
              type = line.replace('NAME=', '').replace(/"/g, '') || 'Linux'
            } else if (line.startsWith('VERSION=')) {
              release = line.replace('VERSION=', '').replace(/"/g, '') || 'Unknown'
            } else if (line.startsWith('PRETTY_NAME=')) {
              // 如果有PRETTY_NAME，可以作为更友好的显示名称
              const prettyName = line.replace('PRETTY_NAME=', '').replace(/"/g, '')
              if (prettyName) {
                type = prettyName.split(' ')[0] // 取第一个词作为系统类型
                // 提取版本信息
                const versionMatch = prettyName.match(/(\d+\.?\d*\.?\d*)/)
                if (versionMatch) {
                  release = versionMatch[1]
                }
              }
            }
          })
        } catch (e) {
          logger.warn('读取 /etc/os-release 失败，尝试使用 uname 命令:', e.message)
          // 如果读取 /etc/os-release 失败，回退到 uname 命令
          try {
            type = await executeCommand('uname -s') || 'Linux'
          } catch (e2) {
            logger.warn('获取系统类型失败:', e2.message)
          }

          try {
            release = await executeCommand('uname -r') || 'Unknown'
          } catch (e2) {
            logger.warn('获取系统版本失败:', e2.message)
          }
        }

        // 获取系统架构
        try {
          arch = await executeCommand('uname -m') || 'Unknown'
        } catch (e) {
          logger.warn('获取系统架构失败:', e.message)
        }

        const staticInfo = {
          hostname: hostname.trim(),
          type: type.trim(),
          platform: 'linux',
          release: release.trim(),
          arch: arch.trim()
        }

        // 缓存结果
        staticSystemInfo.osInfo = staticInfo
        return staticInfo
      } catch (error) {
        logger.error('获取静态系统信息失败:', error.message)
        staticSystemInfo.osInfo = defaultStaticInfo
        return defaultStaticInfo
      }
    }

    // 获取系统信息（结合静态信息和动态信息）
    const getOsInfo = async () => {
      try {
        // 获取静态信息
        const staticInfo = await getStaticOsInfo()

        // 获取动态信息：系统运行时间
        let uptime = 0
        try {
          const uptimeStr = await executeCommand('cat /proc/uptime | cut -d" " -f1') || '0'
          uptime = parseFloat(uptimeStr) || 0
        } catch (e) {
          logger.warn('获取系统运行时间失败:', e.message)

          // 检查是否是关键错误
          if (isServerCriticalError(e.message)) {
            logger.error(`执行命令失败：cat /proc/uptime: ${ e.message }`)
            return { ...staticInfo, uptime: 0 }
          }
        }

        return {
          ...staticInfo,
          uptime
        }
      } catch (error) {
        logger.error('获取系统信息失败:', error.message)
        return {
          hostname: 'Unknown',
          type: 'Linux',
          platform: 'linux',
          release: 'Unknown',
          arch: 'Unknown',
          uptime: 0
        }
      }
    }

    // 更新CPU信息到全局statusData
    const updateCpuInfo = async () => {
      try {
        const cpuInfo = await getCpuInfo()
        statusData.cpuInfo = cpuInfo
        statusData.connect = true // 标记连接状态
      } catch (error) {
        logger.error('更新CPU信息失败:', error.message)
        statusData.cpuInfo = {}
      }
    }

    // 更新内存信息到全局statusData
    const updateMemoryInfo = async () => {
      try {
        const { memInfo, swapInfo } = await getMemoryInfo()
        statusData.memInfo = memInfo
        statusData.swapInfo = swapInfo
        statusData.connect = true
      } catch (error) {
        logger.error('更新内存信息失败:', error.message)
        statusData.memInfo = {}
        statusData.swapInfo = {}
      }
    }

    // 更新磁盘信息到全局statusData
    const updateDrivesInfo = async () => {
      try {
        const drives = await getDrivesInfo()
        statusData.drivesInfo = drives
        statusData.connect = true
      } catch (error) {
        logger.error('更新磁盘信息失败:', error.message)
        statusData.drivesInfo = []
      }
    }

    // 更新网络信息到全局statusData
    const updateNetworkInfo = async () => {
      try {
        const netstatInfo = await getNetstatInfo()
        statusData.netstatInfo = netstatInfo
        statusData.connect = true
      } catch (error) {
        logger.error('更新网络信息失败:', error.message)
        statusData.netstatInfo = {}
      }
    }

    // 更新系统信息到全局statusData
    const updateOsInfo = async () => {
      try {
        const osInfo = await getOsInfo()
        statusData.osInfo = osInfo
        statusData.connect = true
      } catch (error) {
        logger.error('更新系统信息失败:', error.message)
        statusData.osInfo = {}
      }
    }

    // 更新所有服务器状态信息（改为增量更新模式）
    const updateServerStatus = async () => {
      try {
        // 并行执行一些不冲突的数据获取，每完成一个就立即更新statusData
        const updateTasks = [
          updateCpuInfo(),
          updateMemoryInfo(),
          updateDrivesInfo(),
          updateNetworkInfo(),
          updateOsInfo()
        ]

        // 使用Promise.allSettled确保即使某个更新失败，其他更新仍能继续
        const results = await Promise.allSettled(updateTasks)

        // 检查是否有任何成功的更新
        const hasSuccessfulUpdate = results.some(result => result.status === 'fulfilled')
        if (!hasSuccessfulUpdate) {
          // 如果所有更新都失败，标记为断开连接
          statusData.connect = false
        }

      } catch (error) {
        logger.error('更新服务器状态过程中出错:', error.message)
        statusData.connect = false
      }
    }

    // 开始监控（解耦数据收集和数据发送，提升及时性）
    const startMonitoring = () => {
      // 数据收集函数
      const collectData = async () => {
        try {
          // 更新全局statusData
          await updateServerStatus()
        } catch (error) {
          logger.error('数据收集过程中出错:', error.message)
        }
      }

      // 数据发送函数
      const sendData = () => {
        try {
          // 广播给所有监听该主机的 socket
          const entry = monitorMap.get(monitorKey)
          if (entry) {
            entry.statusData = statusData // 保持引用最新
            for (const s of entry.sockets) {
              s.emit('server_status_data', statusData)
            }
          }
        } catch (error) {
          logger.error('数据发送过程中出错:', error.message)
        }
      }

      // 立即执行一次数据收集
      collectData()

      // 每n秒收集一次数据
      monitorTimer = setInterval(collectData, 2000)
      // 每n秒发送一次数据
      sendDataTimer = setInterval(sendData, 1500)
    }

    socket.on('disconnect', (reason) => {
      connectionCount--

      // 如果监控key存在，按照 monitorMap 中的逻辑移除 socket；由之前注册的 stopAll 负责真正清理
      if (monitorKey && monitorMap.has(monitorKey)) {
        const entry = monitorMap.get(monitorKey)
        entry.sockets.delete(socket)
        if (entry.sockets.size === 0) {
          entry.stop()
          monitorMap.delete(monitorKey)
        }
      } else {
        // 非监控socket或尚未建立监控的情况，按旧流程清理
        cleanupResources('socket断开')
      }

      logger.info(`server-status websocket 连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
    })
  })
}