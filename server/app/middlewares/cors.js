import cors from '@koa/cors'

// 跨域处理
const useCors = cors({
  origin: ({ req }) => {
    return req.headers.origin
  },
  credentials: true,
  allowMethods: [ 'GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'PATCH' ]
})

export default useCors
