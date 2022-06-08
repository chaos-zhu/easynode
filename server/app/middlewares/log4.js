const log4js = require('log4js')
const { outDir, flag } = require('../config').logConfig

log4js.configure({
  appenders: {
    out: {
      type: 'stdout',
      layout: {
        type: 'colored'
      }
    },
    cheese: {
      type: 'file',
      maxLogSize: 512*1024, // unit: bytes     1KB = 1024bytes
      filename: `${ outDir }/receive.log`
    }
  },
  categories: {
    default: {
      appenders: [ 'out', 'cheese' ],
      level: 'info'
    }
  }
})

const logger = log4js.getLogger()

const useLog = () => {
  return async (ctx, next) => {
    const { method, path, origin, query, body, headers, ip } = ctx.request
    const data = {
      method,
      path,
      origin,
      query,
      body,
      ip,
      headers
    }
    await next()
    if (flag) {
      const { status, params } = ctx
      data.status = status
      data.params = params
      data.result = ctx.body || 'no content'
      if (String(status).startsWith(4) || String(status).startsWith(5))
        logger.error(JSON.stringify(data))
      else
        logger.info(JSON.stringify(data))
    }
  }
}

module.exports = useLog()