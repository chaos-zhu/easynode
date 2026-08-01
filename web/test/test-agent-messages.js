/**
 * Agent 消息模型测试
 *
 * 运行：node test/test-agent-messages.js
 *
 * 最关键的断言是「两条来路一致」：实时事件流构建出的消息，和刷新后从
 * 后端 ModelMessage[] 还原出的消息，形状必须相同。不然同一段对话在刷新
 * 前后长得不一样，用户会以为数据丢了。
 */

import {
  applyEvent,
  createUserMessage,
  findPreviousUserMessage,
  findUserTurnIndex,
  fromModelMessages,
  messageText,
  normalizeToolOutput,
  emptyUsage,
  removeApproval,
  ToolStatus
} from '../src/composables/agentMessages.js'
import {
  agentToolAccessClass,
  agentToolAccessLabel,
  availableAgentTools
} from '../src/composables/agentTools.js'
import { resolveTerminalRequestId } from '../src/composables/agentTerminal.js'

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

function newState() {
  return {
    messages: [],
    pendingApprovals: [],
    usage: emptyUsage(),
    turnUsage: emptyUsage(),
    running: false,
    aborted: false,
    error: null,
    streamWarning: null,
    finishReason: ''
  }
}

function feed(state, events) {
  for (const event of events) applyEvent(state, event)
  return state
}

/** 只保留形状相关的字段，忽略 id 与时间戳 */
function shape(messages) {
  return messages.map((message) => ({
    role: message.role,
    parts: message.parts.map((part) => {
      if (part.type === 'tool') {
        return {
          type: 'tool',
          tool: part.tool,
          input: part.input,
          status: part.status,
          output: part.output ?? null,
          error: part.error ?? null
        }
      }
      return { type: part.type, text: part.text }
    })
  }))
}

console.log('\n========== 事件流构建 ==========')

expect(
  '终端命令复用 Agent 调度 requestId',
  resolveTerminalRequestId({ requestId: 'agent-request-1' }, () => 'generated'),
  'agent-request-1'
)
expect(
  '缺少调度 requestId 时生成回退值',
  resolveTerminalRequestId({}, () => 'generated'),
  'generated'
)

{
  const state = newState()
  state.messages.push(createUserMessage('看看负载'))
  feed(state, [
    { type: 'turn_start', policy: { mode: 'assist' }, availableTools: ['exec_command',] },
    { type: 'text_delta', text: '我' },
    { type: 'text_delta', text: '来看看' },
  ])
  expect('连续文本增量并进同一个 part', state.messages[1].parts.length, 1)
  expect('文本被正确拼接', state.messages[1].parts[0].text, '我来看看')
  expect('turn_start 置为运行中', state.running, true)
}

{
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'reasoning_delta', text: '先确认' },
    { type: 'reasoning_delta', text: '目标主机' },
    { type: 'text_delta', text: '正文开始' },
  ])
  const parts = state.messages[0].parts
  expect('思考与正文分成两个 part', parts.length, 2)
  expect('思考 part 已定型', parts[0].done, true)
  expect('思考内容完整', parts[0].text, '先确认目标主机')
  expect('正文不并进思考', parts[1].text, '正文开始')
}

{
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'tool_call', toolCallId: 't1', tool: 'exec_command', input: { command: 'uptime' } },
    { type: 'tool_progress', toolCallId: 't1', durationMs: 320 },
    { type: 'tool_result', toolCallId: 't1', output: { type: 'json', value: { stdout: 'ok', exitCode: 0 } } },
  ])
  const part = state.messages[0].parts[0]
  expect('工具卡片已完成', part.status, ToolStatus.DONE)
  expect('耗时已记录', part.durationMs, 320)
  expect('输出已解包', part.output, { stdout: 'ok', exitCode: 0 })
}

{
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'tool_call', toolCallId: 't1', tool: 'exec_command', input: { command: 'rm -rf /' } },
    { type: 'tool_denied', toolCallId: 't1', tool: 'exec_command', reason: '会摧毁系统', category: '根目录破坏', permanent: true },
  ])
  const part = state.messages[0].parts[0]
  expect('被拦截状态', part.status, ToolStatus.DENIED)
  expect('拦截原因', part.error, '会摧毁系统')
  expect('风险级别', part.risk.level, 'deny')
}

{
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'tool_call', toolCallId: 't1', tool: 'exec_command', input: { command: 'apt purge nginx' } },
    {
      type: 'approval_request',
      requestId: 'r1',
      toolCallId: 't1',
      tool: 'exec_command',
      input: { command: 'apt purge nginx' },
      effect: 'delete',
      targets: ['nginx',],
      risk: { level: 'high', reason: '卸载软件包' }
    },
  ])
  expect('进入待审批状态', state.messages[0].parts[0].status, ToolStatus.AWAITING_APPROVAL)
  expect('审批入队', state.pendingApprovals.length, 1)
  expect('审批操作类型', state.pendingApprovals[0].effect, 'delete')
  expect('审批目标', state.pendingApprovals[0].targets, ['nginx',])

  removeApproval(state, 'r1')
  expect('审批出队', state.pendingApprovals.length, 0)
}

{
  const state = newState()
  const preview = {
    type: 'write_file',
    path: '/etc/app.conf',
    operation: 'overwrite',
    diff: '--- old\n+++ new\n-old\n+new'
  }
  feed(state, [
    { type: 'turn_start' },
    { type: 'tool_call', toolCallId: 'write-1', tool: 'write_file', input: { path: '/etc/app.conf' } },
    {
      type: 'approval_request',
      requestId: 'write-approval',
      toolCallId: 'write-1',
      tool: 'write_file',
      input: { path: '/etc/app.conf' },
      preview
    },
  ])
  expect('写文件审批保留结构化预览', state.pendingApprovals[0].preview, preview)
  assert('完整 diff 可供审批组件展示', state.pendingApprovals[0].preview.diff.includes('+new'))
}

{
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'tool_call', toolCallId: 'script-1', tool: 'run_script', input: { scriptId: 'QC7j58fhfF' } },
    {
      type: 'approval_request',
      requestId: 'script-approval',
      toolCallId: 'script-1',
      tool: 'run_script',
      input: {
        scriptId: 'QC7j58fhfF',
        scriptName: '查看系统信息',
        command: 'uname -a'
      }
    },
  ])
  const part = state.messages[0].parts[0]
  expect('脚本审批时补充脚本名称', part.input.scriptName, '查看系统信息')
  expect('工具卡片参数不混入脚本内容', part.input.command, undefined)
}

{
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'tool_call', toolCallId: 't1', tool: 'exec_command', input: {} },
    { type: 'aborted' },
  ])
  expect('中断后不再运行', state.running, false)
  expect('未完成的工具收尾为失败', state.messages[0].parts[0].status, ToolStatus.ERROR)
  assert('失败原因说明是中断', /中断/.test(state.messages[0].parts[0].error))
}

{
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'step_finish', usage: { inputTokens: 100, outputTokens: 20, totalTokens: 120 } },
    { type: 'step_finish', usage: { inputTokens: 50, outputTokens: 10, totalTokens: 60 } },
  ])
  expect('本轮用量逐步累加', state.turnUsage.totalTokens, 180)
  expect('输入累加', state.turnUsage.inputTokens, 150)
  expect('会话累计量不被本轮污染', state.usage.totalTokens, 0)
}

{
  // 第二轮开始时本轮用量必须归零，否则会把上一轮的量重复计进去
  const state = newState()
  state.usage = { ...emptyUsage(), totalTokens: 500 }
  feed(state, [
    { type: 'turn_start' },
    { type: 'step_finish', usage: { totalTokens: 60 } },
    { type: 'finish', usage: { inputTokens: 40, outputTokens: 20, totalTokens: 60 } },
  ])
  expect('finish 用 totalUsage 校正本轮', state.turnUsage.totalTokens, 60)
  expect('finish 把用量绑定到本轮回答', state.messages[0].usage, {
    inputTokens: 40,
    outputTokens: 20,
    totalTokens: 60,
    cachedInputTokens: 0,
    reasoningTokens: 0
  })
  expect('finish 不覆盖会话累计量', state.usage.totalTokens, 500)

  feed(state, [{ type: 'turn_start' },])
  expect('新一轮开始时本轮用量归零', state.turnUsage.totalTokens, 0)
  expect('会话累计量跨轮保留', state.usage.totalTokens, 500)
}

{
  // 流内的局部错误不该结束整轮，也不该把工具卡片标成失败
  const state = newState()
  feed(state, [
    { type: 'turn_start' },
    { type: 'tool_call', toolCallId: 't1', tool: 'exec_command', input: {} },
    { type: 'stream_error', message: '某个 step 出错' },
  ])
  expect('流内错误不结束本轮', state.running, true)
  expect('流内错误不动工具状态', state.messages[0].parts[0].status, ToolStatus.RUNNING)
  expect('流内错误记为警告', state.streamWarning, '某个 step 出错')
  expect('流内错误不置整轮错误', state.error, null)
}

console.log('\n========== 工具输出解包 ==========')

expect('json 输出解包', normalizeToolOutput({ type: 'json', value: { a: 1 } }), { a: 1 })
expect('text 输出解包', normalizeToolOutput({ type: 'text', value: 'hi' }), 'hi')
expect('错误输出带标记', normalizeToolOutput({ type: 'error-text', value: 'boom' }), { __error: true, value: 'boom' })
expect('裸对象原样返回', normalizeToolOutput({ a: 1 }), { a: 1 })
expect('null 保持 null', normalizeToolOutput(null), null)

console.log('\n========== 助手工具说明 ==========')

{
  const tools = [
    { name: 'host_status', effect: 'read', plusPolicy: 'free' },
    { name: 'exec_command', plusPolicy: 'by-effect' },
    { name: 'terminal_command', plusPolicy: 'by-effect' },
    { name: 'write_file', effect: 'write', plusPolicy: 'required' },
  ]
  expect('未选择主机时运维助手不开放工具', availableAgentTools(tools, {
    scope: 'ops',
    preset: 'authorized',
    hasSelectedHosts: false,
    plusAvailable: true
  }), [])
  expect('审查模式展示完整工具集', availableAgentTools(tools, {
    scope: 'ops',
    preset: 'review',
    hasSelectedHosts: true,
    plusAvailable: false
  }).map((tool) => tool.name), ['host_status', 'exec_command', 'write_file',])
  expect('协助模式展示相同工具集', availableAgentTools(tools, {
    scope: 'ops',
    preset: 'assist',
    hasSelectedHosts: true,
    plusAvailable: false
  }).map((tool) => tool.name), ['host_status', 'exec_command', 'write_file',])
  expect('终端助手只展示终端工具', availableAgentTools(tools, {
    scope: 'terminal'
  }).map((tool) => tool.name), ['terminal_command',])
  expect('免费工具展示免费只读标识', agentToolAccessLabel(tools[0], false), '免费只读')
  expect('动态工具展示变更需 Plus', agentToolAccessLabel(tools[1], false), '只读免费 · 变更 Plus')
  expect('未激活时固定写入工具展示 Plus 要求', agentToolAccessLabel(tools[3], false), '需要 Plus')
  expect('固定写入工具使用 Plus 样式', agentToolAccessClass(tools[3]), 'is_plus')
}

console.log('\n========== 回答重新生成 ==========')

{
  const firstUser = { id: 'u1', role: 'user', parts: [{ type: 'text', text: '第一个问题' },] }
  const firstAnswer = { id: 'a1', role: 'assistant', parts: [{ type: 'text', text: '第一个回答' },] }
  const secondUser = {
    id: 'u2',
    role: 'user',
    parts: [{ type: 'text', text: '第二个' }, { type: 'text', text: '问题' },]
  }
  const secondAnswer = { id: 'a2', role: 'assistant', parts: [{ type: 'text', text: '第二个回答' },] }
  const messages = [firstUser, firstAnswer, secondUser, secondAnswer,]

  expect('重新生成定位最近的用户消息', findPreviousUserMessage(messages, 'a2')?.id, 'u2')
  expect('重新生成恢复完整用户文本', messageText(secondUser), '第二个问题')
  expect('找不到目标回答时返回空', findPreviousUserMessage(messages, 'missing'), null)
  expect('分支定位第二轮回答', findUserTurnIndex(messages, 'a2'), 1)
  expect('分支定位第一轮回答', findUserTurnIndex(messages, 'a1'), 0)
  expect('分支目标不存在', findUserTurnIndex(messages, 'missing'), -1)
}

console.log('\n========== 历史还原 ==========')

{
  const modelMessages = [
    { role: 'user', content: '看看负载' },
    {
      role: 'assistant',
      content: [
        { type: 'text', text: '我来执行' },
        { type: 'tool-call', toolCallId: 't1', toolName: 'exec_command', input: { command: 'uptime' } },
      ]
    },
    {
      role: 'tool',
      content: [{ type: 'tool-result', toolCallId: 't1', toolName: 'exec_command', output: { type: 'json', value: { stdout: 'ok' } } },]
    },
    { role: 'assistant', content: '负载正常' },
  ]
  const toolMeta = { t1: { durationMs: 210, risk: 'normal', approved: true, approvalScope: 'once' } }
  const restored = fromModelMessages(modelMessages, toolMeta, [{
    createdAt: 1722386040000,
    usage: { inputTokens: 80, outputTokens: 20, totalTokens: 100 }
  },])

  expect('消息条数', restored.length, 3)
  expect('用户消息文本', restored[0].parts[0].text, '看看负载')
  expect('用户消息时间从 turnMeta 还原', restored[0].createdAt, 1722386040000)
  expect('回答保留后端消息位置供精确分支', [restored[1].sourceIndex, restored[2].sourceIndex,], [1, 3,])
  const toolPart = restored[1].parts[1]
  expect('工具状态还原为完成', toolPart.status, ToolStatus.DONE)
  expect('输出还原', toolPart.output, { stdout: 'ok' })
  expect('耗时从 toolMeta 合回', toolPart.durationMs, 210)
  expect('审批信息还原', toolPart.approval, { approved: true, scope: 'once', cached: undefined })
  assert('normal 级别不产生风险标记', toolPart.risk === undefined)
  assert('同轮中间回答不重复显示用量', restored[1].usage === undefined)
  expect('Token 用量绑定到该轮最后一个回答', restored[2].usage, {
    inputTokens: 80,
    outputTokens: 20,
    totalTokens: 100,
    cachedInputTokens: 0,
    reasoningTokens: 0
  })
}

{
  const restored = fromModelMessages([{ role: 'user', content: '旧会话' },])
  expect('旧会话没有时间元数据时保持未知', restored[0].createdAt, 0)
}

{
  // 历史里有调用没结果 —— 后端修复会补合成结果，但万一没有，前端也不能转圈
  const restored = fromModelMessages([
    { role: 'user', content: 'x' },
    { role: 'assistant', content: [{ type: 'tool-call', toolCallId: 't1', toolName: 'exec_command', input: {} },] },
  ], {})
  expect('无结果的调用还原为失败', restored[1].parts[0].status, ToolStatus.ERROR)
}

{
  // 被拦截的调用：后端补的是 error-text，但 toolMeta 标了 denied，应保持 denied
  const restored = fromModelMessages([
    { role: 'user', content: 'x' },
    { role: 'assistant', content: [{ type: 'tool-call', toolCallId: 't1', toolName: 'exec_command', input: {} },] },
    { role: 'tool', content: [{ type: 'tool-result', toolCallId: 't1', output: { type: 'error-text', value: '被拦截' } },] },
  ], { t1: { denied: true, risk: 'deny', riskReason: '高危' } })
  expect('拦截状态优先于普通错误', restored[1].parts[0].status, ToolStatus.DENIED)
  expect('风险信息还原', restored[1].parts[0].risk.level, 'deny')
}

{
  // reasoning 也要能还原
  const restored = fromModelMessages([
    { role: 'assistant', content: [{ type: 'reasoning', text: '想一下' }, { type: 'text', text: '好' },] },
  ], {})
  expect('reasoning part 还原', restored[0].parts[0].type, 'reasoning')
  expect('reasoning 还原后已定型', restored[0].parts[0].done, true)
}

console.log('\n========== 两条来路一致性 ==========')

{
  // 同一段对话：一次走事件流，一次走历史还原，形状必须相同
  const streamed = newState()
  streamed.messages.push(createUserMessage('查一下磁盘'))
  feed(streamed, [
    { type: 'turn_start' },
    { type: 'text_delta', text: '我来' },
    { type: 'text_delta', text: '看看' },
    { type: 'tool_call', toolCallId: 't1', tool: 'exec_command', input: { command: 'df -h' } },
    { type: 'tool_result', toolCallId: 't1', output: { type: 'json', value: { stdout: '/ 40%' } } },
    { type: 'finish', finishReason: 'stop' },
  ])

  const restored = fromModelMessages([
    { role: 'user', content: '查一下磁盘' },
    {
      role: 'assistant',
      content: [
        { type: 'text', text: '我来看看' },
        { type: 'tool-call', toolCallId: 't1', toolName: 'exec_command', input: { command: 'df -h' } },
      ]
    },
    {
      role: 'tool',
      content: [{ type: 'tool-result', toolCallId: 't1', toolName: 'exec_command', output: { type: 'json', value: { stdout: '/ 40%' } } },]
    },
  ], {})

  expect('事件流与历史还原形状一致', shape(streamed.messages), shape(restored))
}

console.log('\n==================================')
if (failed === 0) {
  console.log(`✅ 全部通过 (${ passed } 项)`)
  process.exit(0)
}
console.log(`❌ ${ failed } 项失败 / 共 ${ passed + failed } 项\n`)
console.log(failures.join('\n\n'))
process.exit(1)
