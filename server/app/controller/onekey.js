const { OnekeyDB } = require('../utils/db-class')
const onekeyDB = new OnekeyDB().getInstance()

async function getOnekeyRecord({ res }) {
  let data = await onekeyDB.findAsync({})
  data = data.map(item => {
    return { ...item, id: item._id }
  })
  data?.sort((a, b) => Number(b.date) - Number(a.date))
  res.success({ data })
}

const removeOnekeyRecord = async ({ res, request }) => {
  let { body: { ids } } = request
  if (ids === 'ALL') {
    await onekeyDB.removeAsync({}, { multi: true })
    res.success({ data: '移除全部成功' })
  } else {
    await onekeyDB.removeAsync({ _id: { $in: ids } })
    res.success({ data: '移除成功' })
  }
}

module.exports = {
  getOnekeyRecord,
  removeOnekeyRecord
}
