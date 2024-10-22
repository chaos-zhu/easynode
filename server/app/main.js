const consola = require('consola')
global.consola = consola
const { httpServer } = require('./server')
const initDB = require('./db')
const scheduleJob = require('./schedule')

async function main() {
  await initDB()
  httpServer()
  scheduleJob()
}

main()
