const cors = require('@koa/cors')
// const { domain } = require('../config')

const useCors = cors({
  origin: ({ req }) => {
    // console.log(req.headers.origin)
    // return domain || req.headers.origin
    return req.headers.origin
  },
  credentials: true,
  allowMethods: [ 'GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'PATCH' ]
})

module.exports = useCors
