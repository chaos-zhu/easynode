const log4js = require('log4js')
const { outDir, recordLog } = require('../config').logConfig

log4js.configure({
  appenders: {
    console: {
      type: 'stdout',
      layout: {
        type: 'pattern',
        pattern: '%[%d{yyyy-MM-dd hh:mm:ss.SSS} [%p] -%] %m'
      }
    },
    cheese: {
      type: 'file',
      maxLogSize: 10 * 1024 * 1024, // unit: bytes     1KB = 1024bytes
      filename: `${ outDir }/receive.log`,
      backups: 10,
      compress: true,
      keepFileExt: true
    }
  },
  categories: {
    default: {
      appenders: ['console', 'cheese'],
      level: 'debug'
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
    await next() // 等待路由处理完成，再开始记录日志
    // 是否记录日志
    if (recordLog) {
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

// 可以先测试一下日志是否正常工作
logger.info('日志系统启动')