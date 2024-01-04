const path = require('path')

module.exports = {
  httpPort: 8082,
  clientPort: 22022, // 勿更改
  uploadDir: path.join(process.cwd(),'app/static/upload'),
  staticDir: path.join(process.cwd(),'app/static'),
  sftpCacheDir: path.join(process.cwd(),'app/socket/sftp-cache'),
  sshRecordPath: path.join(process.cwd(),'app/storage/ssh-record.json'),
  keyPath: path.join(process.cwd(),'app/storage/key.json'),
  hostListPath: path.join(process.cwd(),'app/storage/host-list.json'),
  emailPath: path.join(process.cwd(),'app/storage/email.json'),
  notifyPath: path.join(process.cwd(),'app/storage/notify.json'),
  groupPath: path.join(process.cwd(),'app/storage/group.json'),
  apiPrefix: '/api/v1',
  logConfig: {
    outDir: path.join(process.cwd(),'./app/logs'),
    recordLog: false // 是否记录日志
  }
}
