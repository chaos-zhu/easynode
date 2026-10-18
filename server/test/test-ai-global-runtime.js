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

const { HostListDB, AIConfigDB, ScriptGroupDB, GroupDB, KeyDB, ScriptsDB, ScheduledTaskDB } = await import('../app/utils/db-class.js')
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
  await new GroupDB().getInstance().updateAsync({ _id: 'default' }, { _id: 'default', name: 'Default' }, { upsert: true })
  await new ScriptGroupDB().getInstance().updateAsync({ _id: 'default' }, { _id: 'default', name: 'Default' }, { upsert: true })
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

  const blockedBatch = call('host_metadata_batch_update', { items: [{ hostId: restricted._id, changes: { name: 'Disallowed' } }] })
  const blocked = await turn({ sessionId: (await createSession({ scope: 'ops' })).id }, [blockedBatch, '只读主机不可修改'])
  assert.ok(blocked.events.some(event => event.type === 'tool_denied' && event.reason.includes('仅允许')))
  assert.equal(blocked.events.filter(event => event.type === 'approval_request').length, 0)
  const noPlus = call('script_batch_create', { items: [{ name: 'No license', command: 'echo saved' }] })
  const free = await turn({ sessionId: (await createSession({ scope: 'ops' })).id }, [noPlus, '需要 Plus'])
  assert.ok(free.events.some(event => event.type === 'tool_requires_plus'))
  assert.equal(free.events.filter(event => event.type === 'panel_data_changed').length, 0)

  // Exercise real approvals and execution without requiring a release license.
  // Only replace the Plus loading boundary; no SSH commands are executed.
  const { BUILTIN_TOOL_DEFINITIONS } = await import('../app/ai/tools/registry.js')
  const { executeAuthorizedPanelBatch } = await import('../app/services/panel-batch.js')
  const definition = BUILTIN_TOOL_DEFINITIONS.find(tool => tool.name === 'script_batch_update')
  const originalDefinition = { plusPolicy: definition.plusPolicy, execute: definition.execute }
  const scripts = new ScriptsDB().getInstance()
  const tasks = new ScheduledTaskDB().getInstance()
  const script = await scripts.insertAsync({ name: 'Referenced script', command: 'echo old', group: 'default' })
  const task = await tasks.insertAsync({ name: 'Referencing task', enabled: true, hostIds: [open._id],
    script: { type: 'library', scriptId: script._id } })
  const update = changes => call('script_batch_update', { items: [{ scriptId: script._id, changes }] })
  const runUpdate = async (mutation, approve = false) => turn({
    sessionId: (await createSession({ scope: 'ops' })).id, permission: 'authorized'
  }, [mutation, '完成'], approve)
  definition.plusPolicy = 'free'
  definition.execute = (ctx, input, options) => executeAuthorizedPanelBatch(definition.name, ctx, input, options, () => {})
  try {
    for (const host of [disabled, restricted]) {
      await tasks.updateAsync({ _id: task._id }, { $set: { hostIds: [host._id] } })
      const denied = await runUpdate(update({ command: 'echo new' }), true)
      assert.ok(denied.events.some(event => event.type === 'tool_denied' && /禁止 AI|仅允许/.test(event.reason)))
      assert.equal((await scripts.findOneAsync({ _id: script._id })).command, 'echo old')
      assert.ok(!denied.events.some(event => event.type === 'panel_data_changed'))
    }
    // Metadata edits remain panel-only, even when a task targets a read-only host.
    const metadata = await runUpdate(update({ description: 'Documentation only' }))
    assert.equal(metadata.events.find(event => event.type === 'tool_result').output.status, 'success')
    assert.ok(!metadata.events.some(event => event.type === 'approval_request'))

    await tasks.updateAsync({ _id: task._id }, { $set: { hostIds: [open._id] } })
    const denied = await runUpdate(update({ command: 'rm -rf /' }), true)
    assert.ok(denied.events.some(event => event.type === 'tool_denied' && event.permanent))
    assert.equal((await scripts.findOneAsync({ _id: script._id })).command, 'echo old')
    assert.ok(!denied.events.some(event => event.type === 'approval_request'))

    for (const approved of [false, true]) {
      const mutation = update({ command: 'systemctl restart sshd' })
      const high = await runUpdate(mutation, approved)
      const approval = high.events.find(event => event.type === 'approval_request')
      assert.equal(approval.risk.level, 'high')
      assert.equal(approval.preview.type, 'panel_batch')
      assert.equal(high.result.toolMeta[mutation.id].approved, approved)
      assert.equal((await scripts.findOneAsync({ _id: script._id })).command, approved ? 'systemctl restart sshd' : 'echo old')
    }

    // Host maxMode must still require confirmation in an authorized session.
    await hostDB.updateAsync({ _id: open._id }, { $set: { aiPolicy: { maxMode: 'review' } } })
    const clamped = await runUpdate(update({ command: 'echo safe' }))
    assert.equal(clamped.events.find(event => event.type === 'approval_request').mode, 'review')
    assert.equal((await scripts.findOneAsync({ _id: script._id })).command, 'systemctl restart sshd')
    await hostDB.updateAsync({ _id: open._id }, { $unset: { aiPolicy: true } })
    const safe = await runUpdate(update({ command: 'echo safe' }))
    assert.ok(!safe.events.some(event => event.type === 'approval_request'))
    assert.equal(safe.events.find(event => event.type === 'tool_result').output.status, 'success')
    assert.equal((await tasks.findOneAsync({ _id: task._id })).enabled, true)

    // Saving an unreferenced script does not execute it or inherit host policies.
    await tasks.removeAsync({ _id: task._id })
    const unreferenced = await runUpdate(update({ command: 'systemctl restart sshd' }))
    assert.ok(!unreferenced.events.some(event => event.type === 'approval_request'))
    assert.equal(unreferenced.events.find(event => event.type === 'tool_result').output.status, 'success')
  } finally {
    Object.assign(definition, originalDefinition)
    await hostDB.updateAsync({ _id: open._id }, { $unset: { aiPolicy: true } })
    await tasks.removeAsync({ _id: task._id })
    await scripts.removeAsync({ _id: script._id })
  }

  // Optional local encrypted-module integration. Portable service tests do not require release keys.
  if (process.env.PANEL_BATCH_TEST_PLUS_KEY) {
    const { AESEncryptAsync } = await import('../app/utils/encrypt.js')
    const { RuntimeState } = await import('../app/utils/runtime-state.js')
    await new KeyDB().getInstance().insertAsync({ commonKey: 'isolated-fixture-key' })
    const runtime = new RuntimeState().getInstance()
    runtime.setDecryptKey(await AESEncryptAsync(process.env.PANEL_BATCH_TEST_PLUS_KEY))
    runtime.setPlusKicked(false)
    for (const approved of [false, true]) {
      const mutation = call('host_metadata_batch_update', { items: [{ hostId: open._id, changes: { name: 'Renamed from agent' } }] })
      const output = await turn({ sessionId: (await createSession({ scope: 'ops' })).id }, [mutation, '完成'], approved)
      const approval = output.events.find(event => event.type === 'approval_request')
      assert.equal(approval.preview.type, 'panel_batch')
      assert.equal(approval.preview.items[0].changes[0].before, open.name)
      assert.equal(output.events.filter(event => event.type === 'panel_data_changed').length, approved ? 1 : 0)
      if (approved) {
        const batch = output.events.find(event => event.type === 'tool_result').output
        assert.equal(batch.status, 'success')
        assert.equal(output.result.toolMeta[mutation.id].panelBatchResult.status, 'success')
      }
    }
    const create = call('script_batch_create', { items: [{ name: 'Saved only', command: 'echo never executed' }] })
    const created = await turn({ sessionId: (await createSession({ scope: 'ops' })).id, permission: 'authorized' }, [create, '已保存'])
    assert.equal(created.events.filter(event => event.type === 'approval_request').length, 0)
    assert.equal(created.events.find(event => event.type === 'tool_result').output.status, 'success')
    runtime.clearDecryptKey()
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
