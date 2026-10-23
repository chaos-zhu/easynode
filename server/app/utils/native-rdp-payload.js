// Kept separate from the controller so authorization/type checks can be tested
// without opening the database, sockets, or encrypted Plus module.
export function nativeRdpPayload(hostId, connection, plusActive) {
  if (!plusActive) throw new Error('远程桌面为Plus功能')
  const { authInfo = {}, hostInfo = {}, name } = connection
  if (hostInfo.connectType !== 'rdp') throw new Error('not an RDP host')
  if (authInfo.authType !== 'password') throw new Error('RDP requires password authentication')
  const port = Number(authInfo.port)
  if (!authInfo.host || !authInfo.username || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('invalid RDP connection parameters')
  }
  return {
    hostId, name, host: authInfo.host, port, username: authInfo.username,
    authType: 'password', password: authInfo.password || ''
  }
}
