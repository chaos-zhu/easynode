const { readOneKeyRecord, deleteOneKeyRecord } = require('../utils/storage')

async function getOnekeyRecord({ res }) {
  let data = await readOneKeyRecord()
  data = data.map(item => {
    return { ...item, id: item._id }
  })
  data?.sort((a, b) => Number(b.date) - Number(a.date))
  res.success({ data })
}

const removeOnekeyRecord = async ({ res, request }) => {
  let { body: { ids } } = request
  let onekeyRecord = await readOneKeyRecord()
  if (ids === 'ALL') {
    ids = onekeyRecord.map(item => item._id)
    await deleteOneKeyRecord(ids)
    res.success({ data: '移除全部成功' })
  } else {
    if (!onekeyRecord.some(item => ids.includes(item._id))) return res.fail({ msg: '批量指令记录ID不存在' })
    await deleteOneKeyRecord(ids)
    res.success({ data: '移除成功' })
  }
}

module.exports = {
  getOnekeyRecord,
  removeOnekeyRecord
}
