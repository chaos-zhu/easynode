const log4js = require('log4js')
const { outDir, flag } = require('../config').logConfig

log4js.configure({
  appenders: {
    // 控制台输出
    out: {
      type: 'stdout',
      layout: {
        type: 'colored'
      }
    },
    // 保存日志文件
    cheese: {
      type: 'file',
      maxLogSize: 512*1024, // unit: bytes     1KB = 1024bytes
      filename: `${ outDir }/receive.log`
    }
  },
  categories: {
    default: {
      appenders: [ 'out', 'cheese' ], // 配置
      level: 'info' // 只输出info以上级别的日志
    }
  }
  // pm2: true
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