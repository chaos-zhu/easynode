const consola = require('consola')
global.consola = consola
const { httpServer, httpsServer, clientHttpServer } = require('./server')
const initLocal = require('./init')
const scheduleJob = require('./schedule')

scheduleJob()

initLocal()

httpServer()

httpsServer()

clientHttpServer()
