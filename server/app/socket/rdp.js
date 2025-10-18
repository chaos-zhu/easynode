const GuacamoleLite = require('guacamole-lite')

const GUACD_HOST = process.env.GUACD_HOST || 'guacd'
const GUACD_PORT = Number(process.env.GUACD_PORT) || 4822

const getOptions = (server) => {
  const websocketOptions = {
    server,
    path: '/guac'
  }

  const guacdOptions = {
    host: GUACD_HOST,
    port: GUACD_PORT
  }

  const clientOptions = {
    crypt: {
      cypher: 'AES-256-CBC',
      key: global.rpdToken
    }
  }
  return { websocketOptions, guacdOptions, clientOptions }
}
module.exports = (httpServer) => {
  const { websocketOptions, guacdOptions, clientOptions } = getOptions(httpServer)
  let guacamole = new GuacamoleLite(websocketOptions, guacdOptions, clientOptions)
  try {
    guacamole.on('connection', () => {
      consola.success('✔ RDP guacamole连接成功')
    })
    guacamole.on('error', (err) => {
      consola.error('❌ RDP guacamole连接错误', err)
    })
  } catch (error) {
    guacamole.close()
    guacamole = null
    consola.error('❌ RDP 初始化失败:', error.message)
  }
}