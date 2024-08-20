// 白名单IP
const fs = require('fs')
const path = require('path')
const { isAllowedIp } = require('../utils/tools')

const htmlPath = path.join(__dirname, '../template/ipForbidden.html')
const ipForbiddenHtml = fs.readFileSync(htmlPath, 'utf8')

const ipFilter = async (ctx, next) => {
  // console.log('requestIP:', ctx.request.ip)
  if (isAllowedIp(ctx.request.ip)) return await next()
  ctx.status = 403
  ctx.body = ipForbiddenHtml
}

module.exports = ipFilter
