const cors = require('@koa/cors')
const { domain } = require('../config')

// 跨域处理
const useCors = cors({
  origin: ({ req }) => {
    return domain || req.headers.origin
  },
  credentials: true,
  allowMethods: [ 'GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'PATCH' ]
})

module.exports = useCors
