const koaStatic = require('koa-static')
const { staticDir } = require('../config')

const useStatic = koaStatic(staticDir)

module.exports = useStatic
