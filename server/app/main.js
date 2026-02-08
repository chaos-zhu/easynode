require('./logs')
const { createServer } = require('./server')
const initDB = require('./db')
const scheduleJob = require('./schedule')
const getLicenseInfo = require('./utils/get-plus')

async function main() {
  await initDB()
  createServer()
  scheduleJob()
  getLicenseInfo()
}

main()
