import log4js from 'log4js'
import { logConfig } from './config/index.js'

const { outDir } = logConfig
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
      appenders: ['console', 'file'],
      level: 'debug'
    }
  }
})
const logger = log4js.getLogger()
global.logger = logger
