/**
 * Agent 会话持久化测试
 *
 * 运行：node test/test-ai-session.js
 *
 * 重点验证消息完整性。tool-call 与 tool-result 不配对的历史发给模型
 * 会被绝大多数厂商直接 400，而这种残缺在 turn 被中断时非常容易产生。
 */

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

// DB 路径由 config 在 import 时按 cwd 计算，这里切到临时目录避免污染真实数据
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'easynode-ai-test-'))
fs.mkdirSync(path.join(tmpDir, 'app/db'), { recursive: true })
const originalCwd = process.cwd()
process.chdir(tmpDir)

global.logger = { warn() {}, info() {}, error() {} }

const { repairMessages, truncateHistory } = await import(`${ originalCwd }/app/ai/session-store.js`)
const store = await import(`${ originalCwd }/app/ai/session-store.js`)

let passed = 0
let failed = 0
const failures = []

function expect(label, actual, want) {
  if (JSON.stringify(actual) === JSON.stringify(want)) {
    passed += 1
    return
  }
  failed += 1
  failures.push(`  ${ label }\n    期望: ${ JSON.stringify(want) }\n    实际: ${ JSON.stringify(actual) }`)
}

function assert(label, condition) {
  if (condition) {
    passed += 1
    return
  }
  failed += 1
  failures.push(`  ${ label }\n    断言失败`)
}

const userMsg = (text) => ({ role: 'user', content: text })
const assistantMsg = (text) => ({ role: 'assistant', content: text })
const toolCallMsg = (id, name = 'exec_command') => ({
  role: 'assistant',
  content: [{ type: 'tool-call', toolCallId: id, toolName: name, input: { command: 'ls' } }]
})
const toolResultMsg = (id, name = 'exec_command') => ({
  role: 'tool',
  content: [{ type: 'tool-result', toolCallId: id, toolName: name, output: { type: 'text', value: 'ok' } }]
})

console.log('\n========== 消息完整性修复 ==========')

// 完整的序列不该被改动
{
  const input = [userMsg('看看目录'), toolCallMsg('c1'), toolResultMsg('c1'), { role: 'assistant', content: '好了' }]
  const result = repairMessages(input)
  expect('完整序列不修改', result.repaired, 0)
  expect('完整序列长度不变', result.messages.length, 4)
}

// 中断留下的孤儿 tool-call 必须补上合成结果
{
  const input = [userMsg('装个 nginx'), toolCallMsg('c1')]
  const result = repairMessages(input)
  expect('孤儿 tool-call 被修复', result.repaired, 1)
  expect('补齐后消息数', result.messages.length, 3)
  expect('补的是 tool 消息', result.messages[2].role, 'tool')
  expect('toolCallId 对得上', result.messages[2].content[0].toolCallId, 'c1')
  assert('合成结果标记为错误', result.messages[2].content[0].output.type === 'error-text')
}

// 一条 assistant 消息里多个 tool-call，只有部分有结果
{
  const input = [
    userMsg('并发查两台'),
    {
      role: 'assistant',
      content: [
        { type: 'tool-call', toolCallId: 'c1', toolName: 'host_status', input: {} },
        { type: 'tool-call', toolCallId: 'c2', toolName: 'host_status', input: {} }
      ]
    },
    toolResultMsg('c1', 'host_status')
  ]
  const result = repairMessages(input)
  expect('只补缺失的那个', result.repaired, 1)
  const synthesized = result.messages.filter((m) => m.role === 'tool')
  expect('tool 消息共两条', synthesized.length, 2)
  expect('补的是 c2', synthesized[1].content[0].toolCallId, 'c2')
}

// 没有对应调用的 tool-result 属于非法消息，丢弃
{
  const input = [userMsg('你好'), toolResultMsg('ghost')]
  const result = repairMessages(input)
  expect('孤儿 tool-result 被丢弃', result.messages.length, 1)
  expect('丢弃计入修复数', result.repaired, 1)
}

// 修复后的结果再修一次应当幂等
{
  const once = repairMessages([userMsg('x'), toolCallMsg('c1')])
  const twice = repairMessages(once.messages)
  expect('修复是幂等的', twice.repaired, 0)
  expect('二次修复长度不变', twice.messages.length, once.messages.length)
}

console.log('\n========== 历史裁剪 ==========')

// 裁剪必须落在整轮边界，不能把配对拦腰截断
{
  const messages = []
  for (let i = 0; i < 30; i += 1) {
    messages.push(userMsg(`问题 ${ i }`), toolCallMsg(`c${ i }`), toolResultMsg(`c${ i }`))
  }
  const result = truncateHistory(messages, { maxMessages: 20, maxBytes: 10 * 1024 * 1024 })
  assert('确实发生了裁剪', result.dropped > 0)
  assert('裁剪后不超上限', result.messages.length <= 20)
  expect('裁剪后第一条是 user', result.messages[0].role, 'user')
  // 裁剪后仍然完整
  expect('裁剪后无需再修复', repairMessages(result.messages).repaired, 0)
}

// 字节上限同样生效
{
  const big = 'x'.repeat(50 * 1024)
  const messages = []
  for (let i = 0; i < 20; i += 1) messages.push(userMsg(big), { role: 'assistant', content: 'ok' })
  const result = truncateHistory(messages, { maxMessages: 1000, maxBytes: 200 * 1024 })
  assert('字节超限触发裁剪', result.dropped > 0)
  assert('裁剪后不超字节上限', Buffer.byteLength(JSON.stringify(result.messages)) <= 200 * 1024)
}

// 短历史不该被动
{
  const messages = [userMsg('hi'), { role: 'assistant', content: 'hello' }]
  const result = truncateHistory(messages)
  expect('短历史不裁剪', result.dropped, 0)
}

console.log('\n========== 会话读写 ==========')

{
  const created = await store.createSession({ hostIds: ['h1'], modelId: 'gpt-x', permission: 'auto' })
  assert('创建返回 id', Boolean(created.id))
  expect('初始标题', created.title, '新会话')

  await store.appendTurn(created.id, {
    newMessages: [userMsg('检查一下磁盘占用情况'), { role: 'assistant', content: '已检查' }],
    createdAt: 1722386040000,
    toolMeta: { c1: { risk: 'allow', durationMs: 120 } },
    usage: { inputTokens: 100, outputTokens: 50, totalTokens: 150 }
  })

  const loaded = await store.getSession(created.id)
  expect('消息已落盘', loaded.messages.length, 2)
  expect('toolMeta 已落盘', loaded.toolMeta.c1.durationMs, 120)
  expect('usage 已累加', loaded.usage.totalTokens, 150)
  expect('标题由首条消息生成', loaded.title, '检查一下磁盘占用情况')
  expect('用户消息时间和本轮用量独立落盘', loaded.turnMeta, [{
    createdAt: 1722386040000,
    usage: {
      inputTokens: 100,
      outputTokens: 50,
      totalTokens: 150,
      cachedInputTokens: 0,
      reasoningTokens: 0
    }
  }])

  // 第二轮：usage 继续累加，标题不再变
  await store.appendTurn(created.id, {
    newMessages: [userMsg('再看看内存'), { role: 'assistant', content: '好' }],
    usage: { inputTokens: 10, outputTokens: 5, totalTokens: 15 }
  })
  const second = await store.getSession(created.id)
  expect('usage 跨轮累加', second.usage.totalTokens, 165)
  expect('标题不被后续消息覆盖', second.title, '检查一下磁盘占用情况')

  // 落盘时残缺的历史应当已被修复
  await store.appendTurn(created.id, { newMessages: [userMsg('装 nginx'), toolCallMsg('orphan')] })
  const third = await store.getSession(created.id)
  expect('落盘时已补齐孤儿调用', repairMessages(third.messages).repaired, 0)

  const forModel = await store.loadForModel(created.id)
  expect('读出的历史可直接用', repairMessages(forModel.messages).repaired, 0)

  // 列表摘要不带 messages
  const list = await store.listSessions()
  assert('列表包含该会话', list.some((item) => item.id === created.id))
  assert('列表摘要不带 messages', list.every((item) => item.messages === undefined))

  await store.updateSession(created.id, { title: '磁盘排查' })
  expect('改名生效', (await store.getSession(created.id)).title, '磁盘排查')

  expect('删除成功', await store.removeSession(created.id), true)
  expect('删除后查不到', await store.getSession(created.id), null)
}

console.log('\n========== 编辑消息分支 ==========')

{
  const created = await store.createSession({})
  await store.appendTurn(created.id, {
    newMessages: [
      userMsg('原始首问'),
      toolCallMsg('edit-c1'),
      toolResultMsg('edit-c1'),
      assistantMsg('首轮回答'),
      userMsg('需要修改的追问'),
      assistantMsg('旧的追问回答')
    ],
    toolMeta: { 'edit-c1': { durationMs: 100 } }
  })
  await store.saveCompaction(created.id, { summary: '旧摘要', upTo: 4 })

  const truncated = await store.truncateForUserEdit(created.id, 1, '新的追问')
  expect('编辑时保留前序历史', truncated.messages.length, 4)
  expect('编辑时同步截断消息时间', truncated.turnMeta.length, 1)
  expect('编辑时丢弃旧分支', truncated.messages[3].content, '首轮回答')
  expect('前序工具元数据保留', truncated.toolMeta['edit-c1'].durationMs, 100)
  expect('编辑时移除可能过期的摘要', truncated.compaction, null)

  const firstEdited = await store.truncateForUserEdit(created.id, 0, '新的首问')
  expect('编辑首问时移除全部旧历史', firstEdited.messages.length, 0)
  expect('编辑首问时清空消息时间', firstEdited.turnMeta, [])
  expect('自动标题随首问编辑更新', firstEdited.title, '新的首问')
  expect('移除历史时清理工具元数据', firstEdited.toolMeta, {})

  await store.removeSession(created.id)
}

console.log('\n========== 复制会话分支 ==========')

{
  const created = await store.createSession({
    title: '排查生产环境服务器磁盘和内存占用异常情况',
    scope: 'terminal',
    hostId: 'host-1',
    hostIds: ['host-1'],
    modelId: 'gpt-x',
    permission: 'auto'
  })
  await store.appendTurn(created.id, {
    newMessages: [
      userMsg('第一问'),
      toolCallMsg('fork-c1'),
      toolResultMsg('fork-c1'),
      assistantMsg('第一答')
    ],
    createdAt: 1000,
    toolMeta: { 'fork-c1': { durationMs: 88 }, 'later-c2': { durationMs: 99 } },
    usage: { inputTokens: 10, outputTokens: 5, totalTokens: 15 }
  })
  await store.appendTurn(created.id, {
    newMessages: [userMsg('第二问'), assistantMsg('第二答')],
    createdAt: 2000,
    usage: { inputTokens: 20, outputTokens: 10, totalTokens: 30 }
  })
  await store.saveCompaction(created.id, { summary: '第一轮摘要', upTo: 5 })

  const forked = await store.forkSession(created.id, 0, 1)
  assert('分支创建新 id', forked.id !== created.id)
  expect('分支截止目标回答并保留工具结果', forked.messages.length, 3)
  expect('分支不包含目标后的最终文本', forked.messages.at(-1).role, 'tool')
  expect('分支不影响原会话', (await store.getSession(created.id)).messages.length, 6)
  expect('分支只保留对应轮次元数据', forked.turnMeta.length, 1)
  expect('分支用量按保留轮次重算', forked.usage.totalTokens, 15)
  expect('分支保留已引用工具元数据', forked.toolMeta['fork-c1'].durationMs, 88)
  expect('分支清理未引用工具元数据', forked.toolMeta['later-c2'], undefined)
  expect('分支继承终端作用域', [forked.scope, forked.hostId], ['terminal', 'host-1'])
  assert('分支标题带标识且不超长', forked.title.endsWith('（Fork）') && forked.title.length <= 30)
  expect('目标截止早于摘要范围时不继承摘要', forked.compaction, undefined)

  const forkedLatest = await store.forkSession(created.id, 1)
  expect('最新轮分支保留完整对话', forkedLatest.messages.length, 6)
  expect('最新轮分支用量包含两轮', forkedLatest.usage.totalTokens, 45)
  expect('有效摘要随完整分支继承', forkedLatest.compaction.summary, '第一轮摘要')

  await store.removeSession(forked.id)
  await store.removeSession(forkedLatest.id)
  await store.removeSession(created.id)
}

console.log('\n========== 压缩持久化 ==========')

{
  const created = await store.createSession({})
  const turn = (i) => [userMsg(`问题 ${ i }`), toolCallMsg(`k${ i }`), toolResultMsg(`k${ i }`), assistantMsg(`回答 ${ i }`)]
  for (let i = 0; i < 6; i += 1) {
    await store.appendTurn(created.id, { newMessages: turn(i) })
  }

  const before = await store.getSession(created.id)
  expect('落盘 24 条消息', before.messages.length, 24)

  // 手工写入一次压缩记录：前 12 条被摘要覆盖
  await store.saveCompaction(created.id, { summary: '前三轮已排查完磁盘问题', upTo: 12 })

  const view = await store.loadForModel(created.id)
  expect('摘要被前置', view.messages[0].role, 'user')
  assert('摘要内容在首条消息里', view.messages[0].content.includes('前三轮已排查完磁盘问题'))
  expect('摘要后是 assistant 确认', view.messages[1].role, 'assistant')
  expect('被覆盖的消息不再发给模型', view.messages.length, 2 + 12)
  expect('标记为已压缩', view.compacted, true)
  expect('复用已有摘要时不重复通知前端', view.compactedNow, null)
  expect('拼装后的历史依然完整', repairMessages(view.messages).repaired, 0)

  // 完整消息仍然保留，供前端渲染
  const stillFull = await store.getSession(created.id)
  expect('完整历史未被压缩破坏', stillFull.messages.length, 24)

  // 再追加一轮，摘要与下标必须保持有效
  await store.appendTurn(created.id, { newMessages: turn(99) })
  const after = await store.loadForModel(created.id)
  expect('追加后摘要仍在', after.messages[0].content.includes('前三轮已排查完磁盘问题'), true)
  expect('追加后未覆盖部分正确', after.messages.length, 2 + 16)
  expect('追加后历史完整', repairMessages(after.messages).repaired, 0)

  await store.removeSession(created.id)
}

{
  // 关键回归：appendTurn 里的修复/裁剪会改变数组长度，
  // compaction.upTo 是下标，必须跟着调整，否则摘要会覆盖错范围
  const created = await store.createSession({})
  const bulk = []
  for (let i = 0; i < 60; i += 1) {
    bulk.push(userMsg(`第 ${ i } 问`.repeat(200)), assistantMsg(`第 ${ i } 答`))
  }
  await store.appendTurn(created.id, { newMessages: bulk })
  await store.saveCompaction(created.id, { summary: '早期排查记录', upTo: 40 })

  const beforeAppend = await store.getSession(created.id)
  const beforeLength = beforeAppend.messages.length
  const beforeUpTo = beforeAppend.compaction.upTo

  // 追加到触发裁剪
  const more = []
  for (let i = 0; i < 60; i += 1) {
    more.push(userMsg(`追加 ${ i }`.repeat(200)), assistantMsg(`追加答 ${ i }`))
  }
  await store.appendTurn(created.id, { newMessages: more })

  const afterAppend = await store.getSession(created.id)
  const droppedFromFront = beforeLength + more.length - afterAppend.messages.length
  assert('确实发生了裁剪', droppedFromFront > 0)
  expect('upTo 随裁剪同步下调', afterAppend.compaction.upTo, Math.max(0, beforeUpTo - droppedFromFront))
  assert('upTo 不会越界', afterAppend.compaction.upTo <= afterAppend.messages.length)

  // 最终视图仍然可用
  const finalView = await store.loadForModel(created.id)
  assert('裁剪后摘要仍被带上', finalView.messages[0].content.includes('早期排查记录'))
  expect('裁剪后历史完整', repairMessages(finalView.messages).repaired, 0)

  await store.removeSession(created.id)
}

console.log('\n==================================')
process.chdir(originalCwd)
fs.rmSync(tmpDir, { recursive: true, force: true })

if (failed === 0) {
  console.log(`✅ 全部通过 (${ passed } 项)`)
  process.exit(0)
}
console.log(`❌ ${ failed } 项失败 / 共 ${ passed + failed } 项\n`)
console.log(failures.join('\n\n'))
process.exit(1)
