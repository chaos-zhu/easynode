/** 全局助手真实运行链路回归：模拟模型 HTTP 响应，不连接模型服务或远端主机。 */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const originalCwd = process.cwd()
const testDir = fs.mkdtempSync(path.join(os.tmpdir(), 'easynode-global-agent-'))
fs.mkdirSync(path.join(testDir, 'app/db'), { recursive: true })
process.chdir(testDir)
global.logger = { warn() {}, info() {}, error() {} }

const { HostListDB, AIConfigDB } = await import('../app/utils/db-class.js')
const { runTurn } = await import('../app/ai/runtime.js')
const { createSession, appendTurn, getSession, forkSession } = await import('../app/ai/session-store.js')
const { resolveApproval } = await import('../app/ai/approval.js')
const hostDB = new HostListDB().getInstance()
await new AIConfigDB().getInstance().insertAsync({
  apiUrl: 'https://agent-fixture.invalid/v1', apiKey: 'fixture-key', models: ['fixture'], maxSteps: 5
})
const open = await hostDB.insertAsync({ name: '香港-01', host: '10.0.0.1', port: 22 })
const restricted = await hostDB.insertAsync({
  name: '上海生产', host: '10.0.0.2', port: 2222,
  aiPolicy: { enabled: true, maxEffect: 'read', maxMode: 'review' }
})
const disabled = await hostDB.insertAsync({ name: '禁用机', host: '10.0.0.3', aiPolicy: { enabled: false } })
const targetHost = { hostId: restricted._id, name: restricted.name, address: '10.0.0.2:2222' }

const originalFetch = globalThis.fetch
let replies = []
let requests = []
let sequence = 0
function call(name, input) {
  return { name, input, id: `fixture-call-${ ++sequence }` }
}

globalThis.fetch = async (url, init) => {
  assert.equal(String(url), 'https://agent-fixture.invalid/v1/chat/completions')
  requests.push(JSON.parse(init.body))
  const reply = replies.shift()
  assert.ok(reply, '模型调用次数不能超过预设响应')
  const delta = typeof reply === 'string'
    ? { content: reply }
    : { tool_calls: [{ index: 0, id: reply.id, type: 'function', function: { name: reply.name, arguments: JSON.stringify(reply.input) } }] }
  const chunk = (value, finishReason) => ({
    id: 'fixture', object: 'chat.completion.chunk', created: 0, model: 'fixture',
    choices: [{ index: 0, delta: value, finish_reason: finishReason }]
  })
  const body = [chunk(delta, null), chunk({}, typeof reply === 'string' ? 'stop' : 'tool_calls')]
    .map(value => `data: ${ JSON.stringify(value) }\n\n`).join('') + 'data: [DONE]\n\n'
  return new Response(body, { headers: { 'content-type': 'text/event-stream' } })
}

async function turn(params, responses, approve = false) {
  replies = [...responses]
  requests = []
  const events = []
  const usedHostIds = new Set()
  const result = await runTurn({
    scope: 'ops', permission: 'review', modelId: 'fixture',
    userMessage: { role: 'user', content: '检查上海生产的负载' },
    signal: new AbortController().signal,
    ...params,
    usedHostIds,
    emit(event) {
      events.push(event)
      if (event.type === 'approval_request') resolveApproval(event.requestId, { approved: approve })
    }
  })
  assert.equal(replies.length, 0)
  assert.ok(!events.some(event => event.type === 'error'), JSON.stringify(events))
  return { result, events, usedHostIds }
}

try {
  // 问答本身不会由运行时主动枚举主机；模型是否遵循提示词另做实际对话验收。
  const greeting = await createSession({ scope: 'ops' })
  const originalFind = hostDB.findAsync
  let catalogReads = 0
  hostDB.findAsync = function(...args) {
    catalogReads += 1
    return originalFind.apply(this, args)
  }
  const chat = await turn({ sessionId: greeting.id, userMessage: { role: 'user', content: '你好' } }, ['你好'])
  hostDB.findAsync = originalFind
  assert.equal(catalogReads, 0)
  assert.equal(chat.usedHostIds.size, 0)
  assert.equal(chat.events.filter(event => event.type === 'tool_call').length, 0)
  assert.ok(!requests[0].messages[0].content.includes(open.name))

  for (const hostIds of [undefined, [], [open._id], [disabled._id]]) {
    const session = await createSession({ scope: 'ops', hostIds: [disabled._id] })
    const query = call('host_list', { keyword: '生产' })
    const command = call('exec_command', { hostId: restricted._id, command: 'uptime' })
    const { result, events, usedHostIds } = await turn({ sessionId: session.id, hostIds }, [query, command, '用户拒绝，已停止'])
    assert.ok(events.find(event => event.type === 'turn_start').availableTools.includes('host_list'))
    assert.ok(!events.find(event => event.type === 'turn_start').availableTools.includes('terminal_command'))
    const listing = events.find(event => event.type === 'tool_result' && event.tool === 'host_list')
    assert.deepEqual(listing.output.hosts.map(host => host.hostId), [restricted._id])
    const approval = events.find(event => event.type === 'approval_request')
    assert.deepEqual(approval.targetHost, targetHost)
    assert.equal(approval.mode, 'review')
    assert.deepEqual(result.toolMeta[command.id].targetHost, targetHost)
    assert.deepEqual([...usedHostIds], [restricted._id])
    assert.equal(result.toolMeta[command.id].approved, false)
    await appendTurn(session.id, {
      newMessages: [{ role: 'user', content: '检查上海生产的负载' }, ...result.responseMessages], toolMeta: result.toolMeta
    })
    assert.deepEqual((await getSession(session.id)).toolMeta[command.id].targetHost, targetHost)
    assert.deepEqual((await forkSession(session.id, 0)).toolMeta[command.id].targetHost, targetHost)
  }

  for (const [hostId, reason] of [[disabled._id, '禁止 AI'], ['deleted-host', '未找到主机']]) {
    const session = await createSession({ scope: 'ops' })
    const command = call('exec_command', { hostId, command: 'uptime' })
    const denied = await turn({ sessionId: session.id }, [command, '目标不可访问'])
    assert.ok(denied.events.some(event => event.type === 'tool_denied' && event.reason.includes(reason)))
    assert.equal(denied.events.filter(event => event.type === 'approval_request').length, 0)
    assert.equal(denied.usedHostIds.size, 0)
  }

  const terminal = await createSession({ scope: 'terminal', hostId: open._id, hostIds: [open._id] })
  const attempt = call('terminal_command', { hostId: restricted._id, command: 'uptime' })
  const bound = await turn({
    sessionId: terminal.id, scope: 'terminal', hostIds: [open._id], terminalHostId: open._id,
    terminalPermission: 'review', terminalContext: { output: '', hostName: open.name }
  }, [attempt, '不能操作其他终端'])
  assert.deepEqual(bound.events.find(event => event.type === 'turn_start').availableTools, ['read_output', 'terminal_command'])
  assert.ok(bound.events.some(event => event.type === 'tool_denied' && event.reason.includes('未授权')))
  assert.equal(bound.events.filter(event => event.type === 'approval_request').length, 0)
  assert.equal(bound.usedHostIds.size, 0)
  assert.ok(bound.events.every(event => !event.targetHost))
  console.log('全局助手运行、主机发现、审批目标、历史恢复与终端范围回归通过')
} finally {
  globalThis.fetch = originalFetch
  process.chdir(originalCwd)
  fs.rmSync(testDir, { recursive: true, force: true })
}

process.exit(0)
