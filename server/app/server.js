const Koa = require('koa')
const compose = require('koa-compose') // 组合中间件，简化写法
const http = require('http')
const { httpPort } = require('./config')
const middlewares = require('./middlewares')
const { startRdpServer } = require('./rdp-server')
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

  // 添加RDP WebSocket代理
  const createRdpProxyMiddleware = require('./middlewares/rdp-proxy')
  const rdpProxy = createRdpProxyMiddleware()

  // 只处理WebSocket升级请求的代理（RDP只需要WebSocket）
  server.on('upgrade', (request, socket, head) => {
    if (request.url.startsWith('/rdp-proxy')) {
      rdpProxy.upgrade(request, socket, head)
    }
  })

  serverHandler(app, server)

  // ws一直报跨域的错误：参照官方文档使用createServer API创建服务
  server.listen(httpPort, () => {
    logger.info(`Server(http) is running on: http://localhost:${ httpPort }`)
  })

  // 启动独立的RDP服务
  startRdpServer()
}

// 服务
function serverHandler(app, server) {
  app.proxy = true // 用于nginx反代时获取真实客户端ip
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