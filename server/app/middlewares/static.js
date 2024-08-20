const koaStatic = require('koa-static')
const { staticDir } = require('../config')

const useStatic = koaStatic(staticDir, {
  maxage: 1000 * 60 * 60 * 24 * 30,
  gzip: true,
  setHeaders: (res, path) => {
    if (path && path.endsWith('.html')) {
      res.setHeader('Cache-Control', 'max-age=0')
    }
  }
})

module.exports = useStatic
