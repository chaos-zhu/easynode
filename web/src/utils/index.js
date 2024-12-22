import { reactive } from 'vue'
import JSRsaEncrypt from 'jsencrypt'
import CryptoJS from 'crypto-js'

export const EventBus = reactive({})

EventBus.$emit = (event, data) => {
  if (EventBus[event]) {
    EventBus[event].forEach(callback => callback(data))
  }
}

EventBus.$on = (event, callback) => {
  if (!EventBus[event]) {
    EventBus[event] = []
  }
  EventBus[event].push(callback)
}

export const randomStr = (e) =>{
  e = e || 16
  let str = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678',
    a = str.length,
    res = ''
  for (let i = 0; i < e; i++) res += str.charAt(Math.floor(Math.random() * a))
  return res
}

// rsa公钥加密
export const RSAEncrypt = (text) => {
  const publicKey = localStorage.getItem('publicKey')
  if (!publicKey) return -1 // 公钥不存在
  const RSAPubEncrypt = new JSRsaEncrypt() // 生成实例
  RSAPubEncrypt.setPublicKey(publicKey) // 配置公钥(不是将公钥实例化时传入!!!)
  const ciphertext = RSAPubEncrypt.encrypt(text) // 加密
  // console.log('rsa公钥加密：', ciphertext)
  return ciphertext
}

// aes加密
export const AESEncrypt = (text, secretKey) => {
  let ciphertext = CryptoJS.AES.encrypt(text, secretKey).toString()
  return ciphertext
}

// aes解密
export const AESDecrypt = (ciphertext, secretKey) => {
  let bytes = CryptoJS.AES.decrypt(ciphertext, secretKey)
  let originalText = bytes.toString(CryptoJS.enc.Utf8)
  return originalText
}

export const sortString = (arr = []) => {
  return arr.sort((a, b) => {
    let c1 = ''
    let c2 = ''
    let temp = a.length > b.length ? b : a
    for (let i = 0; i < temp.length; i++) {
      c1 = a[i].toLowerCase()
      c2 = b[i].toLowerCase()
      if (c1 !== c2) break
    }
    return c1.charCodeAt() - c2.charCodeAt()
  })
}

export const dirType = ['d', 'l',] // 文件夹或者链接文件夹

export const fileType = ['-',] // 文本文件或者二进制文件

export const isDir = (type) => dirType.includes(type)

export const isFile = (type) => fileType.includes(type)

export const sortDirTree = (tree = []) => {
  const dirsAndlinks = tree.filter(item => isDir(item.type))
  const others = tree.filter(item => !(isDir(item.type)))
  const sort = (arr = []) => {
    return arr.sort((a, b) => {
      const { name: aName } = a
      const { name: bName } = b
      let c1 = ''
      let c2 = ''
      let temp = aName.length > bName.length ? bName : aName
      for (let i = 0; i < temp.length; i++) {
        c1 = aName[i].toLowerCase()
        c2 = bName[i].toLowerCase()
        if (c1 !== c2) break
      }
      return c1.charCodeAt() - c2.charCodeAt()
    })
  }
  sort(dirsAndlinks)
  sort(others)
  let res = [].concat(dirsAndlinks, others)
  let homeDirIndex = res.findIndex(item => item.name === 'home')
  if (homeDirIndex !== -1) {
    let homeDir = res[homeDirIndex]
    res.splice(homeDirIndex, 1)
    res.unshift(homeDir)
  }
  let rootDirIndex = res.findIndex(item => item.name === 'root')
  if (rootDirIndex !== -1) {
    let rootDir = res[rootDirIndex]
    res.splice(rootDirIndex, 1)
    res.unshift(rootDir)
  }
  return res
}

export const downloadFile = ({ buffer, name }) => {
  let contentUrl = window.URL.createObjectURL(new Blob([buffer,])) // params：object 可选: File对象、Blob对象、MediaSource对象。
  let link = document.createElement('a')
  link.style.display = 'none'
  link.href = contentUrl
  console.log(name)
  link.setAttribute('download', name) // 文件名称
  document.body.appendChild(link)
  link.click()
  setTimeout(() => {
    document.body.removeChild(link)
    window.URL.revokeObjectURL(contentUrl)
  })
}

export const getSuffix = (name = '') => {
  return String(name).split(/\./).pop()
}

export const exportFile = (data, filename, mimeType = 'application/json') =>{
  const blob = new Blob([JSON.stringify(data, null, 2),], { type: mimeType })
  const url = window.URL.createObjectURL(blob)

  const link = document.createElement('a')
  link.href = url
  link.setAttribute('download', filename)

  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  window.URL.revokeObjectURL(url)
}

export const isHttps = () => {
  return window.location.protocol === 'https:'
}

export const isMobile = () => {
  let userAgent = navigator.userAgent || navigator.vendor || window.opera
  return /android|webos|iphone|ipad|ipod|blackberry|iemobile|opera mini/i.test(userAgent)
}

export const handlePlusSupport = () => {
  window.open('https://en.221022.xyz/buy-plus', '_blank')
}
