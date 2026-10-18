export function generateSocketInstance() {
  const handlers = new Map()
  const socket = {
    id: 'onekey-test',
    connected: true,
    on(event, handler) {
      handlers.set(event, handler)
      return socket
    },
    receive(event, payload) {
      handlers.get(event)?.(payload)
    },
    emit(event) {
      if (event === 'ws_onekey') {
        socket.receive('ready')
        window.onekeyFixture.output('initial')
      }
    },
    disconnect() {
      socket.connected = false
      socket.receive('disconnect')
    }
  }
  window.onekeyFixture.socket = socket
  setTimeout(() => socket.receive('connect'), 0)
  return socket
}
