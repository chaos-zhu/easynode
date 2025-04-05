const path = require('path')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const { AIConfigDB } = require('../utils/db-class')

const aiConfigDB = new AIConfigDB().getInstance()

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

module.exports = {
  getAIConfig,
  saveAIConfig,
  getAIModels
}
