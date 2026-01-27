const path = require('path')
const { Client: SSHClient } = require('ssh2')
const { createTerminal } = require('./terminal')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const { createSecureWs } = require('../utils/ws-tool')

let executeCommand = () => {
  return new Promise((resolve) => {
    resolve('')
  })
}

// 专门用于获取Docker日志的函数，Docker logs 输出通常在 stderr 中
function executeDockerLogsCommand(targetSSHClient, command) {
  return new Promise((resolve, reject) => {
    targetSSHClient.exec(command, (err, stream) => {
      if (err) {
        logger.error('执行Docker logs命令失败:', err)
        return reject(err)
      }

      let stdoutData = ''
      let stderrData = ''

      stream.on('close', () => { // code
        // Docker logs 的输出主要在 stderr，合并所有输出
        const allData = stdoutData + stderrData
        // logger.info(`Docker logs 命令完成, 退出码: ${ code }, 输出长度: ${ allData.length }`)

        if (allData.trim()) {
          resolve(allData)
        } else {
          logger.warn('Docker logs 无输出:', command)
          resolve('')
        }
      })

      stream.on('data', (data) => {
        stdoutData += data.toString('utf8')
      })

      stream.stderr.on('data', (data) => {
        stderrData += data.toString('utf8')
      })

      stream.on('error', (err) => {
        logger.error('Docker logs stream 错误:', err)
        reject(err)
      })
    })
  })
}

async function getDockerLogs(targetSSHClient, containerId, tail = 3000) {
  try {
    // 使用专门的日志获取函数，确保能获取到所有日志
    const logsData = await executeDockerLogsCommand(
      targetSSHClient,
      `docker logs --tail ${ tail } -t ${ containerId }`
    )

    // 如果日志为空，返回提示信息
    if (!logsData || logsData.trim() === '') {
      return '该容器暂无日志输出'
    }

    return logsData
  } catch (error) {
    console.error('获取Docker日志失败:', error)
    return `获取Docker日志失败: ${ error.message || '未知错误' }`
  }
}

async function startDockerContainer(targetSSHClient, containerId) {
  try {
    await executeCommand(targetSSHClient, `docker start ${ containerId }`)
    return { success: true, message: '容器启动成功' }
  } catch (error) {
    console.error('启动Docker容器失败:', error)
    return { success: false, message: error.message || '启动容器失败' }
  }
}

async function stopDockerContainer(targetSSHClient, containerId) {
  try {
    await executeCommand(targetSSHClient, `docker stop ${ containerId }`)
    return { success: true, message: '容器停止成功' }
  } catch (error) {
    console.error('停止Docker容器失败:', error)
    return { success: false, message: error.message || '停止容器失败' }
  }
}

async function restartDockerContainer(targetSSHClient, containerId) {
  try {
    await executeCommand(targetSSHClient, `docker restart ${ containerId }`)
    return { success: true, message: '容器重启成功' }
  } catch (error) {
    console.error('重启Docker容器失败:', error)
    return { success: false, message: error.message || '重启容器失败' }
  }
}

async function deleteDockerContainer(targetSSHClient, containerId) {
  try {
    await executeCommand(targetSSHClient, `docker rm -f ${ containerId }`)
    return { success: true, message: '容器删除成功' }
  } catch (error) {
    console.error('删除Docker容器失败:', error)
    return { success: false, message: error.message || '删除容器失败' }
  }
}

module.exports = (httpServer) => {
  const serverIo = createSecureWs(httpServer, '/docker')

  let connectionCount = 0

  serverIo.on('connection', async (socket) => {
    connectionCount++
    logger.info(`docker websocket 已连接 - 当前连接数: ${ connectionCount }`)

    let targetSSHClient = null
    let jumpSshClients = []
    socket.on('ws_docker', async ({ hostId }) => {
      targetSSHClient = new SSHClient()
      let { jumpSshClients: dockerJumpSshClients } = await createTerminal(hostId, socket, targetSSHClient, false)
      jumpSshClients.push(...dockerJumpSshClients)
      let { getDockerContainers = null, executeCommand: dockerExecuteCommand } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
      executeCommand = dockerExecuteCommand
      if (!getDockerContainers) {
        socket.emit('docker_not_plus')
        socket.disconnect()
        return
      }
      let containersData = await getDockerContainers(targetSSHClient)
      if (!containersData) {
        socket.emit('docker_connect_fail')
        socket.disconnect()
        return
      }
      socket.emit('docker_containers_data', containersData)
      socket.on('docker_get_containers_data', async () => {
        socket.emit('docker_containers_data', await getDockerContainers(targetSSHClient))
      })

      socket.on('docker_get_containers_logs', async ({ containerId, tail = 3000 }) => {
        socket.emit('docker_containers_logs', await getDockerLogs(targetSSHClient, containerId, tail))
      })

      socket.on('docker_start_container', async ({ containerId }) => {
        const result = await startDockerContainer(targetSSHClient, containerId)
        socket.emit('docker_operation_result', result)
      })

      socket.on('docker_stop_container', async ({ containerId }) => {
        const result = await stopDockerContainer(targetSSHClient, containerId)
        socket.emit('docker_operation_result', result)
      })

      socket.on('docker_restart_container', async ({ containerId }) => {
        const result = await restartDockerContainer(targetSSHClient, containerId)
        socket.emit('docker_operation_result', result)
      })

      socket.on('docker_delete_container', async ({ containerId }) => {
        const result = await deleteDockerContainer(targetSSHClient, containerId)
        socket.emit('docker_operation_result', result)
      })
    })

    socket.on('disconnect', (reason) => {
      connectionCount--
      targetSSHClient && targetSSHClient.end()
      jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
      targetSSHClient = null
      jumpSshClients = null
      logger.info(`docker websocket 连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
    })
  })
}
