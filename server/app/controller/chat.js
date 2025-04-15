const path = require('path')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const { AIConfigDB, ChatHistoryDB } = require('../utils/db-class')

const aiConfigDB = new AIConfigDB().getInstance()
const chatHistoryDB = new ChatHistoryDB().getInstance()

async function getAIConfig({ res }) {
  try {
    const config = await aiConfigDB.findOneAsync({})
    if (!config) {
      return res.success({ data: {} })
    }
    res.success({ data: config })
  } catch (error) {
    res.fail({ msg: '获取配置失败' })
  }
}

async function getAIModels({ res, request }) {
  let { getAIModels } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (getAIModels) {
    await getAIModels({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

async function saveAIConfig({ res, request }) {
  let { saveAIConfig } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (saveAIConfig) {
    await saveAIConfig({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

async function getChatHistory({ res }) {
  const chatHistory = await chatHistoryDB.findAsync({})
  chatHistory.sort((a, b) => b.createdAt - a.createdAt)
  res.success({ data: chatHistory || [] })
}

async function saveChatHistory({ res, request }) {
  const chatRecord = request.body
  const { id, _id } = chatRecord
  if (!id) return res.fail({ data: false, msg: '参数错误' })

  if (!_id) {
    console.log('不存在-创建')
    chatRecord.createdAt = Date.now()
    await chatHistoryDB.insertAsync(chatRecord)
  } else {
    console.log('存在-更新')
    chatRecord.updatedAt = Date.now()
    await chatHistoryDB.updateAsync({ _id }, chatRecord)
  }
  res.success({ data: true })
}

async function removeChatHistory({ res, request }) {
  let { params: { id } } = request
  if (!id) return res.fail({ data: false, msg: '参数错误' })
  await chatHistoryDB.removeAsync({ _id: id })
  res.success({ data: true })
}

module.exports = {
  getAIConfig,
  saveAIConfig,
  getAIModels,
  getChatHistory,
  saveChatHistory,
  removeChatHistory
}
