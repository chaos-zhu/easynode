const { apiPrefix, clientIPHeader } = require('../config')
const { verifyAuthSync } = require('../utils/verify-auth')

let whitePath = [
  '/login',
  '/get-pub-pem'
].map(item => (apiPrefix + item))
consola.info('路由白名单：', whitePath)

const useAuth = async ({ request, res }, next) => {
  const { path, headers } = request
  const token = headers.token
  // 前者为自定义真实IP请求头或默认兼容nginx反代, 后者为中间件获取的IP地址
  const requestIP = headers[clientIPHeader] || request.ip
  consola.info('verify path: ', path)
  if (whitePath.includes(path)) return next()
  if (!token) return res.fail({ msg: '未登录', status: 403 })
  // 验证token
  const { code, msg } = await verifyAuthSync(token, requestIP)
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
