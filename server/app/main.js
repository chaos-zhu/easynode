const { httpServer } = require('./server')
const initDB = require('./db')
const scheduleJob = require('./schedule')
const getLicenseInfo = require('./utils/get-plus')

async function main() {
  await initDB()
  httpServer()
  scheduleJob()
  getLicenseInfo()
}

main()
