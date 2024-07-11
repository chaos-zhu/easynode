const CryptoJS = require('crypto-js')
const rawCrypto = require('crypto')
const NodeRSA = require('node-rsa')
const { readKey } = require('./storage.js')

// rsa非对称 私钥解密
const RSADecryptSync = async (ciphertext) => {
  if (!ciphertext) return
  let { privateKey } = await readKey()
  privateKey = await AESDecryptSync(privateKey) // 先解密私钥
  const rsakey = new NodeRSA(privateKey)
  rsakey.setOptions({ encryptionScheme: 'pkcs1', environment: "browser" }) // Must Set It When Frontend Use jsencrypt
  const plaintext = rsakey.decrypt(ciphertext, 'utf8')
  return plaintext
}

// aes对称 加密(default commonKey)
const AESEncryptSync = async (text, key) => {
  if(!text) return
  let { commonKey } = await readKey()
  let ciphertext = CryptoJS.AES.encrypt(text, key || commonKey).toString()
  return ciphertext
}

// aes对称 解密(default commonKey)
const AESDecryptSync = async (ciphertext, key) => {
  if(!ciphertext) return
  let { commonKey } = await readKey()
  let bytes = CryptoJS.AES.decrypt(ciphertext, key || commonKey)
  let originalText = bytes.toString(CryptoJS.enc.Utf8)
  return originalText
}

// sha1 加密(不可逆)
const SHA1Encrypt = (clearText) => {
  return rawCrypto.createHash('sha1').update(clearText).digest('hex')
}

module.exports = {
  RSADecryptSync,
  AESEncryptSync,
  AESDecryptSync,
  SHA1Encrypt
}