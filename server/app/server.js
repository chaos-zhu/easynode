import Koa from 'koa'
import compose from 'koa-compose' // 组合中间件,简化写法
import http from 'node:http'
import https from 'node:https'
import fs from 'node:fs'
import { httpPort, httpsPort, enableHttps, sslCertPath, sslKeyPath } from './config/index.js'
import middlewares from './middlewares/index.js'
import { startRdpServer } from './rdp-server.js'
import wsTerminal from './socket/terminal.js'
import wsSftpV2 from './socket/sftp-v2.js'
import wsDocker from './socket/docker.js'
import wsOnekey from './socket/onekey.js'
import wsServerStatus from './socket/server-status.js'
import wsFileTransfer from './socket/file-transfer.js'
import wsAiAgent from './socket/ai-agent.js'
import { throwError, isAllowedIp, getClientIP } from './utils/tools.js'
import { SessionDB } from './utils/db-class.js'
import { parseCookies } from './utils/verify-auth.js'
import { generateSelfSignedCert } from './utils/ssl-cert.js'
import createRdpProxyMiddleware from './middlewares/rdp-proxy.js'

const sessionDB = new SessionDB().getInstance()

const createServer = () => {
  const app = new Koa()

  // 创建HTTP服务器
  const httpServer = http.createServer(app.callback())
  httpServer.setMaxListeners(20)

  // 创建HTTPS服务器(如果启用)
  let httpsServer = null
  if (enableHttps === 1) {
    // 模式1: 自签证书
    try {
      const { cert, key } = generateSelfSignedCert()
      const httpsOptions = { cert, key }
      httpsServer = https.createServer(httpsOptions, app.callback())
      logger.info('🔒 HTTPS服务器已配置(自签名证书)')
    } catch (error) {
      logger.error('自签名证书生成失败:', error.message)
      process.exit(1)
    }
  } else if (enableHttps === 2) {
    // 模式2: 传入证书路径
    try {
      // 验证证书文件路径是否配置
      if (!sslCertPath || !sslKeyPath) {
        logger.error('ENABLE_HTTPS=2 时,必须配置 SSL_CERT_PATH 和 SSL_KEY_PATH 环境变量')
        process.exit(1)
      }

      // 验证证书文件是否存在
      if (!fs.existsSync(sslCertPath)) {
        logger.error(`SSL证书文件不存在: ${ sslCertPath }`)
        process.exit(1)
      }
      if (!fs.existsSync(sslKeyPath)) {
        logger.error(`SSL私钥文件不存在: ${ sslKeyPath }`)
        process.exit(1)
      }

      // 读取SSL证书
      const httpsOptions = {
        cert: fs.readFileSync(sslCertPath),
        key: fs.readFileSync(sslKeyPath)
      }

      httpsServer = https.createServer(httpsOptions, app.callback())
      logger.info('🔒 HTTPS服务器已配置(自定义证书)')
    } catch (error) {
      logger.error('HTTPS服务器配置失败:', error.message)
      process.exit(1)
    }
  } else {
    // 模式0: 关闭HTTPS
    logger.info('HTTPS已关闭')
  }

  // 添加RDP WebSocket代理
  const rdpProxy = createRdpProxyMiddleware()

  // WebSocket升级处理函数
  const handleRdpWsUpgrade = async (request, socket, head) => {
  // 只处理WebSocket升级请求的代理（RDP只需要WebSocket）
  // 安全说明：
  // 1. RDP token 是通过 /get-rdp-token API 获取的，该 API 受 auth 中间件保护，只有登录用户才能获取
  // 2. RDP token 由 guacamole-lite 使用 AES-256-CBC 加密，包含连接信息，guacamole-lite 会验证 token 有效性
  // 3. 这里只需要验证 IP 白名单，防止 token 泄露后被非授权 IP 使用【0127增强: 验证session】
    if (request.url.startsWith('/rdp-proxy')) {
      try {
      // 验证 IP 白名单
        const requestIP = getClientIP(request.socket.remoteAddress, request.headers['x-forwarded-for'])
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
  }

  httpServer.on('upgrade', handleRdpWsUpgrade)
  if (httpsServer) {
    httpsServer.on('upgrade', handleRdpWsUpgrade)
  }

  serverHandler(app, httpServer, httpsServer)

  // ws一直报跨域的错误：参照官方文档使用createServer API创建服务
  httpServer.listen(httpPort, () => {
    logger.info(`Server(http) is running on: http://localhost:${ httpPort }`)
  })

  // 启动HTTPS服务器
  if (httpsServer) {
    httpsServer.listen(httpsPort, () => {
      logger.info(`Server(https) is running on: https://localhost:${ httpsPort }`)
    })
  }

  // 启动独立的RDP服务
  startRdpServer()
}

function registServer(targetServer) {
  // 为HTTP服务器添加WebSocket支持
  wsTerminal(targetServer) // 终端
  wsSftpV2(targetServer) // sftp-v2
  wsDocker(targetServer) // docker
  wsOnekey(targetServer) // 一键指令
  wsServerStatus(targetServer) // 服务器状态监控
  wsFileTransfer(targetServer) // 文件传输
  wsAiAgent(targetServer) // AI agent
}
// 服务
function serverHandler(app, server, httpsServer) {
  app.proxy = true // 用于nginx反代时获取真实客户端ip

  registServer(server)
  if (httpsServer) registServer(httpsServer)

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

export {
  createServer
}
