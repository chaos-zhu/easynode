import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { PRESETS, DEFAULT_PRESET, normalizeMode } from '../app/ai/policy.js'
const source = readFileSync(new URL('../app/socket/ai-agent.js', import.meta.url), 'utf8')
  .replace(/^import\s[\s\S]*?from '[^']+'\n/gm, '')
  .replace('export default (httpServer)', 'const setup = (httpServer)')
let connection
const handlers = new Map()
const emitted = []
const runs = []
const saved = []
const created = []
let currentScope = 'ops'
const noop = () => {}
const dependencies = {
  createSecureWs: () => ({ on: (_event, cb) => { connection = cb } }),
  parseCookies: () => ({}), getClientIP: () => 'fixture',
  RuntimeState: class { getInstance() { return { getDecryptKey: () => '', getPlusKicked: () => false } } },
  runTurn: async params => { runs.push(params); return { responseMessages: [] } },
  resolveApproval: noop, clearSession: noop, listPending: () => [], clearBySession: noop,
  disconnectHost: noop, PRESETS, DEFAULT_PRESET, normalizeMode,
  listConfiguredModels: async () => ({ models: [] }), listToolMetadata: async () => [],
  createSession: async input => { created.push(input); return { id: 'fixture', ...input } },
  getSession: async () => ({ id: 'fixture', scope: currentScope, hostId: 'host', permission: 'full_access' }),
  appendTurn: async (_id, patch) => { saved.push(patch); return { id: 'fixture', permission: patch.permission } },
  resolveTerminalDispatch: noop, reportTerminalDispatchProgress: noop, clearTerminalDispatchBySession: noop,
  claimSessionRun: () => true, releaseSessionRun: noop,
  logger: { info: noop, warn: noop, error: noop }
}
const setup = new Function(...Object.keys(dependencies), `${ source }; return setup`)(...Object.values(dependencies))
setup({})
connection({ id: 'fixture', disconnected: false, conn: { remoteAddress: '' }, handshake: { headers: {} },
  emit: (_name, payload) => emitted.push(payload), on: (name, fn) => handlers.set(name, fn) })

// Execute the real socket handler with network/model/storage dependencies replaced.
const invalidModes = ['', null, false, 0, 'invalid', 'review', [], {}]
for (const scope of ['ops', 'terminal']) {
  currentScope = scope
  for (const existing of [false, true]) {
    const base = {
      input: 'inspect', scope, ...(existing ? { sessionId: 'fixture' } : {}),
      ...(scope === 'terminal' ? {
        hostId: 'host', hostIds: ['host'], terminalContext: { output: '' }
      } : {})
    }
    const cases = [
      ...invalidModes.map(value => ({ fields: { permission: value }, expected: 'assist' })),
      ...['assist', 'authorized', 'full_access'].map(value => ({ fields: { permission: value }, expected: value })),
      { fields: {}, expected: existing ? 'full_access' : 'assist' }
    ]
    if (scope === 'terminal') {
      cases.push(
        ...invalidModes.map(value => ({
          fields: { terminalPermission: value, permission: 'full_access' }, expected: 'assist'
        })),
        { fields: { terminalPermission: 'full_access', permission: 'assist' }, expected: 'full_access' },
        { fields: { terminalPermission: 'authorized', permission: 'full_access' }, expected: 'authorized' }
      )
    }
    for (const { fields, expected } of cases) {
      const before = runs.length
      await handlers.get('ws_agent_run')({ ...base, ...fields })
      assert.equal(runs.length, before + 1, JSON.stringify(emitted))
      assert.equal(runs.at(-1).permission, expected)
      assert.equal(saved.at(-1).permission, expected)
      if (!existing) assert.equal(created.at(-1).permission, expected)
      if (scope === 'terminal') assert.equal(runs.at(-1).terminalPermission, expected)
    }
  }
}
assert.ok(!emitted.some(event => event.type === 'error'), JSON.stringify(emitted))
console.log(`Socket 模式新建、恢复、终端字段优先级与无效值回退通过（${ runs.length } 项）`)
