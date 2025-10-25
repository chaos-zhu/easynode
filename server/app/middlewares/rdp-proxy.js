const { createProxyMiddleware } = require('http-proxy-middleware')

/**
 * RDP代理中间件
 * 将/rdp-proxy/guac路径的请求代理到RDP独立端口
 */
const createRdpProxyMiddleware = () => {
  const RDP_PORT = process.env.RDP_PORT || 8083
  const RDP_HOST = process.env.RDP_HOST || '127.0.0.1' // 使用127.0.0.1更可靠
  const target = `http://${ RDP_HOST }:${ RDP_PORT }`

  console.log('Creating RDP proxy middleware with target:', target)

  // 创建WebSocket代理
  const wsProxy = createProxyMiddleware({
    target: target,
    ws: true,
    changeOrigin: true,
    pathRewrite: {
      '^/rdp-proxy': ''
    },
    logLevel: 'debug'
  })

  return wsProxy
}

module.exports = createRdpProxyMiddleware