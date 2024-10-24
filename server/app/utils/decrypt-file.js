const fs = require('fs-extra')
const path = require('path')
const CryptoJS = require('crypto-js')
const { AESDecryptAsync } = require('./encrypt')
const { PlusDB } = require('./db-class')
const plusDB = new PlusDB().getInstance()

function decryptAndExecuteAsync(plusPath) {
  return new Promise(async (resolve) => {
    try {
      let { decryptKey } = await plusDB.findOneAsync({})
      if (!decryptKey) {
        throw new Error('缺少解密密钥')
      }
      decryptKey = await AESDecryptAsync(decryptKey)
      const encryptedContent = fs.readFileSync(plusPath, 'utf-8')
      const bytes = CryptoJS.AES.decrypt(encryptedContent, decryptKey)
      const decryptedContent = bytes.toString(CryptoJS.enc.Utf8)
      if (!decryptedContent) {
        throw new Error('解密失败,请检查密钥是否正确')
      }
      const customRequire = (modulePath) => {
        if (modulePath.startsWith('.')) {
          const absolutePath = path.resolve(path.dirname(plusPath), modulePath)
          return require(absolutePath)
        }
        return require(modulePath)
      }
      const module = {
        exports: {},
        require: customRequire,
        __filename: plusPath,
        __dirname: path.dirname(plusPath)
      }
      const wrapper = Function('module', 'exports', 'require', '__filename', '__dirname',
        decryptedContent + '\n return module.exports;'
      )
      const exports = wrapper(
        module,
        module.exports,
        customRequire,
        module.__filename,
        module.__dirname
      )
      resolve(exports)
    } catch (error) {
      consola.info('解锁plus功能失败: ', error.message)
      resolve(null)
    }
  })
}

module.exports = decryptAndExecuteAsync
