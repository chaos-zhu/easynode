import { OnekeyDB } from '../utils/db-class.js'
import { sortOnekeyRecords } from './onekey-execution.js'

const records = new OnekeyDB().getInstance()
export const ONEKEY_OUTPUT_CHUNK_SIZE = 64 * 1024
let recordOrder = null

export function invalidateOnekeyRecordOrder() {
  recordOrder = null
}

function integer(value, fallback, min = 1, max = Number.MAX_SAFE_INTEGER) {
  const number = Number(value)
  return Number.isSafeInteger(number) && number >= min ? Math.min(number, max) : fallback
}

function orderedIds() {
  if (!recordOrder) {
    // 只缓存排序所需的 ID；旧记录按 startDate、新记录按批次及主机顺序排列。
    // NeDB 的 sort 不支持字段回退，不能直接用 batchStartDate 对新旧记录混排。
    const pendingOrder = records.findAsync({}, {
      _id: 1, batchId: 1, batchStartDate: 1, startDate: 1, order: 1
    }).then(items => sortOnekeyRecords(items).map(item => item._id))
    recordOrder = pendingOrder
    pendingOrder.catch(() => {
      if (recordOrder === pendingOrder) recordOrder = null
    })
  }
  return recordOrder
}

export async function listOnekeyRecords(query = {}) {
  const pageSize = integer(query.pageSize, 20, 1, 100)
  const ids = await orderedIds()
  const total = ids.length
  const page = Math.min(integer(query.page, 1), Math.max(1, Math.ceil(total / pageSize)))
  const pageIds = ids.slice((page - 1) * pageSize, page * pageSize)
  const items = pageIds.length ? await records.findAsync({ _id: { $in: pageIds } }, {
    _id: 1, batchId: 1, batchStartDate: 1, order: 1, hostId: 1,
    name: 1, host: 1, port: 1, command: 1, startDate: 1, endDate: 1, status: 1
  }) : []
  const byId = new Map(items.map(item => [item._id, { ...item, id: item._id }]))
  return { items: pageIds.map(id => byId.get(id)).filter(Boolean), total, page, pageSize }
}

export async function getOnekeyOutput(id, query = {}) {
  const record = await records.findOneAsync({ _id: id }, { result: 1 })
  if (!record) return null
  const result = record.result || ''
  const offset = Math.min(integer(query.offset, 0, 0), result.length)
  const limit = integer(query.limit, ONEKEY_OUTPUT_CHUNK_SIZE, 1, ONEKEY_OUTPUT_CHUNK_SIZE)
  const nextOffset = Math.min(offset + limit, result.length)
  return {
    id, result: result.slice(offset, nextOffset), offset, nextOffset,
    total: result.length, hasMore: nextOffset < result.length
  }
}
