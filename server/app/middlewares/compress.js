const compress = require('koa-compress')

const options = { threshold: 2048 }

module.exports = compress(options)
