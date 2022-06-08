const Koa = require('koa')
const compose = require('koa-compose')
const http = require('http')
const https = require('https')
const { clientPort } = require('./config')
const { domain, httpPort, httpsPort, certificate } = require('./config')
const middlewares = require('./middlewares')
const wsMonitorOsInfo = require('./socket/monitor')
const wsTerminal = require('./socket/terminal')
const wsClientInfo = require('./socket/clients')
const { throwError } = require('./utils')

const httpServer = () => {

  const app = new Koa()
  const server = http.createServer(app.callback())
  serverHandler(app, server)
  server.listen(httpPort, () => {
    console.log(`Server(http) is running on: http://localhost:${ httpPort }`)
  })
}

const httpsServer = () => {
  if(!certificate) return console.log('未上传证书, 创建https服务失败')
  const app = new Koa()
  const server = https.createServer(certificate, app.callback())
  serverHandler(app, server)
  server.listen(httpsPort, (err) => {
    if (err) return console.log('https server error: ', err)
    console.log(`Server(https) is running: https://${ domain }:${ httpsPort }`)
  })
}

const clientHttpServer = () => {
  const app = new Koa()
  const server = http.createServer(app.callback())
  wsMonitorOsInfo(server)
  server.listen(clientPort, () => {
    console.log(`Client(http) is running on: http://localhost:${ clientPort }`)
  })
}

function serverHandler(app, server) {
  wsTerminal(server)
  wsClientInfo(server)
  app.context.throwError = throwError
  app.use(compose(middlewares))
  app.on('error', (err, ctx) => {
    ctx.status = 500
    ctx.body = {
      status: ctx.status,
      message: `Program Error：${ err.message }`
    }
  })
}

module.exports = {
  httpServer,
  httpsServer,
  clientHttpServer
}