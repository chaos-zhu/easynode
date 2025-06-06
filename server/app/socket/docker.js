const path = require('path')
const { Server } = require('socket.io')
const { Client: SSHClient } = require('ssh2')
const { clientIPHeader } = require('../config')
const { verifyAuthSync } = require('../utils/verify-auth')
const { isAllowedIp } = require('../utils/tools')
const { createTerminal } = require('./terminal')
const decryptAndExecuteAsync = require('../utils/decrypt-file')

module.exports = (httpServer) => {
  const serverIo = new Server(httpServer, {
    path: '/docker',
    cors: {
      origin: '*'
    }
  })

  let connectionCount = 0

  serverIo.on('connection', (socket) => {
    connectionCount++
    consola.success(`docker websocket 已连接 - 当前连接数: ${ connectionCount }`)
    let requestIP = socket.handshake.headers[clientIPHeader] || socket.handshake.address
    if (!isAllowedIp(requestIP)) {
      socket.emit('ip_forbidden', 'IP地址不在白名单中')
      socket.disconnect()
      return
    }
    consola.success('docker websocket 已连接')
    let targetSSHClient = null
    let jumpSshClients = []
    socket.on('ws_docker', async ({ hostId, token }) => {
      const { code } = await verifyAuthSync(token, requestIP)
      if (code !== 1) {
        socket.emit('token_verify_fail')
        socket.disconnect()
        return
      }
      targetSSHClient = new SSHClient()
      let { jumpSshClients: dockerJumpSshClients } = await createTerminal(hostId, socket, targetSSHClient, false)
      jumpSshClients.push(...dockerJumpSshClients)
      let { getDockerContainers = null, getDockerLogs = null } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
      if (!getDockerContainers || !getDockerLogs) {
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

      socket.on('docker_get_containers_logs', async ({ containerId, tail = 1000 }) => {
        socket.emit('docker_containers_logs', await getDockerLogs(targetSSHClient, containerId, tail))
      })
    })

    socket.on('disconnect', (reason) => {
      connectionCount--
      targetSSHClient && targetSSHClient.end()
      jumpSshClients?.forEach(sshClient => sshClient && sshClient.end())
      targetSSHClient = null
      jumpSshClients = null
      consola.info(`docker websocket 连接断开: ${ reason } - 当前连接数: ${ connectionCount }`)
    })
  })
}
