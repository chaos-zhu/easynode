const { KeyDB, LogDB } = require('../utils/db-class')
const keyDB = new KeyDB().getInstance()
const logDB = new LogDB().getInstance()

async function getLog({ res }) {
  let list = await logDB.findAsync({})
  let { ipWhiteList } = await keyDB.findOneAsync({})
  list = list.map(item => {
    return { ...item, id: item._id }
  })
  list?.sort((a, b) => Number(b.date) - Number(a.date))
  res.success({ data: { list, ipWhiteList } })
}

const saveIpWhiteList = async ({ res, request }) => {
  const { body: { ipWhiteList } } = request
  if (!Array.isArray(ipWhiteList)) return res.fail({ msg: 'ip list输入非法' })
  let { _id } = await keyDB.findOneAsync({})
  await keyDB.updateAsync({ _id }, { $set: { ipWhiteList } })
  global.ALLOWED_IPS = ipWhiteList
  res.success({ msg: 'success' })
}

module.exports = {
  getLog,
  saveIpWhiteList
}
