const consola = require('consola')
global.consola = consola
const { httpServer, clientHttpServer } = require('./server')
const initDB = require('./db')
const initEncryptConf = require('./init')
// const scheduleJob = require('./schedule')

async function main() {
  await initDB()
  await initEncryptConf()
  httpServer()
  clientHttpServer()
  // scheduleJob()
}

main()
