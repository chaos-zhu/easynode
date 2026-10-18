/**
 * 主机级访问控制与授权范围测试
 *
 * 运行：node test/test-ai-access.js
 *
 * 覆盖三个曾被审查发现的越权口子：
 *   1. 全局主机发现仍遵守主机策略，终端助手不能越过绑定范围
 *   2. cwd 被拼进 shell，用 JSON.stringify 转义挡不住 $(...) 展开
 *   3. 会话级"始终允许"粒度太粗，且能豁免掉 high 的强制确认
 */

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'easynode-access-test-'))
fs.mkdirSync(path.join(tmpDir, 'app/db'), { recursive: true })
const originalCwd = process.cwd()
process.chdir(tmpDir)

global.logger = { warn() {}, info() {}, error() {} }

const {
  resolveHostAccess,
  resolvePanelHostAccess,
  buildAllowedHostIds,
  HostAccessError
} = await import(`${ originalCwd }/app/ai/host-access.js`)
const { shellQuote, wrapCommand } = await import(`${ originalCwd }/app/ai/ssh.js`)
const { grantKey, requestApproval, resolveApproval, clearSession } = await import(`${ originalCwd }/app/ai/approval.js`)
const { HostListDB, GroupDB, ScheduledTaskDB } = await import(`${ originalCwd }/app/utils/db-class.js`)
const { Effect, Mode, strongerEffect } = await import(`${ originalCwd }/app/ai/policy.js`)
const { normalizeMaxSteps, DEFAULT_MAX_STEPS, MAX_MAX_STEPS, deriveBaseURL } = await import(`${ originalCwd }/app/ai/provider.js`)
const { getToolSpec, PlusPolicy, requiresPlus } = await import(`${ originalCwd }/app/ai/tools/spec.js`)
const { requestTerminalDispatch } = await import(`${ originalCwd }/app/ai/terminal-dispatch.js`)
const { buildTools, describeAvailableTools } = await import(`${ originalCwd }/app/ai/tools/index.js`)
const {
  hostList,
  scheduledTaskGet,
  scheduledTaskList,
  checkRestrictedToolAccess
} = await import(`${ originalCwd }/app/ai/tools/executors.js`)
const { RuntimeState } = await import(`${ originalCwd }/app/utils/runtime-state.js`)

const hostListDB = new HostListDB().getInstance()
const scheduledTaskDB = new ScheduledTaskDB().getInstance()

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

async function expectReject(label, promise, matcher) {
  try {
    await promise
    failed += 1
    failures.push(`  ${ label }\n    期望抛出但成功返回了`)
  } catch (error) {
    if (error instanceof HostAccessError && matcher.test(error.message)) {
      passed += 1
      return
    }
    failed += 1
    failures.push(`  ${ label }\n    抛出的错误不符预期: ${ error.message }`)
  }
}

// 三台主机：不限制 / 只读上限 / 禁用 AI
const group = await new GroupDB().getInstance().insertAsync({ name: '香港分组' })
const open = await hostListDB.insertAsync({
  name: '测试机', host: '10.0.0.1', port: 22, group: group._id,
  password: 'fixture-password', privateKey: 'fixture-private-key', credential: 'fixture-credential'
})
const restricted = await hostListDB.insertAsync({
  name: '生产机', host: '10.0.0.2', port: 22,
  aiPolicy: { enabled: true, maxEffect: Effect.READ, maxMode: Mode.REVIEW }
})
const disabled = await hostListDB.insertAsync({
  name: '禁用机', host: '10.0.0.3', port: 22,
  aiPolicy: { enabled: false }
})
const panelTask = await scheduledTaskDB.insertAsync({
  name: '跨主机定时任务', enabled: false, hostIds: [open._id, restricted._id],
  cron: '0 2 * * *', timezone: 'Asia/Shanghai', timeoutSeconds: 120,
  script: { type: 'inline', command: 'true', useBase64: false },
  notificationPolicy: 'failure', createdAt: Date.now(), updatedAt: Date.now()
})

console.log('\n========== 主机访问控制 ==========')

{
  // 未绑定的终端上下文必须拒绝主机操作，不能误用全局范围。
  const ctx = { scope: 'terminal', sessionMode: Mode.AUTHORIZED, allowedHostIds: buildAllowedHostIds([]) }

  await expectReject('未选择主机时拒绝普通主机', resolveHostAccess(open._id, ctx, Effect.WRITE), /当前会话未授权/)
  await expectReject('未选择主机时拒绝受限主机', resolveHostAccess(restricted._id, ctx, Effect.READ), /当前会话未授权/)

  const panelAccess = await resolvePanelHostAccess(open._id, ctx, Effect.WRITE)
  expect('面板级操作不依赖会话主机选择', panelAccess.host.name, '测试机')
  await expectReject(
    '面板级操作仍遵守主机 AI 策略',
    resolvePanelHostAccess(restricted._id, ctx, Effect.WRITE),
    /仅允许/
  )
}

{
  const ctx = { scope: 'terminal', sessionMode: Mode.AUTHORIZED, allowedHostIds: buildAllowedHostIds([open._id, restricted._id, disabled._id]) }

  const access = await resolveHostAccess(open._id, ctx, Effect.WRITE)
  expect('范围内普通主机可访问', access.host.name, '测试机')
  expect('普通主机沿用会话模式', access.policy.mode, Mode.AUTHORIZED)

  await expectReject(
    '受限主机拒绝超出其上限的工具',
    resolveHostAccess(restricted._id, ctx, Effect.WRITE),
    /仅允许/
  )

  const readonlyAccess = await resolveHostAccess(restricted._id, ctx, Effect.READ)
  expect('受限主机仍放行只读工具', readonlyAccess.host.name, '生产机')
  expect('受限主机操作范围被压到只读', readonlyAccess.policy.maxEffect, Effect.READ)
  expect('受限主机模式被压到审查', readonlyAccess.policy.mode, Mode.REVIEW)

  await expectReject('禁用 AI 的主机被拒绝', resolveHostAccess(disabled._id, ctx, 'host_status'), /禁止/)
  await expectReject('缺少 hostId 被拒绝', resolveHostAccess('', ctx, 'host_status'), /缺少 hostId/)
}

{
  const ctx = { scope: 'terminal', sessionMode: Mode.AUTHORIZED, allowedHostIds: buildAllowedHostIds(['nope']) }
  await expectReject('不存在的范围内主机被拒绝', resolveHostAccess('nope', ctx, Effect.READ), /未找到/)
}

{
  // 会话已指定主机：这是最关键的一条 —— 模型不能靠 host_list 越界
  const ctx = { scope: 'terminal', sessionMode: Mode.AUTHORIZED, allowedHostIds: buildAllowedHostIds([open._id]) }

  const access = await resolveHostAccess(open._id, ctx, Effect.WRITE)
  expect('范围内主机可访问', access.host.name, '测试机')

  await expectReject(
    '范围外主机被拒绝（越权核心用例）',
    resolveHostAccess(restricted._id, ctx, Effect.READ),
    /当前会话未授权/
  )
}

console.log('\n========== 全局主机发现 ==========')

{
  const ctx = {
    scope: 'ops',
    policy: { mode: Mode.AUTHORIZED, maxEffect: Effect.WRITE },
    sessionMode: Mode.AUTHORIZED,
    allowedHostIds: buildAllowedHostIds([]),
    usedHostIds: new Set()
  }
  const toolNames = Object.keys(buildTools(ctx))
  for (const name of ['host_list', 'host_status', 'script_list', 'exec_command', 'write_file', 'read_output', 'scheduled_task_list']) {
    assert(`全局助手无需预选即可使用 ${ name }`, toolNames.includes(name))
  }
  assert('全局助手不开放终端命令', !toolNames.includes('terminal_command'))
  assert('工具说明不再要求预选主机', !describeAvailableTools(ctx).includes('当前未选择目标主机'))

  const allIds = [open._id, restricted._id, disabled._id].sort()
  for (const selection of [[], [open._id], [disabled._id]]) {
    ctx.allowedHostIds = buildAllowedHostIds(selection)
    const listed = await hostList(ctx, {})
    expect('旧选择不再限制全局目录', listed.data.hosts.map(host => host.hostId).sort(), allIds)
    expect('禁用主机在目录标记不可操作', listed.data.hosts.find(host => host.hostId === disabled._id).aiEnabled, false)
    assert('主机目录不暴露凭据字段', listed.data.hosts.every(host => !('password' in host) && !('privateKey' in host) && !('credential' in host)))
  }
  const matched = await hostList(ctx, { keyword: '生产' })
  expect('按名称定位目标', matched.data.hosts.map(host => host.hostId), [restricted._id])
  const byAddress = await hostList(ctx, { keyword: '10.0.0.1' })
  expect('按地址定位目标', byAddress.data.hosts.map(host => host.hostId), [open._id])
  expect('按分组定位目标', (await hostList(ctx, { keyword: '香港分组' })).data.hosts.map(host => host.hostId), [open._id])
  expect('没有匹配返回空列表', (await hostList(ctx, { keyword: '不存在的机器' })).data.total, 0)
  expect('仅查询目录不记录远端访问', ctx.usedHostIds.size, 0)

  expect('全局访问不依赖旧选择', (await resolveHostAccess(open._id, ctx, Effect.WRITE)).host._id, open._id)
  expect('跟踪实际通过访问校验的主机', [...ctx.usedHostIds], [open._id])
  const access = await resolveHostAccess(restricted._id, ctx, Effect.READ)
  expect('全局访问仍遵守主机模式上限', access.policy.mode, Mode.REVIEW)
  await expectReject('全局访问仍禁止受限主机写入', resolveHostAccess(restricted._id, ctx, Effect.WRITE), /仅允许/)
  await expectReject('全局访问仍禁止禁用 AI 主机', resolveHostAccess(disabled._id, ctx, Effect.READ), /禁止/)
  await expectReject('全局访问仍拒绝缺少主机 ID', resolveHostAccess('', ctx, Effect.READ), /缺少/)
  await expectReject('全局访问仍拒绝已删除主机', resolveHostAccess('deleted-host', ctx, Effect.READ), /未找到/)

  expect('全局助手可查询跨主机面板任务', (await scheduledTaskList(ctx, {})).data.tasks.map(task => task.taskId), [panelTask._id])
  expect('全局助手可查看面板任务', (await scheduledTaskGet(ctx, { taskId: panelTask._id })).data.id, panelTask._id)

  const terminalCtx = { ...ctx, scope: 'terminal', allowedHostIds: buildAllowedHostIds([open._id]) }
  expect('终端内置工具保持原范围', Object.keys(buildTools(terminalCtx)), ['read_output', 'terminal_command'])
  await expectReject('终端不能因全局范围改动访问其他主机', resolveHostAccess(restricted._id, terminalCtx, Effect.READ), /未授权/)
}

console.log('\n========== shell 转义 ==========')

{
  expect('普通路径加单引号', shellQuote('/var/log'), '\'/var/log\'')
  assert('命令替换被字面化', !wrapCommand('ls', { cwd: '/tmp/$(rm -rf /)' }).includes('$(rm -rf /)"'))

  const wrapped = wrapCommand('ls', { cwd: '/tmp/$(whoami)' })
  assert('cwd 用单引号包裹', wrapped.includes('cd \'/tmp/$(whoami)\''))
  assert('反引号同样被字面化', wrapCommand('ls', { cwd: '/tmp/`id`' }).includes('cd \'/tmp/`id`\''))

  // 路径里自带单引号不能把引号闭合掉
  const tricky = shellQuote('/tmp/it\'s; rm -rf /')
  expect('内嵌单引号被正确断开拼接', tricky, '\'/tmp/it\'\\\'\'s; rm -rf /\'')
  assert('转义后不存在裸的分号逃逸', !/^'[^']*';/.test(tricky))
}

console.log('\n========== 授权粒度 ==========')

{
  // 授权键必须区分主机
  const a = grantKey('exec_command', { hostId: 'h1', command: 'docker restart nginx' })
  const b = grantKey('exec_command', { hostId: 'h2', command: 'docker restart nginx' })
  assert('不同主机的授权互不通用', a !== b)

  // 授权必须包含完整操作对象
  const c = grantKey('exec_command', { hostId: 'h1', command: 'docker restart redis' })
  assert('不同容器不能共享授权', a !== c)

  // sudo 等包装不该绕过授权键
  const d = grantKey('exec_command', { hostId: 'h1', command: 'sudo docker restart nginx' })
  expect('包装命令归一到同一个键', a, d)

  // 文件破坏命令不提供会话级授权
  const rm = grantKey('exec_command', { hostId: 'h1', command: 'rm -rf /tmp/x' })
  expect('rm 不可生成会话授权键', rm, '')
  expect('复合命令不可生成会话授权键', grantKey('exec_command', {
    hostId: 'h1', command: 'docker restart nginx && docker restart redis'
  }), '')
  expect('动态命令不可生成会话授权键', grantKey('exec_command', {
    hostId: 'h1', command: 'docker restart $CONTAINER'
  }), '')
  assert('不同选项不能共享授权', grantKey('exec_command', {
    hostId: 'h1', command: 'docker restart --time 5 nginx'
  }) !== grantKey('exec_command', {
    hostId: 'h1', command: 'docker restart --time 10 nginx'
  }))

  // write_file 已强制逐次展示 diff，不应生成会话授权键
  const w1 = grantKey('write_file', { hostId: 'h1', path: '/etc/nginx/nginx.conf' })
  const w2 = grantKey('write_file', { hostId: 'h1', path: '/etc/shadow' })
  expect('普通文件写入不可会话授权', w1, '')
  expect('核心文件写入不可会话授权', w2, '')
}

console.log('\n========== Agent 执行上限 ==========')

{
  expect('未配置时使用默认迭代次数', normalizeMaxSteps(), DEFAULT_MAX_STEPS)
  expect('合法配置生效', normalizeMaxSteps(12), 12)
  expect('非法值回退默认值', normalizeMaxSteps('not-a-number'), DEFAULT_MAX_STEPS)
  expect('超大配置被服务端限幅', normalizeMaxSteps(MAX_MAX_STEPS + 1), MAX_MAX_STEPS)
  expect('文件写入声明为写操作', getToolSpec('write_file').effect, Effect.WRITE)
  expect('文件写入声明为 Plus 工具', getToolSpec('write_file').plusPolicy, PlusPolicy.REQUIRED)
  expect('命令工具按实际效果判定 Plus', getToolSpec('exec_command').plusPolicy, PlusPolicy.BY_EFFECT)
  expect('只读命令不需要 Plus', requiresPlus(getToolSpec('exec_command'), Effect.READ), false)
  expect('写入命令需要 Plus', requiresPlus(getToolSpec('exec_command'), Effect.WRITE), true)
  expect('敏感文件读取仍为免费能力', requiresPlus(getToolSpec('read_file'), Effect.READ), false)
  expect('定时任务变更不会被只读脚本降级', strongerEffect(Effect.WRITE, Effect.READ), Effect.WRITE)
  expect('定时任务变更保留删除脚本效果', strongerEffect(Effect.WRITE, Effect.DELETE), Effect.DELETE)
  expect('模型发现保留自定义 API 前缀', deriveBaseURL('https://example.com/api/v1/chat/completions'), 'https://example.com/api/v1')
}

console.log('\n========== Plus 工具权限 ==========')

{
  const events = []
  const ctx = { emit: (event) => events.push(event) }
  const readAccess = await checkRestrictedToolAccess(ctx, 'exec_command', Effect.READ, 'tool-read')
  expect('只读 Shell 不检查 Plus', readAccess.ok, true)
  expect('只读 Shell 不产生激活事件', events.length, 0)

  const writeAccess = await checkRestrictedToolAccess(ctx, 'exec_command', Effect.WRITE, 'tool-write')
  expect('未激活时写入 Shell 被拒绝', writeAccess.code, 'PLUS_REQUIRED')
  assert('拒绝事件包含工具和实际效果', events.some((event) => (
    event.type === 'tool_requires_plus'
      && event.tool === 'exec_command'
      && event.effect === Effect.WRITE
      && event.toolCallId === 'tool-write'
  )))

  const runtimeState = new RuntimeState().getInstance()
  runtimeState.setPlusKicked(true)
  events.length = 0
  const invalidAccess = await checkRestrictedToolAccess(
    ctx,
    'exec_command',
    Effect.WRITE,
    'tool-invalid-plus'
  )
  expect('已失效的 Plus 授权不误报成未激活', invalidAccess.code, 'PLUS_AUTH_INVALID')
  assert('授权失效时返回可恢复的工具拒绝', events.some((event) => (
    event.type === 'tool_denied'
      && event.toolCallId === 'tool-invalid-plus'
      && event.permanent === false
  )))
  assert('授权失效时不弹出重复激活提示', !events.some((event) => (
    event.type === 'tool_requires_plus'
  )))
  runtimeState.setPlusKicked(false)
}

console.log('\n========== 会话保留策略 ==========')

{
  const scheduleSource = fs.readFileSync(`${ originalCwd }/app/schedule/index.js`, 'utf8')
  assert('定时任务不再自动清理 Agent 会话', !scheduleSource.includes('pruneOlderThan'))
  const sessionStoreSource = fs.readFileSync(`${ originalCwd }/app/ai/session-store.js`, 'utf8')
  assert('会话存储不再保留按天数清理入口', !sessionStoreSource.includes('pruneOlderThan'))
}

console.log('\n========== 终端命令取消 ==========')

{
  const controller = new AbortController()
  const events = []
  const pending = requestTerminalDispatch({
    sessionId: 'terminal-cancel-test',
    hostId: 'h1',
    command: 'sleep 60',
    toolCallId: 'tool-cancel',
    emit: (event) => events.push(event),
    signal: controller.signal
  })
  const request = events.find((event) => event.type === 'terminal_command_request')
  assert('终端命令请求已发出', Boolean(request?.requestId))

  controller.abort()
  const result = await pending
  expect('取消后等待以失败结束', result.ok, false)
  assert('取消时通知终端中断命令', events.some((event) => event.type === 'terminal_command_cancel' && event.requestId === request.requestId))
}

console.log('\n========== high 不接受会话授权 ==========')

{
  const sessionId = 'sess-high'
  const events = []
  const emit = (event) => events.push(event)

  // 先用一个范围明确的服务操作拿到会话级授权
  const first = requestApproval({
    sessionId,
    toolName: 'exec_command',
    toolCallId: 'tool-restart',
    input: { hostId: 'h1', command: 'docker restart nginx' },
    riskLevel: 'normal',
    emit
  })
  const firstRequest = events.find((item) => item.type === 'approval_request')
  assert('普通操作可授予会话级', firstRequest.grantable === true)
  expect('审批事件关联工具调用', firstRequest.toolCallId, 'tool-restart')
  resolveApproval(firstRequest.requestId, { approved: true, scope: 'session' })
  expect('首次批准生效', (await first).approved, true)

  // 完全相同的操作应命中缓存，不再弹窗
  events.length = 0
  const cached = await requestApproval({
    sessionId,
    toolName: 'exec_command',
    input: { hostId: 'h1', command: 'docker restart nginx' },
    riskLevel: 'normal',
    emit
  })
  expect('同类操作命中会话授权', cached.cached, true)
  expect('命中缓存时不再弹窗', events.length, 0)

  // 同命令但不同对象不能复用
  events.length = 0
  const differentTarget = requestApproval({
    sessionId,
    toolName: 'exec_command',
    input: { hostId: 'h1', command: 'docker restart redis' },
    riskLevel: 'normal',
    emit
  })
  const differentRequest = events.find((item) => item.type === 'approval_request')
  assert('不同操作对象仍然弹窗', Boolean(differentRequest))
  resolveApproval(differentRequest.requestId, { approved: false })
  expect('不同对象可独立拒绝', (await differentTarget).approved, false)

  // 删除命令即使是 normal 也只能单次批准
  events.length = 0
  const destructive = requestApproval({
    sessionId,
    toolName: 'exec_command',
    input: { hostId: 'h1', command: 'rm /tmp/cache.txt' },
    riskLevel: 'normal',
    emit
  })
  const destructiveRequest = events.find((item) => item.type === 'approval_request')
  expect('rm 不提供会话级选项', destructiveRequest.grantable, false)
  resolveApproval(destructiveRequest.requestId, { approved: true, scope: 'session' })
  expect('rm 的 session 请求被降级为单次', (await destructive).scope, 'once')

  // 高危命令即便同键也必须重新确认
  events.length = 0
  const highPromise = requestApproval({
    sessionId,
    toolName: 'exec_command',
    input: { hostId: 'h1', command: 'docker restart nginx' },
    riskLevel: 'high',
    emit
  })
  const highRequest = events.find((item) => item.type === 'approval_request')
  assert('高危操作仍然弹窗（未被会话授权豁免）', Boolean(highRequest))
  expect('高危操作不提供会话级选项', highRequest.grantable, false)

  // 即便前端硬传 session，也只按单次处理
  resolveApproval(highRequest.requestId, { approved: true, scope: 'session' })
  const highResult = await highPromise
  expect('高危批准被降级为单次', highResult.scope, 'once')

  // 确认没有因此写入会话授权
  events.length = 0
  const again = requestApproval({
    sessionId,
    toolName: 'exec_command',
    input: { hostId: 'h1', command: 'docker restart nginx' },
    riskLevel: 'high',
    emit
  })
  assert('高危操作下次仍需确认', events.some((item) => item.type === 'approval_request'))
  const againRequest = events.find((item) => item.type === 'approval_request')
  resolveApproval(againRequest.requestId, { approved: false })
  expect('拒绝生效', (await again).approved, false)

  clearSession(sessionId)
}

console.log('\n========== MCP 工具会话授权 ==========')

{
  const sessionId = 'sess-mcp-grant'
  const events = []
  const toolInfo = {
    source: 'mcp',
    providerId: 'search-server',
    providerName: 'AnySearch',
    remoteName: 'batch_search',
    displayName: '批量搜索'
  }
  const first = requestApproval({
    sessionId,
    toolName: 'mcp_anysearch_batch_search',
    input: { queries: ['first'] },
    riskLevel: 'normal',
    toolInfo,
    emit: (event) => events.push(event)
  })
  const firstRequest = events.find((item) => item.type === 'approval_request')
  expect('MCP 工具提供会话授权选项', firstRequest.grantable, true)
  expect('MCP 授权按 Server 和原始工具名生成', firstRequest.grantKey, 'mcp:search-server:batch_search')
  resolveApproval(firstRequest.requestId, { approved: true, scope: 'session' })
  expect('MCP 首次会话授权生效', (await first).scope, 'session')

  events.length = 0
  const cached = await requestApproval({
    sessionId,
    toolName: 'mcp_anysearch_batch_search',
    input: { queries: ['different arguments'] },
    riskLevel: 'normal',
    toolInfo,
    emit: (event) => events.push(event)
  })
  expect('同一 MCP 工具更换参数仍命中会话授权', cached.cached, true)
  expect('MCP 会话授权命中后不再弹窗', events.length, 0)

  const otherTool = requestApproval({
    sessionId,
    toolName: 'mcp_anysearch_get_page',
    input: {},
    riskLevel: 'normal',
    toolInfo: { ...toolInfo, remoteName: 'get_page', displayName: '读取页面' },
    emit: (event) => events.push(event)
  })
  const otherRequest = events.find((item) => item.type === 'approval_request')
  assert('同一 Server 的其他 MCP 工具仍需确认', Boolean(otherRequest))
  resolveApproval(otherRequest.requestId, { approved: false })
  expect('其他 MCP 工具可以独立拒绝', (await otherTool).approved, false)

  clearSession(sessionId)
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
