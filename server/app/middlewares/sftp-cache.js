const koaStatic = require('koa-static')
const path = require('path')
const { sftpCacheDir } = require('../config')

const useSftpCacheStatic = async (ctx, next) => {
  // 只处理 /sftp-cache 路径
  if (ctx.path.startsWith('/sftp-cache')) {
    const relativePath = ctx.path.replace('/sftp-cache', '')
    ctx.path = relativePath

    ctx.set('Cache-Control', 'no-cache, no-store, must-revalidate')
    ctx.set('Pragma', 'no-cache')
    ctx.set('Expires', '0')

    const staticMiddleware = koaStatic(sftpCacheDir, {
      maxage: 0,
      gzip: true,
      setHeaders: (res, filePath) => {
        // 强制下载而不是在浏览器中打开
        const filename = path.basename(filePath)

        res.setHeader('Content-Disposition', `attachment; filename="${ encodeURIComponent(filename) }"`)
      }
    })

    await staticMiddleware(ctx, next)
  } else {
    await next()
  }
}

module.exports = useSftpCacheStatic