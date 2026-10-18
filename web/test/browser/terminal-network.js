// Simulated terminal transport; Vue, Element Plus, xterm and its addons are real.
export const isDockerId = () => false
export const isDockerComposeYml = () => false
export function generateSocketInstance() {
  const listeners = new Map()
  const socket = {
    connected: false,
    sent: [],
    on(event, callback) {
      if (!listeners.has(event)) listeners.set(event, new Set())
      listeners.get(event).add(callback)
      return this
    },
    once(event, callback) {
      const wrapped = (...args) => { this.off(event, wrapped); callback(...args) }
      return this.on(event, wrapped)
    },
    off(event, callback) { listeners.get(event)?.delete(callback); return this },
    removeAllListeners() { listeners.clear(); return this },
    receive(event, ...args) { for (const callback of [...(listeners.get(event) || []),]) callback(...args) },
    connect() { queueMicrotask(() => { this.connected = true; this.receive('connect') }); return this },
    close() { this.connected = false; this.receive('disconnect', 'io client disconnect'); return this },
    emit(event, payload) {
      this.sent.push({ event, payload })
      if (event === 'ws_terminal') queueMicrotask(() => {
        this.receive('session_created', { sessionId: `session-${ payload.hostId }` })
        this.receive('terminal_connect_success')
        this.receive('output', `Connected to ${ payload.hostId }\r\nroot@${ payload.hostId }:~# `)
        this.receive('terminal_connect_shell_success')
      })
      if (event === 'suspend_terminal') queueMicrotask(() => this.receive('terminal_suspended', payload))
      return this
    }
  }
  window.terminalFixture.sockets.push(socket)
  return socket
}
