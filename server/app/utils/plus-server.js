const defaultPlusServers = [
  'https://easynode-auth1.chaoszhu.com',
  'https://easynode-auth2.chaoszhu.com'
]

const envPlusServers = process.env.PLUS_AUTH_SERVERS
  ?.split(',')
  .map(server => server.trim())
  .filter(Boolean)

const plusServers = envPlusServers?.length ? envPlusServers : defaultPlusServers

export { plusServers }
