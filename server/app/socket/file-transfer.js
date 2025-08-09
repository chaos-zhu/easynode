const path = require('path')
const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const consola = require('consola')
const { verifyAuthSync } = require('../utils/verify-auth')
const { isAllowedIp, fileTransferThrottle } = require('../utils/tools')
const { getConnectionOptions } = require('./terminal')
const { FileTransferDB, HostListDB } = require('../utils/db-class')
const decryptAndExecuteAsync = require('../utils/decrypt-file')

const fileTransferDB = new FileTransferDB().getInstance()
const hostListDB = new HostListDB().getInstance()

// 全局传输任务管理
const activeTasks = new Map() // taskId -> { process, sshClient, status, ... }

// 任务排序函数：运行中的任务优先，然后按updateTime降序
function sortTasks(tasks) {
  return tasks.sort((a, b) => {
    // 状态优先级：running > 其他状态
    const statusPriority = { running: 0 }
    const aPriority = statusPriority[a.status] ?? 1
    const bPriority = statusPriority[b.status] ?? 1

    if (aPriority !== bPriority) {
      return aPriority - bPriority
    }

    // 相同状态按updateTime降序
    return (b.updateTime || 0) - (a.updateTime || 0)
  })
}

// 获取排序后的任务列表（合并数据库和内存状态）
async function getSortedTasksList() {
  const tasks = await fileTransferDB.findAsync({}, { sort: { updateTime: -1 } })

  // 合并内存中的活跃任务状态
  const tasksWithStatus = tasks.map(task => {
    const activeTask = activeTasks.get(task.taskId)
    if (activeTask) {
      return {
        ...task,
        status: activeTask.status,
        progress: activeTask.progress,
        speed: activeTask.speed,
        eta: activeTask.eta,
        errorMessage: activeTask.errorMessage
      }
    }
    return task
  })

  // 按状态和时间重新排序
  return sortTasks(tasksWithStatus)
}

module.exports = (httpServer) => {
  const transferIo = new Server(httpServer, {
    path: '/file-transfer',
    cors: { origin: '*' }
  })

  let connectionCount = 0
  const connectedSockets = new Set() // 跟踪所有连接的socket

  transferIo.on('connection', (socket) => {
    connectionCount++
    connectedSockets.add(socket)
    consola.success(`file-transfer websocket 已连接 - 当前连接数: ${ connectionCount }`)

    // IP白名单检查
    let requestIP = socket.handshake.headers['x-forwarded-for'] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }

    // 连接时发送当前所有任务状态
    socket.on('get_tasks', async ({ token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        return
      }

      try {
        const sortedTasks = await getSortedTasksList()
        socket.emit('tasks_list', sortedTasks)

        // 检查是否有运行中的任务，如果有则启动定时推送
        const runningTasks = sortedTasks.filter(task => task.status === 'running')
        if (runningTasks.length > 0) {
          startProgressBroadcast(socket, token, requestIP)
        }
      } catch (error) {
        socket.emit('error', { message: '获取任务列表失败', error: error.message })
      }
    })

    // 启动传输任务
    socket.on('start_transfer', async (transferConfig) => {
      const { token } = transferConfig
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        return
      }

      try {
        const { createTransferTask = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
        if (!createTransferTask) throw new Error('Plus功能解锁失败: createTransferTask')
        const task = await createTransferTask(transferConfig, socket, hostListDB, fileTransferDB, executeTransfer)
        socket.emit('task_started', { taskId: task.taskId, message: '传输任务已启动' })

        // 广播更新的任务列表
        const updatedTasks = await getSortedTasksList()
        socket.emit('tasks_list', updatedTasks)
      } catch (error) {
        consola.error('启动传输任务失败:', error)
        socket.emit('task_failed', {
          taskId: transferConfig.taskId,
          message: error.message
        })
      }
    })

    // 取消任务
    socket.on('cancel_task', async ({ taskId, token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        return
      }

      try {
        await cancelTransferTask(taskId)
        socket.emit('task_cancelled', { taskId, message: '任务已取消' })
      } catch (error) {
        socket.emit('error', { message: '取消任务失败', error: error.message })
      }
    })

    // 重试任务
    socket.on('retry_task', async ({ taskId, token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        return
      }

      try {
        const task = await fileTransferDB.findOneAsync({ taskId })
        if (!task) {
          throw new Error('任务不存在')
        }

        // 重置任务状态
        await fileTransferDB.updateAsync(
          { taskId },
          {
            $set: {
              status: 'running',
              progress: 0,
              speed: 0,
              errorMessage: null,
              updateTime: Date.now()
            }
          }
        )

        // 重新启动任务（不创建新任务，重用现有任务）
        executeTransfer(task, socket)
        socket.emit('task_started', { taskId: task.taskId, message: '任务重试中' })
      } catch (error) {
        socket.emit('error', { message: '重试任务失败', error: error.message })
      }
    })

    // 删除单个任务
    socket.on('delete_task', async ({ taskId, token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        return
      }

      try {
        const task = await fileTransferDB.findOneAsync({ taskId })
        if (!task) {
          throw new Error('任务不存在')
        }

        // 检查任务状态，不允许删除正在进行的任务
        if (task.status === 'running') {
          throw new Error('无法删除正在进行的任务，请先取消任务')
        }

        // 从数据库删除任务
        await fileTransferDB.removeAsync({ taskId })

        socket.emit('task_deleted', { taskId, message: '任务已删除' })

        // 广播任务列表更新
        const updatedTasks = await getSortedTasksList()
        socket.emit('tasks_list', updatedTasks)
      } catch (error) {
        socket.emit('error', { message: '删除任务失败', error: error.message })
      }
    })

    // 清空已完成任务
    socket.on('clear_completed_tasks', async ({ token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        return
      }

      try {
        // 删除所有已完成、失败、取消的任务
        const result = await fileTransferDB.removeAsync(
          {
            status: { $in: ['completed', 'failed', 'cancelled'] }
          },
          { multi: true }
        )

        socket.emit('tasks_cleared', {
          count: result,
          message: `已清空 ${ result } 个任务`
        })

        // 广播任务列表更新
        const updatedTasks = await getSortedTasksList()
        socket.emit('tasks_list', updatedTasks)
      } catch (error) {
        socket.emit('error', { message: '清空任务失败', error: error.message })
      }
    })

    socket.on('disconnect', () => {
      connectionCount--
      connectedSockets.delete(socket)

      // 清理该socket的进度广播定时器
      stopProgressBroadcast(socket)
      consola.info(`file-transfer websocket 断开连接 - 当前连接数: ${ connectionCount }`)
    })
  })

  return transferIo
}

// 执行传输任务
async function executeTransfer(taskData, socket) {
  const { taskId } = taskData

  try {
    // 更新任务状态为运行中，确保updateTime是最新的
    await updateTaskStatus(taskId, 'running', socket)

    // 获取源主机连接配置
    const sourceOptions = await getConnectionOptions(taskData.sourceHostId)

    // 建立SSH连接到源主机
    const { sshClient } = await connectToHost(sourceOptions)

    // 注册活跃任务
    activeTasks.set(taskId, {
      sshClient,
      status: 'running',
      progress: 0,
      speed: 0,
      startTime: Date.now(),
      keyFile: null, // 用于跟踪临时密钥文件
      totalFiles: taskData.sourcePaths.length, // 初始化文件总数
      sourcePaths: taskData.sourcePaths // 保存源文件路径信息
    })

    // 只支持Rsync传输
    if (taskData.method === 'rsync') {
      await executeRsyncTransfer(taskData, sshClient, socket)
    } else {
      throw new Error(`不支持的传输方法: ${ taskData.method }，仅支持 rsync`)
    }

    // 传输完成
    await updateTaskStatus(taskId, 'completed', socket)

  } catch (error) {
    consola.error(`传输任务 ${ taskId } 失败:`, error)
    await updateTaskStatus(taskId, 'failed', socket, error.message)
  } finally {
    // 清理资源
    const activeTask = activeTasks.get(taskId)
    if (activeTask) {
      if (activeTask.sshClient) {
        activeTask.sshClient.end()
      }
      activeTasks.delete(taskId)
    }
  }
}

// Rsync传输实现
async function executeRsyncTransfer(taskData, sshClient, socket) {
  const { taskId, sourcePaths, targetPath } = taskData

  // 获取目标主机信息
  const targetConnectionData = await getConnectionOptions(taskData.targetHostId)
  const targetOptions = targetConnectionData.authInfo
  const targetHostAuthType = targetOptions.password ? 'password' : 'privateKey'

  consola.info(`目标主机认证方式: ${ targetHostAuthType }`)

  // 构建Rsync命令
  let rsyncCmd = []
  let envVars = {}

  // ssh密钥tmp路径
  let keyFile = null

  // 如果目标主机使用密码认证，源主机需使用sshpass
  if (targetHostAuthType === 'password') {
    // 检查源主机sshpass是否可用
    try {
      await checkSshpassAvailable(sshClient)
      // 使用环境变量方式传递密码，避免命令行参数解析问题
      envVars.SSHPASS = targetOptions.password
      rsyncCmd.push('sshpass', '-e') // -e 表示从环境变量读取密码
    } catch (error) {
      throw new Error('源主机未安装sshpass工具，无法进行密码认证传输。请使用密钥认证或在源主机安装sshpass: apt-get install sshpass 或 yum install sshpass')
    }
  } else {
    keyFile = await createRemoteTempKeyFile(sshClient, targetOptions.privateKey)
  }

  rsyncCmd.push('rsync', '-avz', '--progress', '--partial') // 归档、详细、压缩、进度、支持断点续传

  // 添加增量同步和安全选项
  rsyncCmd.push('--inplace', '--append') // 断点续传关键选项

  // 添加更详细的进度输出选项
  rsyncCmd.push('--stats', '--human-readable', '--itemize-changes') // 统计信息、可读格式、详细变更

  // 构建SSH命令选项
  const sshOptions = [
    '-p', (targetOptions.port || 22).toString(),
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'GlobalKnownHostsFile=/dev/null'
  ]

  // 根据认证类型设置不同的SSH选项
  if (targetOptions.password) {
    sshOptions.push('-o', 'PreferredAuthentications=password')
  } else {
    sshOptions.push('-o', 'BatchMode=yes')
  }

  if (keyFile) {
    sshOptions.push('-i', `"${ keyFile }"`)
    // 记录临时密钥文件路径到活跃任务中
    const activeTask = activeTasks.get(taskId)
    if (activeTask) {
      activeTask.keyFile = keyFile
    }
  }

  // 封装成一个整体的 SSH 命令，放到双引号内，确保 rsync 正确解析
  const sshCmd = `ssh ${ sshOptions.join(' ') } -o LogLevel=ERROR`
  rsyncCmd.push('-e', `"${ sshCmd }"`)

  // 添加传输选项
  if (taskData.options.delete) {
    rsyncCmd.push('--delete')
  }
  if (taskData.options.excludePatterns && taskData.options.excludePatterns.length > 0) {
    taskData.options.excludePatterns.forEach(pattern => {
      rsyncCmd.push('--exclude', pattern)
    })
  }

  // 添加源和目标路径
  rsyncCmd.push(...sourcePaths.map(item => item.path))
  rsyncCmd.push(`${ targetOptions.username }@${ targetOptions.host }:"${ targetPath }"`)

  consola.info(`执行Rsync命令: ${ rsyncCmd.join(' ') }`)
  if (Object.keys(envVars).length > 0) {
    consola.info(`环境变量: ${ Object.keys(envVars).join(', ') }`)
  }

  return new Promise((resolve, reject) => {
    // 在源主机上执行Rsync命令
    let finalCommand = rsyncCmd.join(' ')

    // 环境变量，需要在命令前设置
    if (Object.keys(envVars).length > 0) {
      const envString = Object.entries(envVars)
        .map(([key, value]) => `${ key }='${ value.replace(/'/g, '\'"\'"\'') }'`)
        .join(' ')
      finalCommand = `${ envString } ${ finalCommand }`
    }

    // consola.info(`最终Rsync命令: ${ finalCommand }`)
    let start = false
    sshClient.exec(finalCommand, (err, stream) => {
      if (err) {
        reject(err)
        return
      }

      let errorOutput = ''
      const activeTask = activeTasks.get(taskId)

      stream.on('close', async (code) => {
        if (code === 0) {
          // 传输成功，设置为校验状态
          const activeTask = activeTasks.get(taskId)
          if (activeTask && activeTask.progressTracker) {
            activeTask.progressTracker.isVerifying = true
            await updateTaskProgress(taskId, activeTask.progressTracker, socket)
          }
          consola.success(`Rsync传输完成: ${ taskId }`)
          resolve()
        } else {
          consola.error(`Rsync传输失败: ${ taskId }, 退出码: ${ code }`)
          reject(new Error(`Rsync传输失败: ${ errorOutput || '未知错误' }`))
        }
      })

      stream.on('data', (data) => {
        if (!start) {
          start = true
          // 清理密钥文件并从内存中移除
          if (activeTask.keyFile) {
            cleanupRemoteKeyFile(activeTask.sshClient, activeTask.keyFile)
          }
          return
        }
        fileTransferThrottle(parseRsyncProgress(data.toString(), taskId, socket))
      })

      stream.stderr.on('data', (data) => {
        if (!start) {
          start = true
          // 清理密钥文件并从内存中移除
          if (activeTask.keyFile) {
            cleanupRemoteKeyFile(activeTask.sshClient, activeTask.keyFile)
          }
          return
        }
        const output = data.toString()
        errorOutput += output
        consola.warn(`Rsync stderr: ${ output }`)

        // 解析错误信息中的进度信息
        fileTransferThrottle(parseRsyncProgress(output, taskId, socket))
      })

      // 存储stream引用以支持取消操作
      if (activeTask) {
        activeTask.stream = stream
      }
    })
  })
}

// 解析Rsync进度
function parseRsyncProgress(output, taskId, socket) {
  const activeTask = activeTasks.get(taskId)
  if (!activeTask) return

  // 初始化进度跟踪器（如果不存在）
  if (!activeTask.progressTracker) {
    activeTask.progressTracker = {
      totalFiles: activeTask.totalFiles || 1,
      completedFiles: 0,
      currentFile: null,
      files: new Map(), // 文件路径 -> 进度信息
      overallProgress: 0,
      isVerifying: false
    }
  }

  const tracker = activeTask.progressTracker
  const outputLine = output.trim()

  // 添加调试日志
  consola.info(`Rsync输出 [${ taskId }]: "${ outputLine }"`)

  // 检测是否在校验阶段
  if (outputLine.includes('verifying') ||
      outputLine.includes('checking') ||
      outputLine.includes('delta-transmission disabled') ||
      (tracker.overallProgress >= 100 && outputLine.includes('receiving'))) {
    if (!tracker.isVerifying) {
      tracker.isVerifying = true
      updateTaskProgress(taskId, tracker, socket)
    }
    return
  }

  // 如果还没有当前文件，且总文件数为1，使用第一个源文件作为当前文件
  if (!tracker.currentFile && tracker.totalFiles === 1) {
    const activeTask = activeTasks.get(taskId)
    if (activeTask && activeTask.sourcePaths && activeTask.sourcePaths.length > 0) {
      const sourcePath = activeTask.sourcePaths[0].path
      const fileName = sourcePath.split('/').pop()
      tracker.currentFile = fileName || sourcePath
      if (!tracker.files.has(tracker.currentFile)) {
        tracker.files.set(tracker.currentFile, {
          progress: 0,
          size: activeTask.sourcePaths[0].size || 0,
          transferred: 0,
          speed: 0,
          status: 'transferring'
        })
      }
      consola.info(`单文件传输初始化: ${ tracker.currentFile }`)
    }
  }

  // 检测新文件开始传输
  // 模式1: itemize-changes 格式 - <f+++++++++ filename
  let filePathMatch = outputLine.match(/^<f\+{5,}\s+(.+)$/)
  if (filePathMatch) {
    const filePath = filePathMatch[1].trim()
    tracker.currentFile = filePath
    if (!tracker.files.has(filePath)) {
      tracker.files.set(filePath, {
        progress: 0,
        size: 0,
        transferred: 0,
        speed: 0,
        status: 'transferring'
      })
    }
    consola.info(`检测到新文件传输(itemize格式): ${ filePath }`)
    return
  }

  // 模式2: 传统文件路径格式
  filePathMatch = outputLine.match(/^([^\s]+\/[^\s]+|[^\s]+\.[^\s]+)\s*$/)
  if (filePathMatch && !outputLine.includes('%')) {
    const filePath = filePathMatch[1]
    tracker.currentFile = filePath
    if (!tracker.files.has(filePath)) {
      tracker.files.set(filePath, {
        progress: 0,
        size: 0,
        transferred: 0,
        speed: 0,
        status: 'transferring'
      })
    }
    consola.info(`检测到新文件传输(传统格式): ${ filePath }`)
    return
  }

  // 解析进度信息
  let fileProgress = null
  let speed = 0
  let eta = 0
  let transferred = 0

  // 模式1: 标准格式 - 1,024,000 100% 1.23MB/s 0:00:30 (xfr#1, to-chk=0/1)
  let match = outputLine.match(/(\d+(?:,\d+)*)\s+(\d+)%\s+([\d.]+)([KMGT]?B\/s)\s+(\d+):(\d+):(\d+)/)
  if (match) {
    const [, transferredStr, percentage, speedVal, speedUnit, hours, minutes, seconds] = match
    fileProgress = parseInt(percentage)
    transferred = parseInt(transferredStr.replace(/,/g, ''))
    const unitFactor = { 'B/s': 1, 'KB/s': 1024, 'MB/s': 1024 ** 2, 'GB/s': 1024 ** 3, 'TB/s': 1024 ** 4 }
    speed = parseFloat(speedVal) * (unitFactor[speedUnit] || 1)
    eta = parseInt(hours) * 3600 + parseInt(minutes) * 60 + parseInt(seconds)
    consola.info(`Rsync标准格式解析 [${ taskId }]: ${ fileProgress }%, 速度: ${ speedVal }${ speedUnit }, ETA: ${ eta }s`)
  } else {
    // 模式2: 简化格式 - 100% 1.23MB/s
    match = outputLine.match(/(\d+)%\s+([\d.]+)([KMGT]?B\/s)/)
    if (match) {
      fileProgress = parseInt(match[1])
      const unit = match[3]
      const unitFactor = { 'B/s': 1, 'KB/s': 1024, 'MB/s': 1024 ** 2, 'GB/s': 1024 ** 3, 'TB/s': 1024 ** 4 }
      speed = parseFloat(match[2]) * (unitFactor[unit] || 1)
      consola.info(`Rsync简化格式解析 [${ taskId }]: ${ fileProgress }%, 速度: ${ match[2] }${ unit }`)
    } else {
      // 模式3: 最简格式 - 只有百分比
      match = outputLine.match(/(\d+)%/)
      if (match) {
        fileProgress = parseInt(match[1])
        consola.info(`Rsync百分比解析 [${ taskId }]: ${ fileProgress }%`)
      }
    }
  }

  // 检测文件传输完成 - to-chk=x/y 格式
  const checkMatch = outputLine.match(/to-chk=(\d+)\/(\d+)/)
  if (checkMatch) {
    const [, remaining, total] = checkMatch
    const completed = parseInt(total) - parseInt(remaining)
    tracker.completedFiles = completed
    tracker.totalFiles = parseInt(total)

    // 如果当前文件进度是100%，标记为完成并清除当前文件
    if (tracker.currentFile && fileProgress === 100) {
      const fileInfo = tracker.files.get(tracker.currentFile)
      if (fileInfo) {
        fileInfo.progress = 100
        fileInfo.status = 'completed'
        fileInfo.transferred = transferred
        // 清除当前文件，为下一个文件做准备
        consola.info(`文件传输完成: ${ tracker.currentFile }`)
        tracker.currentFile = null
      }
    }

    consola.info(`传输进度: ${ completed }/${ total } 文件完成`)
  }

  // 更新当前文件进度
  if (fileProgress !== null) {
    // 如果没有当前文件，但有进度信息，尝试找到正在传输的文件
    if (!tracker.currentFile && tracker.files.size > 0) {
      // 找到最后一个未完成的文件作为当前文件
      for (const [fileName, fileInfo] of tracker.files.entries()) {
        if (fileInfo.status === 'transferring' && fileInfo.progress < 100) {
          tracker.currentFile = fileName
          break
        }
      }
    }

    // 更新当前文件进度
    if (tracker.currentFile) {
      const fileInfo = tracker.files.get(tracker.currentFile)
      if (fileInfo) {
        fileInfo.progress = fileProgress
        fileInfo.speed = speed
        fileInfo.transferred = transferred
        if (fileProgress === 100) {
          fileInfo.status = 'completed'
          // 文件完成后清除当前文件，为下一个文件做准备
          consola.info(`文件传输完成: ${ tracker.currentFile }`)
          tracker.currentFile = null
        }
      }
    } else {
      // 如果仍然没有当前文件，记录警告但继续处理
      consola.warn(`收到进度信息但没有当前文件 [${ taskId }]: ${ fileProgress }%`)
    }
  }

  // 计算总体进度
  if (tracker.totalFiles > 0) {
    if (tracker.totalFiles === 1) {
      // 单文件传输：直接使用当前文件进度
      if (tracker.currentFile && tracker.files.has(tracker.currentFile)) {
        const currentFileInfo = tracker.files.get(tracker.currentFile)
        tracker.overallProgress = currentFileInfo ? currentFileInfo.progress : 0
      } else {
        // 如果没有文件信息，使用解析出的fileProgress
        tracker.overallProgress = fileProgress || 0
      }
    } else {
      // 多文件传输：基于已完成文件数 + 当前文件进度的总体进度
      let overallProgress = (tracker.completedFiles / tracker.totalFiles) * 100
      if (tracker.currentFile && tracker.files.has(tracker.currentFile)) {
        const currentFileInfo = tracker.files.get(tracker.currentFile)
        if (currentFileInfo && currentFileInfo.status !== 'completed') {
          overallProgress += (currentFileInfo.progress / tracker.totalFiles)
        }
      }
      tracker.overallProgress = Math.min(100, Math.round(overallProgress))
    }
  }

  // 更新活跃任务状态
  activeTask.progress = tracker.overallProgress
  activeTask.speed = speed

  updateTaskProgress(taskId, tracker, socket)
}

// 更新任务进度
async function updateTaskProgress(taskId, progressTracker, socket) {
  try {
    // 准备数据库更新数据
    const updateData = {
      progress: progressTracker.overallProgress,
      updateTime: Date.now()
    }

    // 如果在校验阶段，添加状态
    if (progressTracker.isVerifying) {
      updateData.status = 'verifying'
    }

    await fileTransferDB.updateAsync(
      { taskId },
      { $set: updateData }
    )

    // 准备发送给前端的详细进度数据
    const activeTask = activeTasks.get(taskId)
    const progressData = {
      taskId,
      overallProgress: progressTracker.overallProgress,
      completedFiles: progressTracker.completedFiles,
      totalFiles: progressTracker.totalFiles,
      currentFile: progressTracker.currentFile,
      isVerifying: progressTracker.isVerifying,
      speed: activeTask ? activeTask.speed : 0,
      files: Array.from(progressTracker.files.entries()).map(([path, info]) => ({
        path,
        progress: info.progress,
        status: info.status,
        speed: info.speed,
        transferred: info.transferred
      }))
    }

    consola.info(`推送进度更新 [${ taskId }]:`, {
      overall: progressData.overallProgress,
      files: `${ progressData.completedFiles }/${ progressData.totalFiles }`,
      current: progressData.currentFile,
      speed: `${ (progressData.speed / 1024 / 1024).toFixed(1) }MB/s`,
      verifying: progressData.isVerifying
    })

    // 发送给原始socket（如果存在且连接）
    if (socket && socket.connected) {
      socket.emit('task_progress', progressData)
    }
  } catch (error) {
    consola.error('更新任务进度失败:', error)
  }
}

// 更新任务状态
async function updateTaskStatus(taskId, status, socket, errorMessage = null) {
  try {
    const updateData = {
      status,
      updateTime: Date.now()
    }

    if (errorMessage) {
      updateData.errorMessage = errorMessage
    }

    await fileTransferDB.updateAsync({ taskId }, { $set: updateData })

    // 更新内存中的状态
    const activeTask = activeTasks.get(taskId)
    if (activeTask) {
      activeTask.status = status
      if (errorMessage) {
        activeTask.errorMessage = errorMessage
      }
    }

    // 通知前端
    socket.emit('task_status_changed', {
      taskId,
      status,
      errorMessage
    })
  } catch (error) {
    consola.error('更新任务状态失败:', error)
  }
}

// 取消传输任务
async function cancelTransferTask(taskId) {
  const activeTask = activeTasks.get(taskId)

  if (activeTask) {
    // 终止SSH连接
    if (activeTask.sshClient) {
      activeTask.sshClient.end()
    }
    activeTasks.delete(taskId)
  }

  // 更新数据库状态
  await fileTransferDB.updateAsync(
    { taskId },
    {
      $set: {
        status: 'cancelled',
        updateTime: Date.now()
      }
    }
  )
}

// 连接到主机（文件传输专用，直连不走代理）
async function connectToHost(connectionOptions) {
  return new Promise((resolve, reject) => {
    const sshClient = new SSHClient()

    sshClient.on('ready', () => {
      resolve({ sshClient })
    })

    sshClient.on('error', (err) => {
      reject(err)
    })

    // 直接连接，不使用代理
    sshClient.connect(connectionOptions.authInfo)
  })
}

// 检查sshpass工具是否可用
async function checkSshpassAvailable(sshClient) {
  return new Promise((resolve, reject) => {
    sshClient.exec('which sshpass', (err, stream) => {
      if (err) {
        reject(err)
        return
      }

      let output = ''
      stream.on('close', (code) => {
        if (code === 0 && output.trim()) {
          resolve(true)
        } else {
          reject(new Error('sshpass not found'))
        }
      })

      stream.on('data', (data) => {
        output += data.toString()
      })

      stream.stderr.on('data', () => {
        // 忽略stderr
      })
    })
  })
}

// 在源主机上创建临时密钥文件
async function createRemoteTempKeyFile(sshClient, privateKey) {
  return new Promise((resolve, reject) => {
    const remotePath = `/tmp/easynode_key_${ Date.now() }_${ Math.random().toString(36).slice(2) }`
    sshClient.sftp((err, sftp) => {
      if (err) return reject(err)
      // 打开文件句柄
      sftp.open(remotePath, 'w', 0o600, (openErr, handle) => {
        if (openErr) {
          sftp.end()
          return reject(openErr)
        }
        // 写入私钥内容（Buffer）
        const keyBuffer = Buffer.from(privateKey, 'utf-8')
        sftp.write(handle, keyBuffer, 0, keyBuffer.length, 0, (writeErr) => {
          if (writeErr) {
            sftp.close(handle, () => sftp.end())
            return reject(writeErr)
          }
          sftp.close(handle, (closeErr) => {
            sftp.end()
            if (closeErr) return reject(closeErr)
            resolve(remotePath)
          })
        })
      })
    })
  })
}

// 安全清理远程密钥文件
function cleanupRemoteKeyFile(sshClient, keyFile) {
  if (!keyFile || !sshClient) return

  consola.info(`清理远程密钥文件: ${ keyFile }`)

  // 先删除文件，再验证删除
  // const cleanupCmd = `rm -f "${ keyFile }" && if [ -f "${ keyFile }" ]; then echo "CLEANUP_FAILED"; else echo "CLEANUP_SUCCESS"; fi`
  const cleanupCmd = 'cd /tmp && rm -f easynode_key_* && if ls easynode_key_* 2>/dev/null; then echo "CLEANUP_FAILED"; else echo "CLEANUP_SUCCESS"; fi'
  sshClient.exec(cleanupCmd, (err, stream) => {
    if (err) {
      consola.error('清理密钥文件时SSH错误:', err)
      return
    }

    let output = ''
    stream.on('data', (data) => {
      output += data.toString()
    })

    stream.on('close', () => {
      if (output.includes('CLEANUP_SUCCESS')) {
        consola.success(`密钥文件清理成功: ${ keyFile }`)
      } else if (output.includes('CLEANUP_FAILED')) {
        consola.error(`密钥文件清理失败: ${ keyFile }`)
        // 强制清理尝试 - 覆盖后删除
        const forceCleanup = `echo "" > "${ keyFile }" && rm -f "${ keyFile }"`
        sshClient.exec(forceCleanup, () => {
          consola.info(`强制清理密钥文件: ${ keyFile }`)
        })
      } else {
        consola.warn(`密钥文件清理状态未知: ${ keyFile }`)
      }
    })

    stream.stderr.on('data', (data) => {
      consola.warn('清理密钥文件stderr:', data.toString())
    })
  })
}

// 定时进度广播管理
const progressBroadcastTimers = new Map() // socket -> timer

// 启动进度广播
function startProgressBroadcast(socket, token, requestIP) {
  // 如果该socket已经有定时器，先清除
  if (progressBroadcastTimers.has(socket)) {
    clearInterval(progressBroadcastTimers.get(socket))
  }

  // 启动新的定时器，每秒检查并推送运行中任务的进度
  const timer = setInterval(async () => {
    try {
      // 验证token是否仍然有效
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        // token失效，停止广播
        stopProgressBroadcast(socket)
        return
      }

      // 检查是否还有运行中的任务
      const runningTasks = Array.from(activeTasks.values()).filter(task => task.status === 'running')
      if (runningTasks.length === 0) {
        // 没有运行中的任务，停止广播
        consola.info('没有运行中的任务，停止进度广播')
        stopProgressBroadcast(socket)
        return
      }

      // 推送所有运行中任务的最新进度
      for (const [taskId, activeTask] of activeTasks.entries()) {
        if (activeTask.status === 'running' && activeTask.progressTracker) {
          const progressData = {
            taskId,
            overallProgress: activeTask.progressTracker.overallProgress || 0,
            completedFiles: activeTask.progressTracker.completedFiles || 0,
            totalFiles: activeTask.progressTracker.totalFiles || 1,
            currentFile: activeTask.progressTracker.currentFile,
            isVerifying: activeTask.progressTracker.isVerifying || false,
            speed: activeTask.speed || 0
          }

          // 检查socket是否仍然连接
          if (socket.connected) {
            socket.emit('task_progress', progressData)
          } else {
            // socket已断开，停止广播
            stopProgressBroadcast(socket)
            return
          }
        }
      }
    } catch (error) {
      consola.error('进度广播出错:', error)
      stopProgressBroadcast(socket)
    }
  }, 1500)

  progressBroadcastTimers.set(socket, timer)
  consola.info('已启动进度广播定时器')
}

// 停止进度广播
function stopProgressBroadcast(socket) {
  const timer = progressBroadcastTimers.get(socket)
  if (timer) {
    clearInterval(timer)
    progressBroadcastTimers.delete(socket)
    consola.info('已停止进度广播定时器')
  }
}

