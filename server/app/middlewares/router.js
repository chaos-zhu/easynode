const router = require('../router')

// 路由中间件
const useRoutes = router.routes()
// 优化错误提示中间件
// 原先如果请求方法错误响应404
// 使用该中间件后请求方法错误会提示405 Method Not Allowed【get list ✔200 post /list ❌405】
const useAllowedMethods = router.allowedMethods()

module.exports = {
  useRoutes,
  useAllowedMethods
}
