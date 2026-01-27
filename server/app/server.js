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
const { throwError, isAllowedIp } = require('./utils/tools')
const { SessionDB } = require('./utils/db-class')
const { parseCookies } = require('./utils/verify-auth')
const sessionDB = new SessionDB().getInstance()

const httpServer = () => {
  const app = new Koa()
  const server = http.createServer(app.callback())

  // 添加RDP WebSocket代理
  const createRdpProxyMiddleware = require('./middlewares/rdp-proxy')
  const rdpProxy = createRdpProxyMiddleware()

  // 只处理WebSocket升级请求的代理（RDP只需要WebSocket）
  // 安全说明：
  // 1. RDP token 是通过 /get-rdp-token API 获取的，该 API 受 auth 中间件保护，只有登录用户才能获取
  // 2. RDP token 由 guacamole-lite 使用 AES-256-CBC 加密，包含连接信息，guacamole-lite 会验证 token 有效性
  // 3. 这里只需要验证 IP 白名单，防止 token 泄露后被非授权 IP 使用【0127增强: 验证session】
  server.on('upgrade', async (request, socket, head) => {
    if (request.url.startsWith('/rdp-proxy')) {
      try {
      // 验证 IP 白名单
        const requestIP = request.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
                          request.socket.remoteAddress
        if (!isAllowedIp(requestIP)) {
          logger.warn(`RDP 连接被拒绝: IP ${ requestIP } 不在白名单中`)
          socket.write('HTTP/1.1 403 Forbidden\r\n\r\n')
          socket.destroy()
          return
        }
        // 验证 session
        const cookies = request.headers.cookie
        const { session } = parseCookies(cookies)
        const sessionRecord = await sessionDB.findOneAsync({ session })
        // 是否无效/注销/过期的token
        if (
          !session ||
          !sessionRecord ||
          sessionRecord.revoked !== false ||
          sessionRecord.expireAt < Date.now()
        ) {
          logger.warn(`RDP 连接被拒绝: IP ${ requestIP } 不在白名单中`)
          socket.write('HTTP/1.1 403 Forbidden\r\n\r\n')
          socket.destroy()
          return
        }

        // 验证通过，转发请求到 guacamole-lite
        // guacamole-lite 会验证 URL 中的加密 token
        console.log('RDP 代理转发请求初步验证成功，开始转发...')
        rdpProxy.upgrade(request, socket, head)
      } catch (error) {
        logger.error('RDP 代理异常:', error.message)
        socket.write('HTTP/1.1 500 Internal Server Error\r\n\r\n')
        socket.destroy()
      }
    }
    // 对于非 /rdp-proxy 路径, Socket.IO 的内部 upgrade 监听器自动处理
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