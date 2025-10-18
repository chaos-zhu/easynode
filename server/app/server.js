const Koa = require('koa')
const compose = require('koa-compose') // 组合中间件，简化写法
const http = require('http')
const { httpPort } = require('./config')
const middlewares = require('./middlewares')
const wsRdp = require('./socket/rdp')
const wsTerminal = require('./socket/terminal')
const wsSftpV2 = require('./socket/sftp-v2')
const wsDocker = require('./socket/docker')
const wsOnekey = require('./socket/onekey')
const wsServerStatus = require('./socket/server-status')
const wsFileTransfer = require('./socket/file-transfer')
const { throwError } = require('./utils/tools')

const httpServer = () => {
  const app = new Koa()
  const server = http.createServer(app.callback())
  serverHandler(app, server)
  // ws一直报跨域的错误：参照官方文档使用createServer API创建服务
  server.listen(httpPort, () => {
    consola.success(`Server(http) is running on: http://localhost:${ httpPort }`)
  })
}

// 服务
function serverHandler(app, server) {
  app.proxy = true // 用于nginx反代时获取真实客户端ip
  wsRdp(server) // RDP
  wsTerminal(server) // 终端
  wsSftpV2(server) // sftp-v2
  wsDocker(server) // docker
  wsOnekey(server) // 一键指令
  wsServerStatus(server) // 服务器状态监控
  wsFileTransfer(server) // 文件传输
  app.context.throwError = throwError // 常用方法挂载全局ctx上
  app.use(compose(middlewares))
  // 捕获error.js模块抛出的服务错误
  app.on('error', (err, ctx) => {
    ctx.status = 500
    ctx.body = {
      status: ctx.status,
      message: `Program Error：${ err.message }`
    }
  })
}

module.exports = {
  httpServer
}