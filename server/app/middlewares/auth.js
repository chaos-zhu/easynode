const { apiPrefix } = require('../config')
const { verifyAuthSync, enumLoginCode } = require('../utils/verify-auth')

let whitePath = [
  '/login',
  '/get-pub-pem'
].map(item => (apiPrefix + item))
logger.warn('路由白名单：', whitePath)

const useAuth = async ({ request, res }, next) => {
  const { path, headers: { token, uid } } = request
  logger.info('verify path: ', path)
  if (whitePath.includes(path)) return next()
  if (!token) return res.fail({ msg: '未登录(token)', status: 401 })
  if (!uid) return res.fail({ msg: '未登录(uid)', status: 401 })
  // 验证token
  const { code } = await verifyAuthSync(token, uid)
  switch (code) {
    case enumLoginCode.SUCCESS:
      return await next()
    case enumLoginCode.EXPIRES:
      return res.fail({ msg: 'TOKEN已过期, 请重新登录', status: 403 })
    case enumLoginCode.ERROR_TOKEN:
      return res.fail({ msg: 'TOKEN校验失败, 请重新登录', status: 403 })
    case enumLoginCode.REVOKED_TOKEN:
      return res.fail({ msg: 'TOKEN已被注销, 请重新登录', status: 403 })
    case enumLoginCode.ERROR_UID:
      logger.error('用户id校验失败(可能存在外部攻击): ', path)
      return res.fail({ msg: 'UID错误!!!', status: 403 })
  }
}

module.exports = useAuth
