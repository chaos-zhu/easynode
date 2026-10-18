import { OnekeyDB } from '../utils/db-class.js'
import { getOnekeyOutput, invalidateOnekeyRecordOrder, listOnekeyRecords } from '../services/onekey-records.js'
const onekeyDB = new OnekeyDB().getInstance()

async function getOnekeyRecord({ res, request }) {
  res.success({ data: await listOnekeyRecords(request.query) })
}

async function getOnekeyRecordOutput({ res, request }) {
  const data = await getOnekeyOutput(request.params.id, request.query)
  if (!data) return res.fail({ status: 404, msg: '执行记录不存在' })
  res.success({ data })
}

const removeOnekeyRecord = async ({ res, request }) => {
  let { body: { ids } } = request
  if (ids === 'ALL') {
    await onekeyDB.removeAsync({}, { multi: true })
    res.success({ data: '移除全部成功' })
  } else {
    await onekeyDB.removeAsync({ _id: { $in: ids } }, { multi: true })
    res.success({ data: '移除成功' })
  }
  invalidateOnekeyRecordOrder()
}

export {
  getOnekeyRecord,
  getOnekeyRecordOutput,
  removeOnekeyRecord
}
