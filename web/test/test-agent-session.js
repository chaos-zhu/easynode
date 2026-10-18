import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { readFileSync } from 'node:fs'
import * as Vue from 'vue'
import * as messages from '../src/composables/agentMessages.js'

// 执行 composable 自身，只替换网络、存储和组件生命周期依赖。
const source = readFileSync(new URL('../src/composables/useAgentSession.js', import.meta.url), 'utf8')
  .replace(/^import\s[\s\S]*?from '[^']+'\n/gm, '')
  .replace('export function useAgentSession', 'function useAgentSession')

class Socket extends EventEmitter {
  sent = []
  emit(name, payload) {
    this.sent.push({ name, payload })
    return this
  }
  receive(name, payload) { return super.emit(name, payload) }
  close() { this.receive('disconnect') }
}

function harness(config = {}) {
  const socket = Vue.markRaw(new Socket())
  const effect = Vue.effectScope()
  const cleanups = []
  const history = {
    id: 'legacy-session', scope: config.scope || 'ops', hostId: config.hostId,
    hostIds: ['old-selection',], messages: [], modelId: 'fixture', permission: 'review'
  }
  const dependencies = {
    ...Vue,
    ...messages,
    onBeforeUnmount: fn => cleanups.push(fn),
    useStore: () => ({ aiConfig: { models: ['fixture',] } }),
    generateSocketInstance: () => socket,
    $api: {
      getAgentSessionDetail: async () => ({ data: history }),
      forkAgentSession: async () => ({ data: { ...history, id: 'fork' } }),
      getAgentSessions: async () => ({ data: [] })
    },
    localStorage: { getItem: () => null, setItem() {} },
    DEFAULT_PRESET: 'review'
  }
  const create = new Function(...Object.keys(dependencies), `${ source }; return useAgentSession`)(...Object.values(dependencies))
  const session = effect.run(() => create(config))
  session.connect()
  socket.receive('connect')
  return { session, socket, history, close() { cleanups.forEach(fn => fn()); effect.stop() } }
}

const global = harness()
try {
  global.session.send('解释 uptime 命令')
  let payload = global.socket.sent.find(item => item.name === 'ws_agent_run').payload
  assert.equal(payload.scope, 'ops')
  assert.ok(!Object.hasOwn(payload, 'hostIds'))
  assert.ok(!Object.hasOwn(global.session.settings, 'hostIds'))
  global.session.resetConversation()
  await global.session.loadSession('legacy-session')
  global.session.send('继续解释')
  payload = global.socket.sent.at(-1).payload
  assert.equal(payload.sessionId, 'legacy-session')
  assert.ok(!Object.hasOwn(payload, 'hostIds'))
  global.socket.receive('agent_event', { type: 'finish', finishReason: 'stop' })
  await global.session.forkSession(0)
  global.session.send('分支继续')
  assert.equal(global.socket.sent.at(-1).payload.sessionId, 'fork')
  assert.ok(!Object.hasOwn(global.socket.sent.at(-1).payload, 'hostIds'))
} finally {
  global.close()
}

const terminal = harness({ scope: 'terminal', hostId: 'current-host' })
try {
  const terminalContext = { output: 'snapshot', capturedAt: 1 }
  terminal.session.send('查看负载', { terminalContext })
  const payload = terminal.socket.sent.at(-1).payload
  assert.equal(payload.scope, 'terminal')
  assert.deepEqual(payload.hostIds, ['current-host',])
  assert.equal(payload.hostId, 'current-host')
  assert.equal(payload.terminalContext, terminalContext)
  assert.equal(payload.terminalPermission, 'review')
  terminal.session.resetConversation()
  terminal.history.hostId = 'other-host'
  await assert.rejects(() => terminal.session.loadSession('foreign-terminal'), /不属于当前/)
} finally {
  terminal.close()
}
console.log('全局助手发送、旧历史与分支恢复、终端请求协议回归通过')
