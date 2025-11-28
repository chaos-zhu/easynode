const { apiPrefix } = require('../config')
const { verifyAuthSync, enumLoginCode } = require('../utils/verify-auth')

let whitePath = [
  '/login',
  '/get-pub-pem'
].map(item => (apiPrefix + item))
logger.warn('路由白名单：', whitePath)

const useAuth = async ({ request, res }, next) => {
  const { path, headers: { token, uid } } = request
  if (whitePath.includes(path)) {
    logger.info('白名单路由: ', path)
    return next()
  }
  logger.info('验证权限路由: ', path)
  if (!token) return res.fail({ msg: '未登录(token)', status: 401 })
  if (!uid) return res.fail({ msg: '未登录(uid)', status: 401 })
  // 验证token
  const { code } = await verifyAuthSync(token, uid)
  let failMsg = ''
  switch (code) {
    case enumLoginCode.SUCCESS:
      return await next()
    case enumLoginCode.EXPIRES:
      failMsg = 'TOKEN已过期, 请重新登录'
      break
    case enumLoginCode.ERROR_TOKEN:
      failMsg = 'TOKEN校验失败, 请重新登录'
      break
    case enumLoginCode.REVOKED_TOKEN:
      failMsg = 'TOKEN已被注销, 请重新登录'
      break
    case enumLoginCode.ERROR_UID:
      logger.error('用户id校验失败(可能存在外部攻击): ', path)
      failMsg = 'UID错误!!!'
      break
  }
  logger.warn('验证失败: ', code, failMsg)
  return res.fail({ msg: failMsg || '身份验证失败(未知错误!)', status: 403 })
}

module.exports = useAuth
