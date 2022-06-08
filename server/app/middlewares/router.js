const router = require('../router')

const useRoutes = router.routes()
const useAllowedMethods = router.allowedMethods()

module.exports = {
  useRoutes,
  useAllowedMethods
}
