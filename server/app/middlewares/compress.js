// 响应压缩模块，自适应头部压缩方式
const compress = require('koa-compress')

const options = { threshold: 2048 }

module.exports = compress(options)
