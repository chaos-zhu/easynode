const {
  readSupportEmailList,
  readUserEmailList,
  writeUserEmailList,
  emailTransporter,
  readNotifyList,
  writeNotifyList } = require('../utils')
const commonTemp = require('../template/commonTemp')

async function getSupportEmailList({ res }) {
  const data = await readSupportEmailList()
  res.success({ data })
}

async function getUserEmailList({ res }) {
  const userEmailList = (await readUserEmailList()).map(({ target, auth: { user } }) => ({ target, user }))
  const supportEmailList = await readSupportEmailList()
  const data = userEmailList.map(({ target: userTarget, user: email }) => {
    let name = supportEmailList.find(({ target: supportTarget }) => supportTarget === userTarget).name
    return { name, email }
  })
  res.success({ data })
}

async function pushEmail({ res, request }) {
  let { body: { toEmail, isTest } } = request
  if (!isTest) return res.fail({ msg: '此接口暂时只做测试邮件使用, 需传递参数isTest: true' })
  consola.info('发送测试邮件：', toEmail)
  let { code, msg } = await emailTransporter({ toEmail, title: '测试邮件', html: commonTemp('邮件通知测试邮件') })
  msg = msg && msg.message || msg
  if (code === 0) return res.success({ msg })
  return res.fail({ msg })
}

async function updateUserEmailList({ res, request }) {
  let { body: { target, auth } } = request
  const supportList = await readSupportEmailList()
  let flag = supportList.some((item) => item.target === target)
  if (!flag) return res.fail({ msg: `不支持的邮箱类型：${ target }` })
  if (!auth.user || !auth.pass) return res.fail({ msg: 'missing params: auth.' })

  let newUserEmail = { target, auth }
  let userEmailList = await readUserEmailList()
  let idx = userEmailList.findIndex(({ auth: { user } }) => auth.user === user)
  if (idx !== -1) userEmailList.splice(idx, 1, newUserEmail)
  else userEmailList.unshift(newUserEmail)

  const { code, msg } = await writeUserEmailList(userEmailList)
  if (code === 0) return res.success()
  return res.fail({ msg })
}

async function removeUserEmail({ res, request }) {
  let { params: { email } } = request
  const userEmailList = await readUserEmailList()
  let idx = userEmailList.findIndex(({ auth: { user } }) => user === email)
  if (idx === -1) return res.fail({ msg: `删除失败, 不存在该邮箱：${ email }` })
  userEmailList.splice(idx, 1)
  const { code, msg } = await writeUserEmailList(userEmailList)
  if (code === 0) return res.success()
  return res.fail({ msg })
}

async function getNotifyList({ res }) {
  const data = await readNotifyList()
  res.success({ data })
}

async function updateNotifyList({ res, request }) {
  let { body: { type, sw } } = request
  if (!([true, false].includes(sw))) return res.fail({ msg: `Error type for sw：${ sw }, must be Boolean` })
  const notifyList = await readNotifyList()
  let target = notifyList.find((item) => item.type === type)
  if (!target) return res.fail({ msg: `更新失败, 不存在该通知类型：${ type }` })
  target.sw = sw
  // console.log(notifyList)
  await writeNotifyList(notifyList)
  res.success()
}

module.exports = {
  pushEmail,
  getSupportEmailList,
  getUserEmailList,
  updateUserEmailList,
  removeUserEmail,
  getNotifyList,
  updateNotifyList
}
