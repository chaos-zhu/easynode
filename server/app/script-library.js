/**
 * 脚本库访问层
 *
 * Web 接口与 AI 工具都从这里读取脚本，避免两边各自维护一份内置脚本
 * 或对 id / 分组的转换规则。这里仅负责读取；执行权限仍由各调用方控制。
 */

import { randomStr } from './utils/tools.js'
import { ScriptsDB } from './utils/db-class.js'
import localShellJson from './config/shell.json' with { type: 'json' }

const scriptsDB = new ScriptsDB().getInstance()

// 内置脚本没有数据库 _id，启动时生成稳定于本进程生命周期的可引用 id。
const builtinScripts = JSON.parse(JSON.stringify(localShellJson)).map((item) => ({
  ...item,
  id: randomStr(10),
  index: '--',
  description: item.description,
  group: 'builtin',
  builtin: true
}))

function normalizeStoredScript(item) {
  return {
    ...item,
    id: item._id,
    group: item.group || 'default',
    builtin: false
  }
}

export async function listScripts() {
  const scripts = (await scriptsDB.findAsync({})).map(normalizeStoredScript)
  scripts.sort((a, b) => Number(b.index || 0) - Number(a.index || 0))
  return [...scripts, ...builtinScripts]
}

export function listBuiltinScripts() {
  return builtinScripts
}

export async function getScriptById(id) {
  const builtin = builtinScripts.find((item) => item.id === id)
  if (builtin) return builtin

  const stored = await scriptsDB.findOneAsync({ _id: id })
  return stored ? normalizeStoredScript(stored) : null
}
