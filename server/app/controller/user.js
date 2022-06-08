const jwt = require('jsonwebtoken')
const { readKey, writeKey, decrypt } = require('../utils')

const getpublicKey = ({ res }) => {
  let { publicKey: data } = readKey()
  if(!data) return res.fail({ msg: 'publicKey not found, Try to restart the server', status: 500 })
  res.success({ data })
}

const login = async ({ res, request }) => {
  let { body: { ciphertext } } = request
  if(!ciphertext) return res.fail({ msg: '参数错误' })
  try {
    const password = decrypt(ciphertext)
    let { pwd, jwtSecret, jwtExpires } = readKey()
    if(password !== pwd) return res.fail({ msg: '密码错误' })
    const token = jwt.sign({ date: Date.now() }, jwtSecret, { expiresIn: jwtExpires }) // 生成token
    res.success({ data: { token, jwtExpires } })
  } catch (error) {
    res.fail({ msg: '解密失败' })
  }
}

const updatePwd = async ({ res, request }) => {
  let { body: { oldPwd, newPwd } } = request
  oldPwd = decrypt(oldPwd)
  newPwd = decrypt(newPwd)
  let keyObj = readKey()
  if(oldPwd !== keyObj.pwd) return res.fail({ data: false, msg: '旧密码校验失败' })
  keyObj.pwd = newPwd
  writeKey(keyObj)
  res.success({ data: true, msg: 'success' })
}

module.exports = {
  login,
  getpublicKey,
  updatePwd
}
