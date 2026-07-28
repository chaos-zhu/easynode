import './logs.js'
import { createServer } from './server.js'
import initDB from './db.js'
import scheduleJob from './schedule/index.js'
import { startActivation } from './utils/get-plus.js'

async function main() {
  await initDB()
  createServer()
  scheduleJob()
  startActivation()
}

main()
