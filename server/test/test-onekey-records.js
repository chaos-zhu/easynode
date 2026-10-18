import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

const originalCwd = process.cwd()
const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'easynode-onekey-records-'))
await fs.mkdir(path.join(tempRoot, 'app', 'db'), { recursive: true })
process.chdir(tempRoot)

try {
  const { OnekeyDB } = await import('../app/utils/db-class.js')
  const { sortOnekeyRecords } = await import('../app/services/onekey-execution.js')
  const {
    ONEKEY_OUTPUT_CHUNK_SIZE,
    getOnekeyOutput,
    invalidateOnekeyRecordOrder,
    listOnekeyRecords
  } = await import('../app/services/onekey-records.js')
  const { getOnekeyRecord, getOnekeyRecordOutput, removeOnekeyRecord } = await import('../app/controller/onekey.js')
  const records = new OnekeyDB().getInstance()
  const fixtures = []
  for (let batch = 0; batch < 400; batch++) {
    const timestamp = 100000 + batch * 10
    for (let order = 0; order < 2; order++) {
      fixtures.push({
        _id: `batch-${ batch }-${ order }`, batchId: `batch-${ batch }`, batchStartDate: timestamp,
        order, hostId: `host-${ order }`, name: `Host ${ order }`, host: '127.0.0.1', port: 22,
        command: 'echo fixture', startDate: timestamp + order, status: '执行成功', result: 'x'.repeat(2048)
      })
    }
    fixtures.push({ _id: `legacy-${ batch }`, startDate: timestamp + 5, result: 'legacy output' })
  }
  const largeOutput = 'x'.repeat(ONEKEY_OUTPUT_CHUNK_SIZE * 2) + '完成😀'
  fixtures[0].result = largeOutput
  await records.insertAsync(fixtures)
  const expectedOrder = sortOnekeyRecords(fixtures).map(row => row._id)

  // 列表及其排序索引都只能读取必要字段，不得复制或返回历史输出。
  const originalFind = records.findAsync.bind(records)
  let orderingReads = 0
  records.findAsync = (query, projection) => {
    assert.equal(projection.result, undefined)
    assert.equal(projection._id, 1)
    if (!projection.name) orderingReads++
    return originalFind(query, projection)
  }
  const first = await listOnekeyRecords()
  assert.equal(first.total, 1200)
  assert.equal(first.items.length, 20)
  assert.equal(first.page, 1)
  assert.equal(first.pageSize, 20)
  assert.deepEqual(first.items.map(row => row.id), expectedOrder.slice(0, 20))
  assert.equal(first.items.some(row => 'result' in row), false)
  assert.ok(JSON.stringify(first).length < 10000)
  const second = await listOnekeyRecords({ page: 2, pageSize: 20 })
  assert.deepEqual(second.items.map(row => row.id), expectedOrder.slice(20, 40))
  const capped = await listOnekeyRecords({ pageSize: 10000 })
  assert.equal(capped.items.length, 100)
  assert.equal(capped.pageSize, 100)
  const last = await listOnekeyRecords({ page: Number.MAX_SAFE_INTEGER, pageSize: 50 })
  assert.equal(last.page, 24)
  assert.deepEqual(last.items.map(row => row.id), expectedOrder.slice(-50))
  const invalid = await listOnekeyRecords({ page: '-1', pageSize: 'Infinity' })
  assert.equal(invalid.page, 1)
  assert.equal(invalid.pageSize, 20)
  assert.equal(orderingReads, 1, 'Repeated pages must reuse the lightweight ordering index')

  let offset = 0
  let combined = ''
  do {
    const chunk = await getOnekeyOutput(fixtures[0]._id, { offset, limit: 1000000 })
    assert.ok(chunk.result.length <= ONEKEY_OUTPUT_CHUNK_SIZE)
    assert.equal(chunk.offset, offset)
    assert.equal(chunk.total, largeOutput.length)
    combined += chunk.result
    offset = chunk.nextOffset
    if (!chunk.hasMore) break
  } while (true)
  assert.equal(combined, largeOutput)
  const beyondEnd = await getOnekeyOutput(fixtures[0]._id, { offset: 1000000 })
  assert.equal(beyondEnd.result, '')
  assert.equal(beyondEnd.hasMore, false)
  const invalidChunk = await getOnekeyOutput(fixtures[0]._id, { offset: -1, limit: 0 })
  assert.equal(invalidChunk.offset, 0)
  assert.equal(invalidChunk.result.length, ONEKEY_OUTPUT_CHUNK_SIZE)
  assert.equal(await getOnekeyOutput('missing'), null)

  let response
  const res = { success(value) { response = value }, fail(value) { response = value } }
  await getOnekeyRecord({ res, request: { query: { page: 3, pageSize: 50 } } })
  assert.equal(response.data.page, 3)
  assert.equal(response.data.items.length, 50)
  await getOnekeyRecordOutput({ res, request: { params: { id: 'missing' }, query: {} } })
  assert.equal(response.status, 404)
  await getOnekeyRecordOutput({ res, request: { params: { id: fixtures[0]._id }, query: { offset: 0, limit: 10 } } })
  assert.equal(response.data.result.length, 10)

  await removeOnekeyRecord({ res, request: { body: { ids: expectedOrder.slice(0, 2) } } })
  const afterDelete = await listOnekeyRecords()
  assert.equal(afterDelete.total, 1198)
  assert.deepEqual(afterDelete.items.map(row => row.id), expectedOrder.slice(2, 22))
  assert.equal(orderingReads, 2)
  await records.insertAsync({ _id: 'newest', startDate: 999999, result: 'new output' })
  invalidateOnekeyRecordOrder()
  assert.equal((await listOnekeyRecords()).items[0].id, 'newest')
  await removeOnekeyRecord({ res, request: { body: { ids: 'ALL' } } })
  assert.deepEqual(await listOnekeyRecords({ page: 100 }), { items: [], total: 0, page: 1, pageSize: 20 })
  console.log('onekey record pagination tests passed: 1200 records, mixed ordering, bounded summaries/output, cache invalidation and deletion')
} finally {
  process.chdir(originalCwd)
  await fs.rm(tempRoot, { recursive: true, force: true })
}
