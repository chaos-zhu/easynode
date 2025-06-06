// 白名单IP
const fs = require('fs')
const path = require('path')
const { clientIPHeader } = require('../config')
const { isAllowedIp } = require('../utils/tools')

const htmlPath = path.join(__dirname, '../template/ipForbidden.html')
const ipForbiddenHtml = fs.readFileSync(htmlPath, 'utf8')

const ipFilter = async (ctx, next) => {
  // 前者为自定义真实IP请求头或默认兼容nginx反代, 后者为中间件获取的IP地址
  const requestIP = ctx.request.headers[clientIPHeader] || ctx.request.ip

  if (isAllowedIp(requestIP)) return await next()
  ctx.status = 403
  ctx.body = ipForbiddenHtml
}

module.exports = ipFilter
