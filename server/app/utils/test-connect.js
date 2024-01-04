// based off of https://github.com/apaszke/tcp-ping
// rewritten with modern es6 syntax & promises
const { io: ClientIO } = require('socket.io-client')

const testConnectAsync = (options) => {
  let connectTimes = 0
  options = Object.assign({ retryTimes: 3, timeout: 5000, host: 'http://localhost', port: '80' }, options)
  const { retryTimes, host, port, timeout } = options
  // eslint-disable-next-line
  return new Promise(async (resolve, reject) => {
    while (connectTimes < retryTimes) {
      try {
        connectTimes++
        await connect({ host, port, timeout })
        break
      } catch (error) {
        // 重连次数达到限制仍未连接成功
        if(connectTimes === retryTimes) {
          reject({ message: error.message, host, port, connectTimes })
          return
        }
      }
    }
    resolve({ status: 'connect_success', host, port, connectTimes })
  })
}

const connect = (options) => {
  const { host, port, timeout } = options
  return new Promise((resolve, reject) => {
    let io = ClientIO(`${ host }:${ port }`, {
      path: '/client/os-info',
      forceNew: false,
      timeout,
      reconnection: false
    })
      .on('connect', () => {
        resolve()
        io.disconnect()
      })
      .on('connect_error', (error) => {
        reject(error)
      })
  })
}

module.exports = testConnectAsync