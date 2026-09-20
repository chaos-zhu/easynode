/**
 * 脚本库访问层
 *
 * Web 接口与 AI 工具都从这里读取脚本，避免两边各自维护一份内置脚本
 * 或对 id / 分组的转换规则。这里仅负责读取；执行权限仍由各调用方控制。
 */

import { ScriptsDB } from '../utils/db-class.js'
import { getLayout, ORDER_DOMAIN, orderByIds } from './order-service.js'
import localShellJson from '../config/shell.json' with { type: 'json' }

const scriptsDB = new ScriptsDB().getInstance()

// 内置脚本的 ID 持久稳定，定时任务才能在面板重启后继续引用。
const builtinScripts = JSON.parse(JSON.stringify(localShellJson)).map((item) => ({
  ...item,
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
  const order = await getLayout(ORDER_DOMAIN.SCRIPTS)
  const ordered = order.sections.flatMap(section => orderByIds(scripts, section.itemIds))
  return [...ordered, ...builtinScripts]
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
