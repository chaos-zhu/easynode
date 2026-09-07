import assert from 'node:assert/strict'

/**
 * 测试登录流程中的IP归属地异步查询
 * 验证：
 * 1. 登录立即返回，不等待IP查询
 * 2. Session记录先插入占位符
 * 3. IP信息异步更新
 */

let getNetIPInfoCallCount = 0
let getNetIPInfoResolveTime = 0
const mockGetNetIPInfo = (ip) => {
  getNetIPInfoCallCount++
  return new Promise((resolve) => {
    // 模拟3秒的网络延迟
    setTimeout(() => {
      getNetIPInfoResolveTime = Date.now()
      resolve({ ip, country: '中国', city: '北京' })
    }, 3000)
  })
}

let insertedRecords = []
let updatedRecords = []
const mockSessionDB = {
  async insertAsync(record) {
    insertedRecords.push({ ...record, insertTime: Date.now() })
    return record
  },
  async updateAsync(query, update) {
    updatedRecords.push({ query, update, updateTime: Date.now() })
    return { numAffected: 1 }
  }
}

// 模拟beforeLoginHandler的核心逻辑
const beforeLoginHandlerAsync = async (clientIp, sessionDB, getNetIPInfo) => {
  const session = 'test-session'
  const startTime = Date.now()

  // 先插入session记录，IP信息使用占位符
  await sessionDB.insertAsync({
    session,
    ip: clientIp,
    country: '查询中',
    city: '查询中',
    create: Date.now()
  })

  // 异步查询IP归属地并更新数据库（不阻塞登录响应）
  getNetIPInfo(clientIp).then(clientIPInfo => {
    const { ip, country, city } = clientIPInfo || {}
    // 更新session记录中的IP信息
    sessionDB.updateAsync({ session }, { $set: { ip, country, city } }).catch(error => {
      console.error('更新IP归属地信息失败:', error)
    })
  }).catch(error => {
    console.error('查询IP归属地失败:', error)
    sessionDB.updateAsync({ session }, { $set: { country: '未知', city: '未知' } }).catch(e => {
      console.error('更新IP归属地信息失败:', e)
    })
  })

  const endTime = Date.now()
  return { session, responseTime: endTime - startTime }
}

// 执行测试
const testResult = await beforeLoginHandlerAsync('192.168.1.1', mockSessionDB, mockGetNetIPInfo)

// 验证1: 登录响应时间应该很快（远小于3秒的IP查询时间）
assert.ok(testResult.responseTime < 100, `登录响应时间应该<100ms，实际: ${testResult.responseTime}ms`)
console.log(`✓ 登录响应时间: ${testResult.responseTime}ms（不等待IP查询）`)

// 验证2: Session记录应该已插入，且使用占位符
assert.equal(insertedRecords.length, 1, 'Session记录应该已插入')
assert.equal(insertedRecords[0].country, '查询中', '初始country应为"查询中"')
assert.equal(insertedRecords[0].city, '查询中', '初始city应为"查询中"')
console.log('✓ Session记录已插入，使用占位符')

// 验证3: IP查询应该已触发
assert.equal(getNetIPInfoCallCount, 1, 'IP查询应该被调用1次')
console.log('✓ IP归属地查询已触发（异步执行）')

// 等待IP查询完成
await new Promise(resolve => setTimeout(resolve, 3500))

// 验证4: IP信息应该已更新
assert.equal(updatedRecords.length, 1, 'Session记录应该被更新1次')
assert.equal(updatedRecords[0].update.$set.country, '中国', 'country应该更新为"中国"')
assert.equal(updatedRecords[0].update.$set.city, '北京', 'city应该更新为"北京"')
console.log('✓ IP归属地信息已异步更新到数据库')

// 验证5: 确认更新发生在登录响应之后
const responseCompleteTime = insertedRecords[0].insertTime + testResult.responseTime
const ipUpdateTime = updatedRecords[0].updateTime
assert.ok(ipUpdateTime > responseCompleteTime, 'IP更新应该在登录响应完成之后')
console.log(`✓ 时间线正确: 登录响应(${testResult.responseTime}ms) → IP查询(3000ms+) → 数据库更新`)

console.log('\n✅ 登录IP异步查询测试全部通过')
