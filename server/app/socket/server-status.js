const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { verifyAuthSync } = require('../utils/verify-auth')
const { isAllowedIp } = require('../utils/tools')
const { createTerminal } = require('./terminal')

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/server-status',
    cors: {
      origin: '*'
    }
  })

  let connectionCount = 0

  serverIo.on('connection', (socket) => {
    connectionCount++
    consola.success(`server-status websocket 已连接 - 当前连接数: ${ connectionCount }`)
    let requestIP = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }

    let targetSSHClient = null
    let jumpSshClients = []
    let monitorTimer = null
    let sendDataTimer = null
    let lastNetStats = null // 用于计算网络速率
    let serverError = false // 服务器错误标志
    let previousCpuStats = null // 用于计算CPU使用率
    let defaultNetInterface = null // 默认网络接口

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
      driveInfo: {},
      netstatInfo: {},
      osInfo: {}
    }

    socket.on('ws_server_status', async ({ hostId, token }) => {
      try {
        const { code } = await verifyAuthSync(token, requestIP)
        if (code !== 1) {
          socket.emit('token_verify_fail')
          socket.disconnect()
          return
        }

        targetSSHClient = new SSHClient()
        let { jumpSshClients: statusJumpSshClients } = await createTerminal(hostId, socket, targetSSHClient, false)
        jumpSshClients.push(...statusJumpSshClients || [])

        // 开始监控
        startMonitoring()
      } catch (error) {
        consola.error('ws_server_status 事件处理失败:', error.message)
        socket.emit('server_status_error', `连接失败: ${ error.message }`)
      }
    })

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

    // 设置服务器错误状态并停止监控
    const setServerError = (reason) => {
      if (serverError) return // 已经设置过错误状态

      serverError = true
      consola.error(`检测到服务器关键错误，停止监控: ${ reason }`)

      // 停止监控定时器
      if (monitorTimer) {
        clearInterval(monitorTimer)
        monitorTimer = null
      }

      // 发送错误状态给前端
      socket.emit('server_status_data', {
        connect: false,
        error: true,
        errorReason: reason,
        cpuInfo: {},
        memInfo: {},
        swapInfo: {},
        driveInfo: {},
        netstatInfo: {},
        osInfo: {}
      })
    }

    // 执行SSH命令的通用函数（带重试机制）
    const executeCommand = (command, maxRetries = 2) => {
      return new Promise((resolve, reject) => {
        const attemptExecution = (retryCount) => {
          if (!targetSSHClient || !targetSSHClient._sock || !targetSSHClient._sock.writable) {
            reject(new Error('SSH 连接已断开'))
            return
          }

          targetSSHClient.exec(command, (err, stream) => {
            if (err) {
              if (err.message.includes('Channel open failure') && retryCount < maxRetries) {
                // 通道打开失败，等待一段时间后重试
                setTimeout(() => {
                  attemptExecution(retryCount + 1)
                }, 100 * (retryCount + 1)) // 递增延迟
                return
              }
              reject(err)
              return
            }

            let stdout = ''
            let stderr = ''

            stream
              .on('data', (data) => {
                stdout += data.toString()
              })
              .stderr.on('data', (data) => {
                stderr += data.toString()
              })
              .on('close', (code) => {
                if (code !== 0 && stderr) {
                  reject(new Error(stderr))
                } else {
                  resolve(stdout.trim())
                }
              })
              .on('error', (error) => {
                reject(error)
              })
          })
        }

        attemptExecution(0)
      })
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
        consola.warn('获取CPU核心数失败:', error.message)
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
        consola.warn('获取CPU型号失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          setServerError(`获取CPU型号失败: ${ error.message }`)
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
        const firstLine = procStatOutput.split('\n')[0]
        const values = firstLine.split(' ').slice(2).map(Number)
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
        consola.warn('获取CPU使用率失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          setServerError(`获取CPU使用率失败: ${ error.message }`)
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
        let freeCommand = 'free -m'
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
        consola.error('获取内存信息失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          setServerError(`获取内存信息失败: ${ error.message }`)
        }

        return defaultReturn
      }
    }

    // 获取内存信息（兼容性包装函数）
    const getMemInfo = async () => {
      const { memInfo } = await getMemoryInfo()
      return memInfo
    }

    // 获取Swap信息（兼容性包装函数）
    const getSwapInfo = async () => {
      const { swapInfo } = await getMemoryInfo()
      return swapInfo
    }

    // 获取磁盘信息
    const getDriveInfo = async () => {
      try {
        const driveInfo = await executeCommand('df -kP / | tail -1')
        const driveLine = driveInfo.split(/\s+/)

        const totalKb = parseInt(driveLine[1])
        const usedKb = parseInt(driveLine[2])
        const freeKb = parseInt(driveLine[3])
        const usedPercentage = parseFloat(driveLine[4].replace('%', ''))

        return {
          totalGb: (totalKb / 1024 / 1024).toFixed(1),
          usedGb: (usedKb / 1024 / 1024).toFixed(1),
          freeGb: (freeKb / 1024 / 1024).toFixed(1),
          usedPercentage: usedPercentage.toFixed(1),
          freePercentage: (100 - usedPercentage).toFixed(1)
        }
      } catch (error) {
        consola.error('获取磁盘信息失败:', error.message)
        return { totalGb: '0', usedGb: '0', freeGb: '0', usedPercentage: '0', freePercentage: '0' }
      }
    }

    // 获取默认网络接口
    const getDefaultInterface = async () => {
      if (defaultNetInterface) {
        return defaultNetInterface
      }

      try {
        // 尝试通过路由表获取默认接口
        const routeOutput = await executeCommand('ip route get 1')
        const match = routeOutput.match(/dev\s+(\w+)/)
        if (match) {
          defaultNetInterface = match[1]
          return defaultNetInterface
        }
      } catch (error) {
        // 静默处理，继续尝试其他方法
      }

      try {
        // 备用方法：获取第一个非lo接口
        const netDev = await executeCommand('cat /proc/net/dev')
        const lines = netDev.split('\n').slice(2)
        for (const line of lines) {
          const parts = line.trim().split(/\s+/)
          if (parts.length >= 9 && parts[0]) {
            const interfaceName = parts[0].replace(':', '')
            if (interfaceName !== 'lo') {
              defaultNetInterface = interfaceName
              return defaultNetInterface
            }
          }
        }
      } catch (error) {
        // 静默处理
      }

      return null
    }

    // 解析网络设备统计信息
    const parseNetworkStats = async () => {
      try {
        const netDev = await executeCommand('cat /proc/net/dev')
        const lines = netDev.split('\n').slice(2)
        const stats = {}

        lines.forEach(line => {
          const parts = line.trim().split(/\s+/)
          if (parts.length >= 9 && parts[0]) {
            const interfaceName = parts[0].replace(':', '')
            const rxBytes = parseInt(parts[1]) || 0
            const txBytes = parseInt(parts[9]) || 0
            stats[interfaceName] = { rxBytes, txBytes }
          }
        })

        return stats
      } catch (error) {
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

          if (timeDiffSeconds > 0.1) {
            // 总流量速率
            netstatInfo.total = {
              inputMb: ((totalInput - lastNetStats.totalInput) / timeDiffSeconds / 1024 / 1024).toFixed(3),
              outputMb: ((totalOutput - lastNetStats.totalOutput) / timeDiffSeconds / 1024 / 1024).toFixed(3)
            }

            // 默认接口的速率
            if (defaultInterface && currentStats[defaultInterface] && lastNetStats.interfaces[defaultInterface]) {
              const currentRx = currentStats[defaultInterface].rxBytes
              const currentTx = currentStats[defaultInterface].txBytes
              const lastRx = lastNetStats.interfaces[defaultInterface].rxBytes
              const lastTx = lastNetStats.interfaces[defaultInterface].txBytes

              netstatInfo.default = {
                interface: defaultInterface,
                inputMb: ((currentRx - lastRx) / timeDiffSeconds / 1024 / 1024).toFixed(3),
                outputMb: ((currentTx - lastTx) / timeDiffSeconds / 1024 / 1024).toFixed(3)
              }
            }

            // 各个接口的速率
            Object.keys(currentStats).forEach(interfaceName => {
              if (lastNetStats.interfaces[interfaceName]) {
                const currentInterface = currentStats[interfaceName]
                const lastInterface = lastNetStats.interfaces[interfaceName]

                netstatInfo[interfaceName] = {
                  inputMb: ((currentInterface.rxBytes - lastInterface.rxBytes) / timeDiffSeconds / 1024 / 1024).toFixed(3),
                  outputMb: ((currentInterface.txBytes - lastInterface.txBytes) / timeDiffSeconds / 1024 / 1024).toFixed(3)
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
          timestamp
        }

        return netstatInfo
      } catch (error) {
        consola.error('获取网络信息失败:', error.message)

        // 检查是否是关键错误
        if (isServerCriticalError(error.message)) {
          setServerError(`获取网络信息失败: ${ error.message }`)
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
          consola.warn('获取hostname失败:', e.message)
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
          consola.warn('读取 /etc/os-release 失败，尝试使用 uname 命令:', e.message)
          // 如果读取 /etc/os-release 失败，回退到 uname 命令
          try {
            type = await executeCommand('uname -s') || 'Linux'
          } catch (e2) {
            consola.warn('获取系统类型失败:', e2.message)
          }

          try {
            release = await executeCommand('uname -r') || 'Unknown'
          } catch (e2) {
            consola.warn('获取系统版本失败:', e2.message)
          }
        }

        // 获取系统架构
        try {
          arch = await executeCommand('uname -m') || 'Unknown'
        } catch (e) {
          consola.warn('获取系统架构失败:', e.message)
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
        consola.error('获取静态系统信息失败:', error.message)
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
          consola.warn('获取系统运行时间失败:', e.message)

          // 检查是否是关键错误
          if (isServerCriticalError(e.message)) {
            setServerError(`获取系统运行时间失败: ${ e.message }`)
            return { ...staticInfo, uptime: 0 }
          }
        }

        return {
          ...staticInfo,
          uptime
        }
      } catch (error) {
        consola.error('获取系统信息失败:', error.message)
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
        consola.error('更新CPU信息失败:', error.message)
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
        consola.error('更新内存信息失败:', error.message)
        statusData.memInfo = {}
        statusData.swapInfo = {}
      }
    }

    // 更新磁盘信息到全局statusData
    const updateDriveInfo = async () => {
      try {
        const driveInfo = await getDriveInfo()
        statusData.driveInfo = driveInfo
        statusData.connect = true
      } catch (error) {
        consola.error('更新磁盘信息失败:', error.message)
        statusData.driveInfo = {}
      }
    }

    // 更新网络信息到全局statusData
    const updateNetworkInfo = async () => {
      try {
        const netstatInfo = await getNetstatInfo()
        statusData.netstatInfo = netstatInfo
        statusData.connect = true
      } catch (error) {
        consola.error('更新网络信息失败:', error.message)
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
        consola.error('更新系统信息失败:', error.message)
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
          updateDriveInfo(),
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
        consola.error('更新服务器状态过程中出错:', error.message)
        statusData.connect = false
      }
    }

    // 开始监控（解耦数据收集和数据发送，提升及时性）
    let isCollecting = false
    const startMonitoring = () => {
      // 数据收集函数 - 每2秒执行一次
      const collectData = async () => {
        try {
          if (isCollecting) return
          isCollecting = true
          // 如果已经检测到服务器错误，停止监控
          if (serverError) {
            if (monitorTimer) {
              clearInterval(monitorTimer)
              monitorTimer = null
            }
            if (sendDataTimer) {
              clearInterval(sendDataTimer)
              sendDataTimer = null
            }
            consola.info('服务器存在关键错误，已停止监控')
            return
          }

          // 更新全局statusData
          await updateServerStatus()
        } catch (error) {
          consola.error('数据收集过程中出错:', error.message)
        } finally {
          isCollecting = false
        }
      }

      // 数据发送函数 - 每1秒执行一次
      const sendData = () => {
        try {
          // 如果检测到服务器错误，停止发送
          if (serverError) {
            if (sendDataTimer) {
              clearInterval(sendDataTimer)
              sendDataTimer = null
            }
            return
          }

          // 发送当前statusData给前端
          socket.emit('server_status_data', statusData)
        } catch (error) {
          consola.error('数据发送过程中出错:', error.message)
        }
      }

      // 立即执行一次数据收集
      collectData()

      // 启动定时器（如果没有错误）
      if (!serverError) {
        // 每2秒收集一次数据
        monitorTimer = setInterval(collectData, 3000)
        // 每1秒发送一次数据（1秒后开始，避免与首次收集冲突）
        if (!serverError) {
          sendDataTimer = setInterval(sendData, 1500)
        }
      }
    }

    socket.on('disconnect', (reason) => {
      connectionCount--

      // 清理所有定时器
      if (monitorTimer) {
        clearInterval(monitorTimer)
        monitorTimer = null
      }
      if (sendDataTimer) {
        clearInterval(sendDataTimer)
        sendDataTimer = null
      }

      targetSSHClient && targetSSHClient.end()
      jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())

      // 清理所有状态变量
      targetSSHClient = null
      jumpSshClients = null
      lastNetStats = null
      previousCpuStats = null
      defaultNetInterface = null
      serverError = false

      // 清理系统信息缓存
      staticSystemInfo = {
        cpuCount: null,
        cpuModel: null,
        osInfo: null
      }

      // 重置状态数据
      statusData = {
        connect: false,
        cpuInfo: {},
        memInfo: {},
        swapInfo: {},
        driveInfo: {},
        netstatInfo: {},
        osInfo: {}
      }

      consola.info(`server-status websocket 连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
    })
  })
}