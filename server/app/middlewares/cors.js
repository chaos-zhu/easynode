const cors = require('@koa/cors')

// 跨域处理
const useCors = cors({
  origin: ({ req }) => {
    return req.headers.origin
  },
  credentials: true,
  allowMethods: [ 'GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'PATCH' ]
})

module.exports = useCors
