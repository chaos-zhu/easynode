/** Panel-only mutations. Preparation is read-only; execution consumes its exact snapshot. */
import { resolvePanelHostAccess } from '../ai/host-access.js'
import { Effect, Risk, strongerEffect } from '../ai/policy.js'
import { classifyCommand, primaryReason } from '../ai/safety.js'
import { writeAudit, ACTION } from '../ai/audit.js'
import { buildFullReplacementDiff } from '../ai/write-preview.js'
import { createHash } from 'node:crypto'
import { PANEL_BATCH_SCHEMAS } from '../ai/tools/panel-schema.js'
export { PANEL_BATCH_SCHEMAS } from '../ai/tools/panel-schema.js'
import { HostListDB, GroupDB, ScriptsDB, ScriptGroupDB, ScheduledTaskDB } from '../utils/db-class.js'
import { getScriptById } from './script-library.js'
import { addItemsToOrder, addGroupToOrder, moveItemsToGroup, removeItemsFromOrder, getLayout, ORDER_DOMAIN } from './order-service.js'
import { disableScheduledTasksForScripts } from './scheduled-task-service.js'

const hostsDB = new HostListDB().getInstance()
const groupsDB = new GroupDB().getInstance()
const scriptsDB = new ScriptsDB().getInstance()
const scriptGroupsDB = new ScriptGroupDB().getInstance()
const tasksDB = new ScheduledTaskDB().getInstance()

export async function scriptReferences(scriptId) {
  const tasks = await tasksDB.findAsync({ 'script.type': 'library', 'script.scriptId': scriptId })
  return tasks.map(task => ({ taskId: task._id, name: task.name, enabled: task.enabled === true,
    hostIds: [...new Set(task.hostIds || [])].sort() }))
    .sort((a, b) => a.taskId.localeCompare(b.taskId))
}

async function prepareScheduledExecution(before, after, affectedTasks) {
  if (!before || !after || !affectedTasks.length ||
    (before.command === after.command && before.useBase64 === after.useBase64)) return null

  // Referencing tasks (including manually runnable disabled tasks) consume the
  // new content. Bind their targets and AI policies to this approval snapshot.
  const verdict = classifyCommand(after.command)
  const hostIds = [...new Set(affectedTasks.flatMap(task => task.hostIds))].sort()
  const hosts = await Promise.all(hostIds.map(async hostId => {
    const host = await hostsDB.findOneAsync({ _id: hostId })
    if (!host) throw new Error(`未找到主机 ${ hostId }`)
    return { hostId, aiPolicy: host.aiPolicy || {} }
  }))
  return { effect: strongerEffect(Effect.WRITE, verdict.effect), risk: verdict.risk,
    reason: primaryReason(verdict) || null, hosts }
}

export async function resolvePanelBatchAccess(batch, ctx) {
  let effect = batch.action === 'delete' ? Effect.DELETE : Effect.WRITE
  let risk = Risk.NORMAL
  let reason = null
  const hostIds = new Set(batch.domain === 'hosts' ? batch.items.map(item => item.id) : [])
  const riskOrder = [Risk.NORMAL, Risk.HIGH, Risk.DENY]
  for (const item of batch.items) {
    const execution = item.scheduledExecution
    if (!execution) continue
    effect = strongerEffect(effect, execution.effect)
    if (riskOrder.indexOf(execution.risk) > riskOrder.indexOf(risk)) {
      risk = execution.risk
      reason = execution.reason
    }
    execution.hosts.forEach(host => hostIds.add(host.hostId))
  }
  const hostPolicies = await Promise.all([...hostIds].map(hostId => resolvePanelHostAccess(hostId, ctx, effect)))
  return { effect, risk, reason, hostPolicies }
}

function hostMetadata(record) {
  return { name: record.name || '', groupId: record.group || 'default', tag: record.tag || [],
    expired: record.expired === null || record.expired === undefined || record.expired === '' ? null : Number(record.expired),
    expiredNotify: record.expiredNotify === true, consoleUrl: record.consoleUrl || '' }
}

function scriptMetadata(record) {
  return { name: record.name, description: record.description || '', command: record.command || '',
    groupId: record.group || 'default', useBase64: record.useBase64 === true }
}

async function requireGroup(groupId, domain) {
  if (domain === 'scripts' && groupId === 'builtin') throw new Error('内置分组只读，不能写入或移动到内置分组')
  const record = await (domain === 'hosts' ? groupsDB : scriptGroupsDB).findOneAsync({ _id: groupId })
  if (!record) throw new Error(`分组不存在: ${ groupId }`)
  return { groupId, name: record.name }
}

export async function preparePanelBatch(tool, rawInput) {
  if (!Object.hasOwn(PANEL_BATCH_SCHEMAS, tool)) throw new Error('未知面板管理工具')
  const input = PANEL_BATCH_SCHEMAS[tool].parse(rawInput)
  if (Buffer.byteLength(JSON.stringify(input)) > 1024 * 1024) throw new Error('单批内容不能超过 1 MiB')
  const domain = tool.startsWith('host_') ? 'hosts' : tool.startsWith('script_group_') ? 'script_groups' : 'scripts'
  const action = tool.endsWith('_create') ? 'create' : tool.endsWith('_delete') ? 'delete' : 'update'
  const seen = new Set()
  const items = []
  for (const [index, item] of input.items.entries()) {
    const targetId = action === 'create' ? undefined
      : domain === 'hosts' ? item.hostId : domain === 'scripts' ? item.scriptId : item.groupId
    const key = targetId || item.name
    if (seen.has(key)) throw new Error(`批次包含重复目标: ${ key }`)
    seen.add(key)
    let before = null
    let after = null
    let affectedTasks = []
    let members = []
    let group = null
    let policy = null
    if (domain === 'hosts') {
      const record = await hostsDB.findOneAsync({ _id: targetId })
      if (!record) throw new Error(`主机不存在: ${ targetId }`)
      policy = record.aiPolicy || {}
      before = hostMetadata(record)
      const { tagMode = 'replace', ...changes } = item.changes
      after = { ...before, ...changes }
      if (changes.expired !== undefined && changes.expired !== null) {
        after.expired = Number(changes.expired)
        if (!Number.isSafeInteger(after.expired) || after.expired > 8640000000000000) throw new Error('到期时间无效')
      }
      if (changes.tag) {
        after.tag = [...new Set(tagMode === 'add' ? [...before.tag, ...changes.tag]
          : tagMode === 'remove' ? before.tag.filter(tag => !changes.tag.includes(tag)) : changes.tag)]
      }
      if (changes.expired === null) after.expiredNotify = false
      if (changes.expiredNotify === true && after.expired === null) throw new Error('设置到期提醒前需要到期时间')
      group = await requireGroup(after.groupId, 'hosts')
    } else if (domain === 'scripts') {
      if (action !== 'create') {
        const script = await getScriptById(targetId)
        if (!script) throw new Error(`脚本不存在: ${ targetId }`)
        if (script.builtin) throw new Error('内置脚本只读；如需修改，请复制为新的自定义脚本')
        before = scriptMetadata(script)
        affectedTasks = await scriptReferences(targetId)
      }
      if (action !== 'delete') {
        after = action === 'create'
          ? { description: '', groupId: 'default', useBase64: false, ...item }
          : { ...before, ...item.changes }
        group = await requireGroup(after.groupId, 'scripts')
      }
    } else {
      if (targetId === 'builtin') throw new Error('内置分组只读')
      if (action === 'delete' && targetId === 'default') throw new Error('默认分组不能删除')
      if (action !== 'create') {
        const record = await scriptGroupsDB.findOneAsync({ _id: targetId })
        if (!record) throw new Error(`脚本分组不存在: ${ targetId }`)
        before = { name: record.name }
      }
      if (action !== 'delete') {
        after = { name: item.name }
        const duplicates = await scriptGroupsDB.findAsync({ name: item.name })
        if (duplicates.some(record => record._id !== targetId)) throw new Error(`脚本分组名称已存在: ${ item.name }`)
      } else {
        group = await requireGroup('default', 'scripts')
        const layout = await getLayout(ORDER_DOMAIN.SCRIPTS)
        const records = await scriptsDB.findAsync({ group: targetId })
        const byId = new Map(records.map(record => [record._id, record]))
        members = (layout.sections.find(section => section.groupId === targetId)?.itemIds || [])
          .filter(id => byId.has(id)).map(id => ({ id, name: byId.get(id).name }))
      }
    }
    const changes = [...new Set([...Object.keys(before || {}), ...Object.keys(after || {})])]
      .filter(field => JSON.stringify(before?.[field]) !== JSON.stringify(after?.[field]))
      .map(field => ({ field, before: before?.[field] ?? null, after: after?.[field] ?? null,
        ...(field === 'command' ? { diff: buildFullReplacementDiff(before?.name || after?.name || 'script', before?.command || '', after?.command || '', !before) } : {}) }))
    const scheduledExecution = domain === 'scripts'
      ? await prepareScheduledExecution(before, after, affectedTasks) : null
    items.push({ changes, id: targetId || `new-${ index + 1 }`, name: before?.name || after?.name || targetId,
      scheduledExecution,
      before, after, affectedTasks, members, group, policy, changed: action !== 'update' || JSON.stringify(before) !== JSON.stringify(after) })
  }
  if (domain === 'script_groups' && action !== 'delete' && new Set(items.map(item => item.after.name)).size !== items.length) {
    throw new Error('批次中的分组名称不能重复')
  }
  const snapshot = { tool, domain, action, items }
  const fingerprint = createHash('sha256').update(JSON.stringify(snapshot)).digest('hex')
  return { ...snapshot, fingerprint, type: 'panel_batch' }
}

// The caller checks license/host policy again before each item. No SSH is used here.
export async function executePanelBatch(prepared, { signal, beforeItem, onChange, audit } = {}) {
  const results = []
  const domains = new Set()
  let stopped = false
  try {
    for (const item of prepared.items) {
      if (signal?.aborted || stopped) {
        results.push({ id: item.id, name: item.name, status: 'not_executed' })
        continue
      }
      let changed = false
      let resultId = item.id
      const disabledTaskIds = []
      try {
        await beforeItem?.(item)
        if (signal?.aborted) {
          results.push({ id: item.id, name: item.name, status: 'not_executed' })
          stopped = true
          continue
        }
        if (!item.changed) {
          results.push({ id: item.id, name: item.name, status: 'unchanged' })
          continue
        }
        const { domain, action } = prepared
        const mark = domain => { changed = true; domains.add(domain) }
        if (domain === 'hosts') {
          const { groupId } = item.after
          const updates = Object.fromEntries(item.changes.map(change => [change.field === 'groupId' ? 'group' : change.field, change.after]))
          const count = await hostsDB.updateAsync({ _id: item.id }, { $set: updates })
          if (count.numAffected !== 1) throw new Error('主机已删除')
          mark('hosts')
          if (item.before.groupId !== groupId) await moveItemsToGroup(ORDER_DOMAIN.HOSTS, [item.id], groupId)
        } else if (domain === 'scripts') {
          if (action === 'delete') {
            await disableScheduledTasksForScripts([item.id], {
              onDisabled: taskId => {
                disabledTaskIds.push(taskId)
                mark('scheduled_tasks')
              }
            })
            const count = await scriptsDB.removeAsync({ _id: item.id })
            if (!count) throw new Error('脚本已删除')
            mark('scripts')
            await removeItemsFromOrder(ORDER_DOMAIN.SCRIPTS, [item.id])
          } else {
            const { groupId, ...fields } = item.after
            if (action === 'create') {
              const record = await scriptsDB.insertAsync({ ...fields, group: groupId })
              resultId = record._id
              mark('scripts')
              await addItemsToOrder(ORDER_DOMAIN.SCRIPTS, record)
            } else {
              const updates = Object.fromEntries(item.changes.map(change => [change.field === 'groupId' ? 'group' : change.field, change.after]))
              const count = await scriptsDB.updateAsync({ _id: item.id }, { $set: updates })
              if (count.numAffected !== 1) throw new Error('脚本已删除')
              mark('scripts')
              if (item.before.groupId !== groupId) await moveItemsToGroup(ORDER_DOMAIN.SCRIPTS, [item.id], groupId)
            }
          }
        } else if (action === 'create') {
          const record = await scriptGroupsDB.insertAsync(item.after)
          resultId = record._id
          mark('scripts')
          await addGroupToOrder(ORDER_DOMAIN.SCRIPTS, record._id)
        } else if (action === 'update') {
          const count = await scriptGroupsDB.updateAsync({ _id: item.id }, { $set: item.after })
          if (count.numAffected !== 1) throw new Error('分组已删除')
          mark('scripts')
        } else {
          const moved = await scriptsDB.updateAsync({ group: item.id }, { $set: { group: 'default' } }, { multi: true })
          if (moved.numAffected > 0) mark('scripts')
          await moveItemsToGroup(ORDER_DOMAIN.SCRIPTS, item.members.map(member => member.id), 'default')
          const removed = await scriptGroupsDB.removeAsync({ _id: item.id })
          if (!removed) throw new Error('分组已删除')
          mark('scripts')
          await getLayout(ORDER_DOMAIN.SCRIPTS)
        }
        results.push({ id: resultId, name: item.after?.name || item.name, status: 'completed',
          ...(disabledTaskIds.length ? { disabledTaskIds } : {}) })
        audit?.({ item, status: 'completed' })
      } catch (error) {
        const message = disabledTaskIds.length
          ? `${ error.message }；已禁用关联任务: ${ disabledTaskIds.map(id => item.affectedTasks.find(task => task.taskId === id)?.name || id).join('、') }`
          : error.message
        results.push({ id: resultId, name: item.name, status: 'failed', changed, error: message,
          ...(disabledTaskIds.length ? { disabledTaskIds } : {}) })
        audit?.({ item, status: 'failed', error: message })
        stopped = true
      }
    }
  } finally {
    if (domains.size) onChange?.([...domains])
  }
  const completed = results.filter(item => item.status === 'completed' || item.status === 'unchanged').length
  return { type: 'panel_batch_result', domain: prepared.domain, action: prepared.action,
    status: completed === results.length ? 'success' : domains.size ? 'partial' : 'failed',
    total: results.length, completed, results }
}

export async function executeAuthorizedPanelBatch(tool, ctx, input, options, assertPlusAccess) {
  if (ctx.scope !== 'ops') return { ok: false, error: '面板管理工具仅供全局助手使用' }
  if (typeof assertPlusAccess !== 'function') throw new Error('缺少 Plus 权限校验')
  assertPlusAccess()
  const approvedHash = ctx.authorizedPanelBatches?.get(options.toolCallId)
  ctx.authorizedPanelBatches?.delete(options.toolCallId)
  if (!approvedHash) return { ok: false, error: '缺少与本次面板变更匹配的有效授权' }
  const prepared = await preparePanelBatch(tool, input)
  if (prepared.fingerprint !== approvedHash) return { ok: false, error: '审批后面板数据或关联任务发生变化，请重新确认' }
  // Validate every target before any write, including tasks using changed scripts.
  const checkAccess = async batch => {
    const access = await resolvePanelBatchAccess(batch, ctx)
    if (access.risk === Risk.DENY) throw new Error(`关联定时任务的脚本被安全策略永久拒绝：${ access.reason?.reason || '命中拒绝规则' }`)
  }
  await checkAccess(prepared)
  const result = await executePanelBatch(prepared, {
    signal: ctx.signal,
    beforeItem: async item => {
      assertPlusAccess()
      const index = prepared.items.indexOf(item)
      const current = await preparePanelBatch(tool, { items: [input.items[index]] })
      if (prepared.action === 'create') current.items[0].id = item.id
      if (JSON.stringify(current.items[0]) !== JSON.stringify(item)) throw new Error('执行前数据发生变化，请重新确认')
      await checkAccess(current)
    },
    onChange: domains => ctx.emit?.({ type: 'panel_data_changed', domains }),
    audit: ({ item, status, error }) => writeAudit({
      action: ACTION.EXEC, sessionId: ctx.sessionId, userId: ctx.userId, tool,
      targetId: item.id, targetName: item.name, status, reason: error,
      mode: ctx.sessionMode, effect: ctx.toolMeta?.[options.toolCallId]?.effect
    })
  })
  ctx.toolMeta[options.toolCallId].panelBatchResult = result
  ctx.emit?.({ type: 'tool_progress', toolCallId: options.toolCallId, panelBatchResult: result })
  return { ok: true, data: result }
}
