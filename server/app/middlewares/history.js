const { historyApiFallback } = require('koa2-connect-history-api-fallback')

module.exports = historyApiFallback({ whiteList: ['/api'] })
