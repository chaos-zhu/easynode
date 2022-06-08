const koaBody = require('koa-body')
const { uploadDir } = require('../config')

module.exports = koaBody({
  multipart: true,
  formidable: {
    uploadDir,
    keepExtensions: true,
    multipart: true,
    maxFieldsSize: 2 * 1024 * 1024
  }
})