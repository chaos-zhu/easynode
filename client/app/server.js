const http = require('http')
const Koa = require('koa')
const { defaultPort } = require('./config')
const wsOsInfo = require('./socket/monitor')

const httpServer = () => {
  const app = new Koa()
  const server = http.createServer(app.callback())
  serverHandler(app, server)
  const port = process.env.clientPort || defaultPort
  server.listen(port, () => {
    console.log(`Server(http) is running on port:${ port }`)
  })
}

function serverHandler(app, server) {
  wsOsInfo(server)
}

module.exports = {
  httpServer
}