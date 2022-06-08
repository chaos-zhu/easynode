const path = require('path')
const fs = require('fs')

const getCertificate =() => {
  try {
    return {
      cert: fs.readFileSync(path.join(__dirname, './pem/cert.pem')),
      key: fs.readFileSync(path.join(__dirname, './pem/key.pem'))
    }
  } catch (error) {
    return null
  }
}
module.exports = {
  domain: 'yourDomain', // 域名xxx.com
  httpPort: 8082,
  httpsPort: 8083,
  clientPort: 22022, // 勿更改
  certificate: getCertificate(),
  uploadDir: path.join(process.cwd(),'./app/static/upload'),
  staticDir: path.join(process.cwd(),'./app/static'),
  sshRecordPath: path.join(__dirname,'./storage/ssh-record.json'),
  keyPath: path.join(__dirname,'./storage/key.json'),
  hostListPath: path.join(__dirname,'./storage/host-list.json'),
  apiPrefix: '/api/v1',
  logConfig: {
    outDir: path.join(process.cwd(),'./app/logs'),
    flag: false // 是否记录日志
  }
}
