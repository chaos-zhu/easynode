const { getLocalNetIP, readHostList, writeHostList, readKey, writeKey, randomStr, isProd } = require('./utils')
const NodeRSA = require('node-rsa')

async function initIp() {
  if(!isProd()) return console.log('非生产环境不初始化保存本地IP')
  const localNetIP = await getLocalNetIP()
  let vpsList = readHostList()
  if(vpsList.some(({ host }) => host === localNetIP)) return console.log('本机IP已储存: ', localNetIP)
  vpsList.unshift({ name: 'server-side-host', host: localNetIP })
  writeHostList(vpsList)
  console.log('首次启动储存本机IP: ', localNetIP)
}

async function initRsa() {
  let keyObj = readKey()
  if(keyObj.privateKey && keyObj.publicKey) return console.log('公私钥已存在')

  let key = new NodeRSA({ b: 1024 })
  key.setOptions({ encryptionScheme: 'pkcs1' })
  let privateKey = key.exportKey('pkcs1-private-pem')
  let publicKey = key.exportKey('pkcs8-public-pem')
  keyObj.privateKey = privateKey
  keyObj.publicKey = publicKey
  writeKey(keyObj)
  console.log('新的公私钥已生成')
}

function randomJWTSecret() {
  let keyObj = readKey()
  if(keyObj.jwtSecret) return console.log('jwt secret已存在')

  keyObj.jwtSecret = randomStr(32)
  writeKey(keyObj)
  console.log('已生成随机jwt secret')
}

module.exports = () => {
  initIp()
  initRsa()
  randomJWTSecret()
}
