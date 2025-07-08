const { apiPrefix } = require('../config')
const { verifyAuthSync } = require('../utils/verify-auth')

let whitePath = [
  '/login',
  '/get-pub-pem'
].map(item => (apiPrefix + item))
consola.info('路由白名单：', whitePath)

const useAuth = async ({ request, res }, next) => {
  const { path, headers: { token } } = request
  // consola.info('verify path: ', path)
  if (whitePath.includes(path)) return next()
  if (!token) return res.fail({ msg: '未登录', status: 403 })
  // 验证token
  const { code, msg } = await verifyAuthSync(token, request.ip)
  switch (code) {
    case 1:
      return await next()
    case -1:
      return res.fail({ msg, status: 401 })
    case -2:
      return res.fail({ msg: '登录态错误, 请重新登录', status: 401, data: msg })
  }
}

module.exports = useAuth
