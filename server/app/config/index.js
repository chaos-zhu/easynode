const path = require('path')

consola.info('debug日志：', process.env.DEBUG === '1' ? '开启' : '关闭')

module.exports = {
  httpPort: 8082,
  uploadDir: path.join(process.cwd(),'app/db'),
  staticDir: path.join(process.cwd(),'app/static'),
  sftpCacheDir: path.join(process.cwd(),'app/socket/sftp-cache'),
  credentialsDBPath: path.join(process.cwd(),'app/db/credentials.db'),
  keyDBPath: path.join(process.cwd(),'app/db/key.db'),
  hostListDBPath: path.join(process.cwd(),'app/db/host.db'),
  groupConfDBPath: path.join(process.cwd(),'app/db/group.db'),
  scriptsDBPath: path.join(process.cwd(),'app/db/scripts.db'),
  scriptGroupDBPath: path.join(process.cwd(),'app/db/script-group.db'),
  notifyDBPath: path.join(process.cwd(),'app/db/notify.db'),
  notifyConfigDBPath: path.join(process.cwd(),'app/db/notify-config.db'),
  onekeyDBPath: path.join(process.cwd(),'app/db/onekey.db'),
  logDBPath: path.join(process.cwd(),'app/db/log.db'),
  plusDBPath: path.join(process.cwd(),'app/db/plus.db'),
  aiConfigDBPath: path.join(process.cwd(),'app/db/ai-config.db'),
  chatHistoryDBPath: path.join(process.cwd(),'app/db/chat-history.db'),
  favoriteSftpDBPath: path.join(process.cwd(),'app/db/favorite-sftp.db'),
  proxyDBPath: path.join(process.cwd(),'app/db/proxy.db'),
  fileTransferDBPath: path.join(process.cwd(),'app/db/file-transfer.db'),
  terminalConfigDBPath: path.join(process.cwd(),'app/db/terminal-config.db'),
  serverListDBPath: path.join(process.cwd(),'app/db/server-list-config.db'),
  apiPrefix: '/api/v1',
  logConfig: {
    outDir: path.join(process.cwd(),'./app/db/logs'),
    recordLog: process.env.DEBUG === '1' // 是否记录日志
  }
}
