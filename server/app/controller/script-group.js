const path = require('path')
const { ScriptGroupDB } = require('../utils/db-class')
const decryptAndExecuteAsync = require('../utils/decrypt-file')
const scriptGroupDB = new ScriptGroupDB().getInstance()

async function getScriptGroupList({ res }) {
  let data = await scriptGroupDB.findAsync({})
  data = data.map(item => ({ ...item, id: item._id }))
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  res.success({ data })
}

const addScriptGroup = async ({ res, request }) => {
  let { addScriptGroup } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (addScriptGroup) {
    await addScriptGroup({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

const updateScriptGroup = async ({ res, request }) => {
  let { updateScriptGroup } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (updateScriptGroup) {
    await updateScriptGroup({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

const removeScriptGroup = async ({ res, request }) => {
  let { removeScriptGroup } = (await decryptAndExecuteAsync(path.join(__dirname, 'plus.js'))) || {}
  if (removeScriptGroup) {
    await removeScriptGroup({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

module.exports = {
  addScriptGroup,
  getScriptGroupList,
  updateScriptGroup,
  removeScriptGroup
}