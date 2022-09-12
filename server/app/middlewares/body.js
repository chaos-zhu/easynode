const koaBody = require('koa-body')
const { uploadDir } = require('../config')

module.exports = koaBody({
  multipart: true, // 支持 multipart-formdate 的表单
  formidable: {
    uploadDir, // 上传目录
    keepExtensions: true, // 保持文件的后缀
    multipart: true, // 多文件上传
    maxFieldsSize: 2 * 1024 * 1024 // 文件上传大小 单位：B
  }
})