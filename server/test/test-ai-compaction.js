/**
 * 上下文压缩测试
 *
 * 运行：node test/test-ai-compaction.js
 *
 * 压缩最容易出的问题是切错位置：把 assistant 的 tool-call 和它的
 * tool-result 拆到两边，留下的历史就是残缺的，发给模型直接 400。
 * 所以每个压缩结果都要过一遍 repairMessages 验证无需修复。
 */

import {
  estimateTokens,
  estimateMessagesTokens,
  renderTranscript,
  findSplitIndex,
  compactMessages,
  isContextLengthError,
  DEFAULT_CONTEXT_LIMIT
} from '../app/ai/compaction.js'
import { repairMessages } from '../app/ai/session-store.js'

global.logger = { warn() {}, info() {}, error() {} }

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
const assistantText = (text) => ({ role: 'assistant', content: text })
const toolCallMsg = (id, command) => ({
  role: 'assistant',
  content: [{ type: 'tool-call', toolCallId: id, toolName: 'exec_command', input: { command } }]
})
const toolResultMsg = (id, value) => ({
  role: 'tool',
  content: [{ type: 'tool-result', toolCallId: id, toolName: 'exec_command', output: { type: 'json', value } }]
})

/** 造 n 轮完整对话，每轮：user → tool-call → tool-result → assistant */
function buildConversation(turns, padding = '') {
  const messages = []
  for (let i = 0; i < turns; i += 1) {
    messages.push(userMsg(`第 ${ i } 个问题${ padding }`))
    messages.push(toolCallMsg(`c${ i }`, `echo ${ i }`))
    messages.push(toolResultMsg(`c${ i }`, { stdout: `输出 ${ i }${ padding }` }))
    messages.push(assistantText(`第 ${ i } 个回答${ padding }`))
  }
  return messages
}

const fakeSummarize = async () => '- 已在 web-01 上检查磁盘，根分区占用 82%\n- 待办：清理 /var/log'

console.log('\n========== token 估算 ==========')

{
  // 中文密度远高于英文，不能一律按 4 字符/token 估
  const chinese = '检查一下这台服务器的磁盘占用情况'
  const english = 'check the disk usage of this server'
  const chineseTokens = estimateTokens(chinese)
  const englishTokens = estimateTokens(english)

  assert('中文估算大于纯字符数除以 4', chineseTokens > chinese.length / 4)
  assert('英文按约 4 字符/token', englishTokens <= Math.ceil(english.length / 4) + 1)
  assert('等长时中文 token 更多', chineseTokens > estimateTokens('a'.repeat(chinese.length)))
  expect('空串为 0', estimateTokens(''), 0)
  expect('null 为 0', estimateTokens(null), 0)
}

{
  const messages = buildConversation(3)
  const total = estimateMessagesTokens(messages)
  assert('多条消息的估算为正', total > 0)
  assert('估算包含每条消息的固定开销', total > messages.reduce((sum, m) => sum + estimateTokens(m), 0))
}

console.log('\n========== 笔录渲染 ==========')

{
  const transcript = renderTranscript([
    userMsg('看看磁盘'),
    toolCallMsg('c1', 'df -h'),
    toolResultMsg('c1', { stdout: '/ 82%' }),
    assistantText('根分区占用 82%')
  ])

  assert('包含用户提问', transcript.includes('看看磁盘'))
  assert('包含工具调用', transcript.includes('df -h'))
  assert('包含工具结果', transcript.includes('82%'))
  assert('包含助手回复', transcript.includes('根分区占用'))
}

{
  // 失败的工具结果要标出来，否则摘要会把失败当成功
  const transcript = renderTranscript([
    toolCallMsg('c1', 'systemctl start nope'),
    { role: 'tool', content: [{ type: 'tool-result', toolCallId: 'c1', output: { type: 'error-text', value: '不存在该单元' } }] }
  ])
  assert('失败结果被标记', transcript.includes('失败'))
}

{
  // 超长输出必须截断，否则摘要素材本身就超限
  const huge = 'x'.repeat(50000)
  const transcript = renderTranscript([toolResultMsg('c1', huge)])
  assert('超长结果被截断', transcript.length < 2000)
  assert('截断有说明', transcript.includes('已截断'))
}

console.log('\n========== 切分点 ==========')

{
  const messages = buildConversation(6)
  const splitAt = findSplitIndex(messages, 3)
  assert('找到切分点', splitAt > 0)
  expect('切分点落在 user 消息上', messages[splitAt].role, 'user')

  const userCountAfter = messages.slice(splitAt).filter((m) => m.role === 'user').length
  expect('保留的轮数符合预期', userCountAfter, 3)
}

{
  // 轮数不够就不该压
  expect('两轮不压缩', findSplitIndex(buildConversation(2), 3), -1)
  expect('空历史不压缩', findSplitIndex([], 3), -1)
}

console.log('\n========== 压缩 ==========')

{
  // 未超阈值不该白白调一次模型
  const result = await compactMessages({
    messages: buildConversation(3),
    summarize: fakeSummarize,
    contextLimit: DEFAULT_CONTEXT_LIMIT
  })
  expect('未超阈值不压缩', result.compacted, false)
  expect('原因是未达阈值', result.reason, 'under-threshold')
}

{
  // 超阈值：压缩后必须变小，且历史仍然完整
  const messages = buildConversation(12, ' '.repeat(600))
  const result = await compactMessages({
    messages,
    summarize: fakeSummarize,
    contextLimit: 4000
  })

  expect('触发压缩', result.compacted, true)
  assert('压缩后 token 显著下降', result.afterTokens < result.beforeTokens / 2)
  assert('丢弃了消息', result.droppedCount > 0)
  expect('压缩后历史无需修复', repairMessages(result.messages).repaired, 0)

  const summaryMsg = result.messages[0]
  expect('摘要以 user 消息回填', summaryMsg.role, 'user')
  assert('摘要内容被带上', summaryMsg.content.includes('根分区占用 82%'))
  expect('摘要后跟一条 assistant 确认', result.messages[1].role, 'assistant')
  expect('保留段紧随其后是 user', result.messages[2].role, 'user')
}

{
  // 强制压缩：即使没超阈值也压，用于超限重试
  const messages = buildConversation(5)
  const result = await compactMessages({
    messages,
    summarize: fakeSummarize,
    contextLimit: DEFAULT_CONTEXT_LIMIT,
    force: true,
    keepRecentTurns: 1
  })
  expect('强制压缩生效', result.compacted, true)
  expect('原因标记为 forced', result.reason, 'forced')
  const remainingUsers = result.messages.slice(2).filter((m) => m.role === 'user').length
  expect('只保留最近一轮', remainingUsers, 1)
  expect('强制压缩后历史完整', repairMessages(result.messages).repaired, 0)
}

{
  // 摘要失败必须降级，不能让整个 turn 挂掉
  const messages = buildConversation(12, ' '.repeat(600))
  const result = await compactMessages({
    messages,
    contextLimit: 4000,
    summarize: async () => {
      throw new Error('模型不可用')
    }
  })
  expect('降级仍算完成压缩', result.compacted, true)
  expect('标记为降级', result.degraded, true)
  assert('降级后仍然变小', result.afterTokens < result.beforeTokens)
  expect('降级后历史完整', repairMessages(result.messages).repaired, 0)
}

{
  // 切分点两侧不能拆散 tool-call 与 tool-result
  const messages = buildConversation(10, ' '.repeat(600))
  const result = await compactMessages({ messages, summarize: fakeSummarize, contextLimit: 4000 })
  const kept = result.messages.slice(2)
  const callIds = kept.filter((m) => m.role === 'assistant' && Array.isArray(m.content))
    .flatMap((m) => m.content.filter((p) => p.type === 'tool-call').map((p) => p.toolCallId))
  const resultIds = kept.filter((m) => m.role === 'tool')
    .flatMap((m) => m.content.map((p) => p.toolCallId))
  expect('保留段内调用与结果一一对应', callIds.sort(), resultIds.sort())
}

console.log('\n========== 超限错误识别 ==========')

assert('识别 context length', isContextLengthError(new Error('This model\'s maximum context length is 8192 tokens')))
assert('识别 context_length_exceeded', isContextLengthError(new Error('code: context_length_exceeded')))
assert('识别 request too large', isContextLengthError(new Error('Request too large for gpt-4')))
assert('识别 prompt is too long', isContextLengthError(new Error('prompt is too long: 250000 tokens')))
assert('识别 413 状态码', isContextLengthError({ statusCode: 413, message: 'Payload Too Large' }))
assert('普通错误不误判', !isContextLengthError(new Error('connect ETIMEDOUT')))
assert('鉴权错误不误判', !isContextLengthError(new Error('invalid api key')))
assert('空错误不误判', !isContextLengthError(null))

console.log('\n==================================')
if (failed === 0) {
  console.log(`✅ 全部通过 (${ passed } 项)`)
  process.exit(0)
}
console.log(`❌ ${ failed } 项失败 / 共 ${ passed + failed } 项\n`)
console.log(failures.join('\n\n'))
process.exit(1)
