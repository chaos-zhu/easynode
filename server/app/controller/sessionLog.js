const { KeyDB, SessionDB } = require('../utils/db-class')
const keyDB = new KeyDB().getInstance()
const sessionDB = new SessionDB().getInstance()

async function getLog({ res }) {
  let sessionList = await sessionDB.findAsync({})
  let { ipWhiteList } = await keyDB.findOneAsync({})
  sessionList = sessionList.map(item => {
    // eslint-disable-next-line no-unused-vars
    const { session, ...otherInfo } = item
    return { ...otherInfo, id: item._id }
  })
  sessionList?.sort((a, b) => Number(b.create) - Number(a.create))
  res.success({ data: { list: sessionList, ipWhiteList } })
}

const saveIpWhiteList = async ({ res, request }) => {
  const { body: { ipWhiteList } } = request
  if (!Array.isArray(ipWhiteList)) return res.fail({ msg: 'ip list输入非法' })
  let { _id } = await keyDB.findOneAsync({})
  await keyDB.updateAsync({ _id }, { $set: { ipWhiteList } })
  global.ALLOWED_IPS = ipWhiteList
  res.success({ msg: 'success' })
}

const removeSomeLoginRecords = async ({ res }) => {
  const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000
  const result = await sessionDB.removeAsync({ create: { $lt: sevenDaysAgo } }, { multi: true })
  if (result === 0) return res.success({ msg: '没有符合条件的登录日志' })
  res.success({ msg: `已成功移除 ${ result } 条登录日志` })
}

const revokeLoginSid = async (ctx) => {
  const { res, request, cookies } = ctx
  let { params: { id } } = request
  const session = cookies.get('session')
  const { _id: curId, deviceId: curDeviceId } = await sessionDB.findOneAsync({ session })
  let result = await sessionDB.updateAsync({
    $or: [
      { _id: id },
      { deviceId: id }
    ]
  }, { $set: { revoked: true } })
  if (id === curId || id === curDeviceId) {
    logger.warn('注销当前登录凭证，清除cookie')
    ctx.cookies.set('session', '', { expires: new Date(0) })
  }
  if (!result || !result.numAffected) return res.fail({ msg: '注销凭证失败' })
  res.success({ msg: '注销凭证成功' })
}

module.exports = {
  getLog,
  saveIpWhiteList,
  removeSomeLoginRecords,
  revokeLoginSid
}
