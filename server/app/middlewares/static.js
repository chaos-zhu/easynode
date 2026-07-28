import koaStatic from 'koa-static'
import { staticDir } from '../config/index.js'

const useStatic = koaStatic(staticDir, {
  maxage: 1000 * 60 * 60 * 24 * 30,
  gzip: true,
  setHeaders: (res, path) => {
    if (path && path.endsWith('.html')) {
      res.setHeader('Cache-Control', 'max-age=0')
    }
  }
})

export default useStatic
