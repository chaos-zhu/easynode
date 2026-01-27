const log4js = require('log4js')
const { outDir } = require('./config').logConfig
log4js.configure({
  appenders: {
    console: {
      type: 'stdout',
      layout: {
        type: 'pattern',
        pattern: '%[%d{yyyy-MM-dd hh:mm:ss.SSS} [%p] -%] %m'
      }
    },
    file: {
      type: 'file',
      maxLogSize: 10 * 1024 * 10, // 10MB
      filename: `${ outDir }/debug.log`,
      backups: 10,
      compress: true,
      keepFileExt: true
    }
  },
  categories: {
    default: {
      appenders: process.env.EXEC_ENV === 'local' ? ['file'] : ['console', 'file'],
      level: 'debug'
    }
  }
})
const logger = log4js.getLogger()
global.logger = logger