import { createHash } from 'node:crypto'
import cronParser from 'cron-parser'
import { HostListDB, ScheduledTaskDB } from '../utils/db-class.js'
import { getScriptById } from './script-library.js'

export const DEFAULT_TASK_TIMEZONE = 'Asia/Shanghai'
export const DEFAULT_TASK_TIMEOUT_SECONDS = 120
export const MIN_TASK_TIMEOUT_SECONDS = 1
export const MAX_TASK_TIMEOUT_SECONDS = 1800
export const MAX_TASK_SCRIPT_BYTES = 256 * 1024
export const NOTIFICATION_POLICIES = ['failure', 'always', 'never']

const taskDB = new ScheduledTaskDB().getInstance()
const hostListDB = new HostListDB().getInstance()

export class ScheduledTaskError extends Error {
  constructor(message, status = 400, code = 'SCHEDULED_TASK_INVALID') {
    super(message)
    this.status = status
    this.code = code
  }
}

export function validateTimezone(timezone) {
  const value = String(timezone || DEFAULT_TASK_TIMEZONE).trim()
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value }).format()
  } catch {
    throw new ScheduledTaskError(`无效时区: ${ value }`)
  }
  return value
}

export function getNextCronRuns(expression, timezone = DEFAULT_TASK_TIMEZONE, count = 5, now = new Date()) {
  const value = String(expression || '').trim().replace(/\s+/g, ' ')
  if (value.split(' ').length !== 5) {
    throw new ScheduledTaskError('Cron 必须为 5 段格式：分 时 日 月 周')
  }
  const tz = validateTimezone(timezone)
  try {
    const interval = cronParser.parseExpression(value, { currentDate: now, tz })
    return {
      expression: value,
      timezone: tz,
      runTimes: Array.from({ length: count }, () => interval.next().getTime())
    }
  } catch (error) {
    throw new ScheduledTaskError(`Cron 表达式无效: ${ error.message }`)
  }
}

export function parseCronExpression(expression, timezone = DEFAULT_TASK_TIMEZONE, now = new Date()) {
  const parsed = getNextCronRuns(expression, timezone, 1, now)
  return { expression: parsed.expression, timezone: parsed.timezone, nextRunAt: parsed.runTimes[0] }
}

function normalizeTimeout(value) {
  const timeoutSeconds = Number(value ?? DEFAULT_TASK_TIMEOUT_SECONDS)
  if (!Number.isInteger(timeoutSeconds)
    || timeoutSeconds < MIN_TASK_TIMEOUT_SECONDS
    || timeoutSeconds > MAX_TASK_TIMEOUT_SECONDS) {
    throw new ScheduledTaskError(`超时时间必须是 ${ MIN_TASK_TIMEOUT_SECONDS }-${ MAX_TASK_TIMEOUT_SECONDS } 秒的整数`)
  }
  return timeoutSeconds
}

async function normalizeHosts(hostIds) {
  const ids = [...new Set(Array.isArray(hostIds) ? hostIds.map(String).filter(Boolean) : [])]
  if (!ids.length) throw new ScheduledTaskError('至少选择一台目标主机')
  const hosts = await hostListDB.findAsync({ _id: { $in: ids } })
  const byId = new Map(hosts.map(host => [host._id, host]))
  for (const id of ids) {
    const host = byId.get(id)
    if (!host) throw new ScheduledTaskError(`目标主机不存在: ${ id }`)
    if (host.connectType === 'rdp' || !host.authType || !host[host.authType]) {
      throw new ScheduledTaskError(`主机「${ host.name || id }」未配置可用的 SSH 连接`)
    }
  }
  return ids
}

function validateCommand(command) {
  const value = String(command || '')
  if (!value.trim()) throw new ScheduledTaskError('脚本内容不能为空')
  if (Buffer.byteLength(value, 'utf8') > MAX_TASK_SCRIPT_BYTES) {
    throw new ScheduledTaskError('脚本内容不能超过 256 KiB')
  }
  return value
}

async function normalizeScript(script, existingScript) {
  const source = script && typeof script === 'object' ? script : existingScript
  if (!source) throw new ScheduledTaskError('缺少任务脚本')
  const type = source.type || source.mode

  if (type === 'library') {
    const scriptId = String(source.scriptId || '').trim()
    if (!scriptId) throw new ScheduledTaskError('请选择要引用的脚本库脚本')
    const libraryScript = await getScriptById(scriptId)
    if (!libraryScript) throw new ScheduledTaskError('引用的脚本库脚本不存在')
    validateCommand(libraryScript.command)
    return { type: 'library', scriptId }
  }

  if (type !== 'inline') throw new ScheduledTaskError('任务指令配置无效')
  return {
    type: 'inline',
    command: validateCommand(source.command),
    useBase64: source.useBase64 === true
  }
}

export async function normalizeTaskInput(input = {}, existing = null) {
  const merged = existing ? { ...existing, ...input } : input
  const name = String(merged.name || '').trim()
  if (!name) throw new ScheduledTaskError('任务名称不能为空')
  if (name.length > 100) throw new ScheduledTaskError('任务名称不能超过 100 个字符')
  const parsedCron = parseCronExpression(merged.cron, merged.timezone)
  const notificationPolicy = merged.notificationPolicy || 'failure'
  if (!NOTIFICATION_POLICIES.includes(notificationPolicy)) {
    throw new ScheduledTaskError('通知策略必须是 failure、always 或 never')
  }

  return {
    name,
    enabled: merged.enabled !== false,
    hostIds: await normalizeHosts(merged.hostIds),
    cron: parsedCron.expression,
    timezone: parsedCron.timezone,
    timeoutSeconds: normalizeTimeout(merged.timeoutSeconds),
    script: await normalizeScript(input.script, existing?.script),
    notificationPolicy,
    disabledReason: merged.enabled === false ? (merged.disabledReason || '') : ''
  }
}

export async function resolveTaskScript(task) {
  if (task?.script?.type === 'inline') {
    return {
      command: validateCommand(task.script.command),
      useBase64: task.script.useBase64 === true,
      scriptId: null,
      scriptName: task.name
    }
  }
  if (task?.script?.type === 'library') {
    const script = await getScriptById(task.script.scriptId)
    if (!script) {
      throw new ScheduledTaskError('引用的脚本库脚本已不存在', 409, 'SCHEDULED_TASK_SCRIPT_MISSING')
    }
    return {
      command: validateCommand(script.command),
      useBase64: script.useBase64 === true,
      scriptId: script.id,
      scriptName: script.name
    }
  }
  throw new ScheduledTaskError('任务脚本配置无效')
}

export async function scheduledTaskFingerprint(task) {
  const script = await resolveTaskScript(task)
  const payload = {
    name: task.name,
    enabled: task.enabled,
    hostIds: task.hostIds,
    cron: task.cron,
    timezone: task.timezone,
    timeoutSeconds: task.timeoutSeconds,
    notificationPolicy: task.notificationPolicy,
    script: {
      type: task.script.type,
      scriptId: task.script.scriptId || null,
      useBase64: script.useBase64,
      command: script.command
    }
  }
  return createHash('sha256').update(JSON.stringify(payload)).digest('hex')
}

export function scheduledTaskDeleteFingerprint(task) {
  return createHash('sha256').update(JSON.stringify({
    id: task._id,
    updatedAt: task.updatedAt,
    hostIds: task.hostIds
  })).digest('hex')
}

export function publicTask(task) {
  if (!task) return null
  const { _id, ...rest } = task
  delete rest.description
  return { ...rest, id: _id }
}

export async function listStoredTasks() {
  return (await taskDB.findAsync({})).sort((left, right) => right.createdAt - left.createdAt)
}

export async function findStoredTask(id) {
  return taskDB.findOneAsync({ _id: id })
}

export async function insertStoredTask(input) {
  const now = Date.now()
  const task = await normalizeTaskInput(input)
  return taskDB.insertAsync({ ...task, createdAt: now, updatedAt: now })
}

export async function updateStoredTask(id, input) {
  const existing = await findStoredTask(id)
  if (!existing) throw new ScheduledTaskError('定时任务不存在', 404, 'SCHEDULED_TASK_NOT_FOUND')
  const task = await normalizeTaskInput(input, existing)
  await taskDB.updateAsync({ _id: id }, {
    $set: { ...task, updatedAt: Date.now() },
    $unset: { description: true }
  })
  return findStoredTask(id)
}

export async function restoreStoredTask(task) {
  if (!task?._id) throw new ScheduledTaskError('无法恢复缺少 ID 的定时任务')
  await taskDB.updateAsync({ _id: task._id }, task)
  return findStoredTask(task._id)
}

export async function removeStoredTask(id) {
  return taskDB.removeAsync({ _id: id })
}

export async function setTaskRunState(id, state) {
  await taskDB.updateAsync({ _id: id }, { $set: { ...state, updatedAt: Date.now() } })
}

export async function disableTasksReferencingScripts(scriptIds) {
  const ids = new Set(Array.isArray(scriptIds) ? scriptIds : [])
  if (!ids.size) return []
  const tasks = await taskDB.findAsync({ 'script.type': 'library', 'script.scriptId': { $in: [...ids] } })
  await Promise.all(tasks.map(task => taskDB.updateAsync({ _id: task._id }, {
    $set: {
      enabled: false,
      disabledReason: '引用的脚本库脚本已删除',
      updatedAt: Date.now()
    }
  })))
  return tasks.map(task => task._id)
}

export async function detachHostsFromStoredTasks(hostIds) {
  const removed = new Set(Array.isArray(hostIds) ? hostIds : [])
  if (!removed.size) return []
  const tasks = await taskDB.findAsync({ hostIds: { $in: [...removed] } })
  await Promise.all(tasks.map(task => {
    const hostIds = task.hostIds.filter(id => !removed.has(id))
    return taskDB.updateAsync({ _id: task._id }, { $set: {
      hostIds,
      enabled: hostIds.length ? task.enabled : false,
      disabledReason: hostIds.length ? task.disabledReason : '所有目标主机均已删除',
      updatedAt: Date.now()
    } })
  }))
  return tasks.map(task => task._id)
}
