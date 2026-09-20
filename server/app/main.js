import './logs.js'
import { createServer } from './server.js'
import initDB from './db.js'
import scheduleJob from './schedule/index.js'
import { startActivation } from './utils/get-plus.js'
import { disconnectAll as disconnectAgentHosts } from './ai/ssh.js'
import { shutdownScheduledTasks } from './services/scheduled-task-service.js'

async function main() {
  await initDB()
  await scheduleJob()
  createServer()
  startActivation()
}

// agent 的 SSH 连接是池化的，进程退出时主动断开，避免在目标主机上留下
// 悬挂的 sshd 会话
let shuttingDown = false
async function shutdown(signal) {
  if (shuttingDown) return
  shuttingDown = true
  logger.info(`收到 ${ signal }，正在清理 AI agent 的 SSH 连接`)
  await shutdownScheduledTasks()
  disconnectAgentHosts()
  process.exit(0)
}

process.on('SIGTERM', () => shutdown('SIGTERM'))
process.on('SIGINT', () => shutdown('SIGINT'))

main()
