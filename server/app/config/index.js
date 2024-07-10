const path = require('path')

module.exports = {
  httpPort: 8082,
  clientPort: 22022, // 暂不支持更改
  uploadDir: path.join(process.cwd(),'app/db'),
  staticDir: path.join(process.cwd(),'app/static'),
  sftpCacheDir: path.join(process.cwd(),'app/socket/sftp-cache'),
  sshRecordDBPath: path.join(process.cwd(),'app/db/ssh-record.db'),
  keyDBPath: path.join(process.cwd(),'app/db/key.db'),
  hostListDBPath: path.join(process.cwd(),'app/db/host-list.db'),
  notifyConfDBPath: path.join(process.cwd(),'app/db/notify.db'),
  groupConfDBPath: path.join(process.cwd(),'app/db/group.db'),
  emailNotifyDBPath: path.join(process.cwd(),'app/db/email.db'),
  apiPrefix: '/api/v1',
  logConfig: {
    outDir: path.join(process.cwd(),'./app/logs'),
    recordLog: true // 是否记录日志
  }
}
