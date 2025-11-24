const http = require('http')
const GuacamoleLite = require('guacamole-lite')

const RDP_PORT = process.env.RDP_PORT || 8083 // 使用独立端口
const GUACD_HOST = process.env.GUACD_HOST || 'guacd'
const GUACD_PORT = Number(process.env.GUACD_PORT) || 4822

// 创建独立的HTTP服务器用于RDP
const rdpServer = http.createServer()

const websocketOptions = {
  server: rdpServer,
  path: '/guac'
}

const guacdOptions = {
  host: GUACD_HOST,
  port: GUACD_PORT
}

const clientOptions = {
  crypt: {
    cypher: 'AES-256-CBC',
    key: global.rpdToken || Array.from({ length:32 },()=>Math.random().toString(36)[2]).join('')
  }
}

const startRdpServer = () => {
  try {
    const guacamole = new GuacamoleLite(websocketOptions, guacdOptions, clientOptions)

    guacamole.on('connection', () => {
      logger.info('✔ RDP guacamole连接成功')
    })

    guacamole.on('error', (err) => {
      logger.error('❌ RDP guacamole连接错误', err)
    })

    rdpServer.listen(RDP_PORT, () => {
      logger.info(`RDP服务运行在端口: ${ RDP_PORT }`)
    })
  } catch (error) {
    logger.error('❌ RDP 初始化失败:', error.message)
  }
}

module.exports = { startRdpServer }
