const { httpServer, httpsServer, clientHttpServer } = require('./server')
const initLocal = require('./init')

initLocal()

httpServer()

httpsServer()

clientHttpServer()