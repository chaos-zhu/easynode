const fs = require('fs-extra')
const path = require('path')
const CryptoJS = require('crypto-js')
require('dotenv').config()
console.log(process.env.PLUS_DECRYPT_KEY)

async function encryptPlusClearFiles(dir) {
  try {
    const files = await fs.readdir(dir)

    for (const file of files) {
      const fullPath = path.join(dir, file)
      const stat = await fs.stat(fullPath)

      if (stat.isDirectory()) {
        await encryptPlusClearFiles(fullPath)
      } else if (file === 'plus-clear.js') {
        const content = await fs.readFile(fullPath, 'utf-8')

        //  global.PLUS_DECRYPT_KEY
        const encryptedContent = CryptoJS.AES.encrypt(content, process.env.PLUS_DECRYPT_KEY).toString()

        const newPath = path.join(path.dirname(fullPath), 'plus.js')

        await fs.writeFile(newPath, encryptedContent)

        console.log(`已加密文件: ${fullPath}`)
        console.log(`生成加密文件: ${newPath}`)
      }
    }
  } catch (error) {
    console.error('加密过程出错:', error)
  }
}

const appDir = path.join(__dirname)
console.log(appDir)
// encryptPlusClearFiles(appDir)
//   .then(() => {
//     console.log('加密完成!')
//   })
//   .catch(error => {
//     console.error('程序执行出错:', error)
//   })