import path, { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ScriptGroupDB } from '../utils/db-class.js'
import decryptAndExecuteAsync from '../utils/decrypt-file.js'

const currentDir = dirname(fileURLToPath(import.meta.url))
const scriptGroupDB = new ScriptGroupDB().getInstance()

async function getScriptGroupList({ res }) {
  let data = await scriptGroupDB.findAsync({})
  data = data.map(item => ({ ...item, id: item._id }))
  data?.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  res.success({ data })
}

const addScriptGroup = async ({ res, request }) => {
  let { addScriptGroup } = (await decryptAndExecuteAsync(path.join(currentDir, 'plus.js'))) || {}
  if (addScriptGroup) {
    await addScriptGroup({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

const updateScriptGroup = async ({ res, request }) => {
  let { updateScriptGroup } = (await decryptAndExecuteAsync(path.join(currentDir, 'plus.js'))) || {}
  if (updateScriptGroup) {
    await updateScriptGroup({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

const removeScriptGroup = async ({ res, request }) => {
  let { removeScriptGroup } = (await decryptAndExecuteAsync(path.join(currentDir, 'plus.js'))) || {}
  if (removeScriptGroup) {
    await removeScriptGroup({ res, request })
  } else {
    return res.fail({ data: false, msg: 'Plus专属功能!' })
  }
}

export {
  addScriptGroup,
  getScriptGroupList,
  updateScriptGroup,
  removeScriptGroup
}
