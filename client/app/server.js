const http = require('http')
const Koa = require('koa')
const { httpPort } = require('./config')
const wsOsInfo = require('./socket/monitor')

const httpServer = () => {
  const app = new Koa()
  const server = http.createServer(app.callback())
  serverHandler(app, server)
  server.listen(httpPort, () => {
    console.log(`Server(http) is running on port:${ httpPort }`)
  })
}

function serverHandler(app, server) {
  wsOsInfo(server)
}

module.exports = {
  httpServer
}