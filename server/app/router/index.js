const { apiPrefix } = require('../config')
const koaRouter = require('koa-router')
const router = new koaRouter({ prefix: apiPrefix })

const routeList = require('./routes')

// 统一注册路由
routeList.forEach(item => {
  const { method, path, controller } = item
  router[method](path, controller)
})

module.exports = router
