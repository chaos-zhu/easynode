// 白名单IP
import fs from 'node:fs'
import path, { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { isAllowedIp, getClientIP } from '../utils/tools.js'

const currentDir = dirname(fileURLToPath(import.meta.url))
const htmlPath = path.join(currentDir, '../template/ipForbidden.html')
const ipForbiddenHtml = fs.readFileSync(htmlPath, 'utf8')

const ipFilter = async (ctx, next) => {
  const requestIP = getClientIP(ctx.socket.remoteAddress, ctx.get('x-forwarded-for'))
  if (isAllowedIp(requestIP)) return await next()
  ctx.status = 403
  ctx.body = ipForbiddenHtml
}

export default ipFilter
