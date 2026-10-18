import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import { parse } from '@vue/compiler-sfc'
import { computed, ref } from 'vue'
import { createDefaultTerminalSettings } from '../src/utils/terminal-settings.js'

// 执行组件自身的 setup，替换浏览器和网络依赖，测试真实连接/命令入口。
const component = readFileSync(new URL('../src/views/terminal/components/terminal.vue', import.meta.url), 'utf8')
const { descriptor } = parse(component)
const setup = descriptor.scriptSetup.content.replace(/^import .+$/gm, '')

class FakeSocket extends EventEmitter {
  sent = []
  connected = false
  closed = false

  emit(event, ...args) {
    this.sent.push({ event, args })
    return this
  }

  receive(event, ...args) {
    if (event === 'connect') this.connected = true
    if (event === 'disconnect') this.connected = false
    return super.emit(event, ...args)
  }

  connect() {
    this.receive('connect')
  }

  close() {
    this.closed = true
    this.receive('disconnect', 'io client disconnect')
  }

  messages(event) {
    return this.sent.filter(message => message.event === event)
  }
}

function createHarness({ autoReconnect = true, resumeSessionId = null } = {}) {
  const settings = createDefaultTerminalSettings()
  settings.behavior.autoReconnect = autoReconnect
  const sockets = []
  const outputs = []
  const timers = new Map()
  const notifications = []
  let timerId = 0
  let unmount
  const context = {
    ref,
    computed,
    watch: () => {},
    onMounted: () => {},
    onBeforeUnmount: callback => { unmount = callback },
    nextTick: () => Promise.resolve(),
    getCurrentInstance: () => ({
      uid: 1,
      proxy: {
        $store: { effectiveTerminalSettings: settings, isPlusActive: true },
        $notification: payload => notifications.push(payload)
      }
    }),
    useMobileWidth: () => ({ isMobileScreen: { value: false } }),
    useContextMenu: () => ({ isVisible: { value: false } }),
    defineProps: () => ({ hostObj: { id: 'host', key: 'tab', resumeSessionId } }),
    defineEmits: () => () => {},
    defineExpose: () => {},
    terminalStatus: { CONNECTING: 0, CONNECT_SUCCESS: 1, CONNECT_FAIL: 2, SUSPENDED: 3 },
    generateSocketInstance: (path, options) => {
      const socket = new FakeSocket()
      socket.options = options
      sockets.push(socket)
      return socket
    },
    setTimeout: callback => {
      timers.set(++timerId, callback)
      return timerId
    },
    clearTimeout: id => timers.delete(id),
    window: { removeEventListener: () => {} },
    console: { log: () => {}, warn: () => {}, error: () => {} }
  }
  const terminal = runInNewContext(`${ setup }\nglobalThis.terminalHarness = { connectIO, reconnectTerminal, inputCommand, term, initCommand, curStatus, socket }`, context)
  terminal.term.value = { rows: 40, cols: 120, write: output => outputs.push(output), dispose: () => {} }
  return {
    terminal,
    sockets,
    outputs,
    timers,
    notifications,
    unmount: () => unmount(),
    flushTimers: () => {
      const callbacks = [...timers.values(),]
      timers.clear()
      callbacks.forEach(callback => callback())
    }
  }
}

const command = 'docker compose -f /root/pansou/docker-compose.yml pull && docker compose -f /root/pansou/docker-compose.yml down && docker compose -f /root/pansou/docker-compose.yml up -d\n'

const harness = createHarness()
harness.terminal.initCommand.value = 'echo init'
harness.terminal.connectIO()
let socket = harness.sockets[0]
assert.equal(socket.messages('ws_terminal').length, 1, '同步 connect 时创建请求不丢失')
socket.receive('connect')
assert.equal(socket.messages('ws_terminal').length, 1, '重复 connect 不得创建多个 SSH shell')
assert.equal(socket.messages('ws_terminal')[0].args[0].rows, 40)
harness.terminal.inputCommand(command, 'script')
assert.equal(socket.messages('input').length, 0, 'shell 未就绪时不得排队发送 SFTP 命令')

for (let i = 0; i < 3; i++) socket.receive('terminal_connect_success')
socket.receive('output', 'Linux banner\r\n')
assert.equal(harness.outputs.filter(output => output === 'Linux banner\r\n').length, 1, '重复成功事件不得重复显示输出')
for (let i = 0; i < 3; i++) socket.receive('terminal_connect_shell_success')
assert.equal(socket.messages('input').length, 1, '初始化命令只执行一次')
harness.terminal.inputCommand(command, 'script')
assert.equal(socket.messages('input').length, 2, '一次 SFTP 操作只发送一次命令')

for (let i = 0; i < 3; i++) {
  const previous = socket
  const staleOutput = previous.listeners('output')[0]
  const staleConnect = previous.listeners('connect')[0]
  previous.receive('disconnect', 'transport close')
  socket = harness.sockets.at(-1)
  assert.notEqual(socket, previous)
  assert.equal(previous.closed, true)
  assert.equal(previous.eventNames().length, 0, '重连清理旧连接全部监听器')
  staleOutput('stale output')
  staleConnect?.()
  assert.equal(harness.outputs.includes('stale output'), false, '忽略已关闭连接的回调')
  assert.equal(socket.messages('ws_terminal').length, 1)
  socket.receive('terminal_connect_success')
  socket.receive('terminal_connect_success')
  socket.receive('terminal_connect_shell_success')
  socket.receive('terminal_connect_shell_success')
  harness.terminal.inputCommand(command, 'script')
  assert.equal(socket.messages('input').length, 2, '多次重连后初始化和 SFTP 命令各发送一次')
}
socket.connected = false
harness.terminal.inputCommand(command, 'script')
assert.equal(socket.messages('input').length, 2, '断线命令不得进入发送缓冲区')
harness.unmount()
assert.equal(socket.closed, true)
const socketCount = harness.sockets.length
harness.terminal.connectIO()
assert.equal(harness.sockets.length, socketCount, '组件关闭后不得重建连接')

const manual = createHarness({ autoReconnect: false })
manual.terminal.connectIO()
manual.sockets[0].receive('disconnect', 'transport close')
assert.equal(manual.sockets.length, 1)
assert.equal(manual.terminal.curStatus.value, 2, '关闭自动重连时进入可手动重连的失败状态')
assert.equal(manual.terminal.socket.value, null)
manual.terminal.reconnectTerminal(false, '手动重连')
assert.equal(manual.sockets.length, 2, '空 socket 也能手动重连')
manual.unmount()

const resumed = createHarness({ resumeSessionId: 'session' })
resumed.terminal.initCommand.value = 'echo init'
resumed.terminal.connectIO()
const resumedSocket = resumed.sockets[0]
assert.equal(resumedSocket.messages('ws_terminal')[0].args[0].resumeSessionId, 'session')
const resumePayload = { sessionId: 'session', bufferedOutput: 'buffered output' }
resumedSocket.receive('terminal_resumed', resumePayload)
resumedSocket.receive('terminal_resumed', resumePayload)
// 服务端恢复后仍会发送会话信息、SSH 就绪和 shell 就绪事件。
resumedSocket.receive('session_created', { sessionId: 'session' })
resumedSocket.receive('terminal_connect_success')
resumedSocket.receive('terminal_connect_shell_success')
resumedSocket.receive('terminal_connect_shell_success')
assert.equal(resumed.terminal.curStatus.value, 1, '恢复后终端保持就绪')
assert.equal(resumedSocket.messages('input').length, 0, '恢复已有 shell 不得再次执行初始化命令')
assert.equal(resumed.outputs.filter(output => output === 'buffered output').length, 1)
resumed.flushTimers()
assert.equal(resumedSocket.messages('input').length, 1, '恢复提示符回车只发送一次')
assert.equal(resumedSocket.messages('input')[0].args[0], '\r')

// 下一次连接若恢复失败而回退到新建 shell，仍需正常执行初始化命令。
resumed.terminal.reconnectTerminal(false, '重新连接中...')
const fallbackSocket = resumed.sockets.at(-1)
fallbackSocket.receive('terminal_resume_failed', '原会话不存在或已过期')
fallbackSocket.receive('terminal_connect_success')
fallbackSocket.receive('terminal_connect_shell_success')
fallbackSocket.receive('session_created', { sessionId: 'new-session' })
fallbackSocket.receive('terminal_connect_shell_success')
assert.equal(fallbackSocket.messages('input').length, 1, '恢复失败后新建 shell 的初始化命令只执行一次')
assert.equal(fallbackSocket.messages('input')[0].args[0], 'echo init\n')
assert.equal(resumed.notifications.length, 1, '恢复失败时明确提示用户正在新建终端')
assert.match(resumed.outputs.join(''), /正在重新创建终端/)
resumed.terminal.reconnectTerminal(false, '重新连接中...')
assert.equal(resumed.sockets.at(-1).messages('ws_terminal')[0].args[0].forceNew, true, '回退后不再反复请求失效会话')
assert.equal(resumed.sockets.at(-1).messages('ws_terminal')[0].args[0].resumeSessionId, undefined)
resumed.unmount()

const interruptedResume = createHarness({ resumeSessionId: 'session' })
interruptedResume.terminal.connectIO()
interruptedResume.sockets[0].receive('terminal_resumed', resumePayload)
interruptedResume.sockets[0].receive('disconnect', 'transport close')
interruptedResume.flushTimers()
assert.equal(interruptedResume.sockets[1].messages('input').length, 0, '旧恢复回车不能进入新 shell')
interruptedResume.unmount()
assert.equal(interruptedResume.timers.size, 0)

console.log('Web 终端连接与 SFTP 命令回归测试通过')
