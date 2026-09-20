import { createHash } from 'node:crypto'
import schedule from 'node-schedule'
import { HostListDB, ScheduledTaskRunDB } from '../utils/db-class.js'
import { sendNoticeAsync } from '../utils/notify.js'
import { executeScheduledHost } from './scheduled-task-runner.js'
import {
  ScheduledTaskError,
  detachHostsFromStoredTasks,
  disableTasksReferencingScripts,
  findStoredTask,
  getNextCronRuns,
  insertStoredTask,
  listStoredTasks,
  publicTask,
  removeStoredTask,
  resolveTaskScript,
  restoreStoredTask,
  setTaskRunState,
  updateStoredTask
} from './scheduled-task-store.js'

export const TASK_RUN_RETENTION_DAYS = 90

const runDB = new ScheduledTaskRunDB().getInstance()
const hostListDB = new HostListDB().getInstance()
const jobs = new Map()
const activeRuns = new Map()

function publicRecord(record) {
  if (!record) return null
  const { _id, ...rest } = record
  return { ...rest, id: _id }
}

function nextRunAt(id) {
  const value = jobs.get(id)?.nextInvocation?.()
  return value ? value.getTime() : null
}

function enrichTask(task) {
  return {
    ...publicTask(task),
    nextRunAt: task.enabled ? nextRunAt(task._id) : null,
    nextRunTimes: getNextCronRuns(task.cron, task.timezone).runTimes
  }
}

function taskListItem(task) {
  const result = enrichTask(task)
  if (result.script?.type === 'inline') {
    result.script = { ...result.script }
    delete result.script.command
  }
  return result
}

function cancelJob(taskId) {
  const job = jobs.get(taskId)
  if (job) job.cancel()
  jobs.delete(taskId)
}

export function scheduleStoredTask(task) {
  if (!task.enabled) {
    cancelJob(task._id)
    return null
  }
  const job = schedule.scheduleJob(
    { rule: task.cron, tz: task.timezone },
    fireDate => triggerScheduledTask(task._id, { trigger: 'scheduled', scheduledAt: fireDate.getTime() })
      .catch(error => logger.error(`定时任务 ${ task._id } 触发失败:`, error.message))
  )
  if (!job) throw new ScheduledTaskError('无法注册 Cron 调度，请检查表达式与时区')
  cancelJob(task._id)
  jobs.set(task._id, job)
  return job
}

export async function listScheduledTasks({ keyword = '' } = {}) {
  const query = String(keyword).trim().toLowerCase()
  return (await listStoredTasks())
    .filter(task => !query || [task.name, task.cron, task.timezone]
      .some(value => String(value || '').toLowerCase().includes(query)))
    .map(taskListItem)
}

export async function getScheduledTask(id, { recentRuns = 0 } = {}) {
  const task = await findStoredTask(id)
  if (!task) throw new ScheduledTaskError('定时任务不存在', 404, 'SCHEDULED_TASK_NOT_FOUND')
  const result = enrichTask(task)
  if (recentRuns > 0) {
    const runs = (await runDB.findAsync({ kind: 'batch', taskId: id }))
      .sort((left, right) => right.createdAt - left.createdAt)
      .slice(0, recentRuns)
    result.recentRuns = await Promise.all(runs.map(async run => {
      const targets = await runDB.findAsync({ kind: 'target', runId: run._id })
      return {
        ...publicRecord(run),
        targets: targets.map(item => ({
          hostId: item.hostId,
          hostName: item.hostName,
          status: item.status,
          exitCode: item.exitCode,
          durationMs: item.durationMs,
          error: item.error
        }))
      }
    }))
  }
  return result
}

export async function createScheduledTask(input) {
  const task = await insertStoredTask(input)
  try {
    scheduleStoredTask(task)
  } catch (error) {
    await removeStoredTask(task._id)
    throw error
  }
  return enrichTask(task)
}

export async function updateScheduledTask(id, input) {
  const previous = await findStoredTask(id)
  if (!previous) throw new ScheduledTaskError('定时任务不存在', 404, 'SCHEDULED_TASK_NOT_FOUND')
  const task = await updateStoredTask(id, input)
  try {
    scheduleStoredTask(task)
    return enrichTask(task)
  } catch (error) {
    try {
      await restoreStoredTask(previous)
    } catch (restoreError) {
      logger.error(`回滚定时任务「${ previous.name }」失败:`, restoreError)
    }
    throw error
  }
}

export async function deleteScheduledTask(id) {
  const task = await findStoredTask(id)
  if (!task) throw new ScheduledTaskError('定时任务不存在', 404, 'SCHEDULED_TASK_NOT_FOUND')
  if (activeRuns.has(id)) {
    throw new ScheduledTaskError('任务正在执行，请先停止当前批次', 409, 'SCHEDULED_TASK_RUNNING')
  }
  await removeStoredTask(id)
  cancelJob(id)
}

function batchStatus(results) {
  const statuses = new Set(results.map(item => item.status))
  if (statuses.size === 1) return results[0]?.status || 'failed'
  return 'partial'
}

function statusLabel(status) {
  return ({
    success: '成功',
    partial: '部分失败',
    failed: '失败',
    timeout: '超时',
    cancelled: '已取消',
    skipped: '已跳过',
    interrupted: '已中断'
  })[status] || status
}

async function sendRunNotification(task, run, results = []) {
  const policy = task.notificationPolicy || 'failure'
  if (policy === 'never' || (policy === 'failure' && run.status === 'success')) return
  const counts = results.reduce((acc, item) => {
    acc[item.status] = (acc[item.status] || 0) + 1
    return acc
  }, {})
  const failed = results.filter(item => item.status !== 'success').slice(0, 5)
  const lines = [
    `任务：${ task.name }`,
    `触发方式：${ run.trigger === 'manual' ? '手动执行' : 'Cron 调度' }`,
    `状态：${ statusLabel(run.status) }`,
    `目标主机：${ run.targetCount ?? results.length }`,
    `结果：${ Object.entries(counts).map(([key, value]) => `${ statusLabel(key) } ${ value }`).join('，') || run.reason || '--' }`,
    `耗时：${ run.durationMs || 0 } ms`
  ]
  if (failed.length) {
    lines.push(`异常摘要：${ failed.map(item => `${ item.hostName }: ${ item.error || statusLabel(item.status) }`).join('；') }`)
  }
  await sendNoticeAsync('scheduled_task_execution', `定时任务${ statusLabel(run.status) }`, lines.join('\n'))
}

async function insertSkippedRun(task, trigger, scheduledAt, reason) {
  const now = Date.now()
  const run = await runDB.insertAsync({
    kind: 'batch',
    taskId: task._id,
    taskName: task.name,
    trigger,
    scheduledAt,
    startedAt: now,
    endedAt: now,
    durationMs: 0,
    status: 'skipped',
    reason,
    targetCount: task.hostIds.length,
    counts: {},
    createdAt: now
  })
  await setTaskRunState(task._id, { lastRunAt: now, lastRunStatus: 'skipped' })
  await sendRunNotification(task, run)
  return publicRecord(run)
}

async function finalizeWithoutTargets(task, batch, status, error) {
  const endedAt = Date.now()
  const state = {
    status,
    error,
    endedAt,
    durationMs: endedAt - batch.startedAt,
    counts: { [status]: task.hostIds.length }
  }
  await runDB.updateAsync({ _id: batch._id }, { $set: state })
  await setTaskRunState(task._id, { lastRunAt: endedAt, lastRunStatus: status })
  const run = { ...batch, ...state }
  await sendRunNotification(task, run, task.hostIds.map(hostId => ({ hostId, hostName: hostId, status, error })))
  return run
}

async function executeBatch(task, batch, controller, scriptSnapshot) {
  if (scriptSnapshot.error) {
    const error = scriptSnapshot.error
    if (error.code === 'SCHEDULED_TASK_SCRIPT_MISSING') {
      await setTaskRunState(task._id, {
        enabled: false,
        disabledReason: '引用的脚本库脚本已删除'
      })
      cancelJob(task._id)
    }
    return finalizeWithoutTargets(task, batch, 'failed', error.message)
  }
  const script = scriptSnapshot.script

  const hosts = await hostListDB.findAsync({ _id: { $in: task.hostIds } })
  const hostById = new Map(hosts.map(host => [host._id, host]))
  const commandHash = createHash('sha256').update(script.command).digest('hex')
  await runDB.updateAsync({ _id: batch._id }, { $set: {
    script: {
      type: task.script.type,
      scriptId: script.scriptId,
      scriptName: script.scriptName,
      commandHash,
      useBase64: script.useBase64
    }
  } })

  const targets = await runDB.insertAsync(task.hostIds.map((hostId, order) => {
    const host = hostById.get(hostId)
    return {
      kind: 'target',
      runId: batch._id,
      taskId: task._id,
      order,
      hostId,
      hostName: host?.name || hostId,
      hostAddress: host ? `${ host.host }:${ host.port }` : '',
      status: 'running',
      stdout: '',
      stderr: '',
      truncated: false,
      startedAt: Date.now(),
      createdAt: Date.now()
    }
  }))

  const results = await Promise.all(targets.map(async target => {
    const host = hostById.get(target.hostId)
    const result = host
      ? await executeScheduledHost({
        host,
        command: script.command,
        useBase64: script.useBase64,
        timeoutSeconds: task.timeoutSeconds,
        signal: controller.signal
      })
      : {
        status: 'failed',
        stdout: '',
        stderr: '',
        truncated: false,
        exitCode: null,
        durationMs: 0,
        endedAt: Date.now(),
        error: '目标主机已不存在'
      }
    const persisted = { ...result, hostId: target.hostId, hostName: target.hostName }
    await runDB.updateAsync({ _id: target._id }, { $set: result })
    return persisted
  }))

  const endedAt = Date.now()
  const status = batchStatus(results)
  const counts = results.reduce((acc, item) => {
    acc[item.status] = (acc[item.status] || 0) + 1
    return acc
  }, {})
  const state = { status, counts, endedAt, durationMs: endedAt - batch.startedAt }
  await runDB.updateAsync({ _id: batch._id }, { $set: state })
  await setTaskRunState(task._id, { lastRunAt: endedAt, lastRunStatus: status })
  const run = { ...batch, ...state }
  await sendRunNotification(task, run, results)
  return run
}

export async function triggerScheduledTask(id, options = {}) {
  const task = await findStoredTask(id)
  if (!task) throw new ScheduledTaskError('定时任务不存在', 404, 'SCHEDULED_TASK_NOT_FOUND')
  const trigger = options.trigger === 'scheduled' ? 'scheduled' : 'manual'
  const scheduledAt = Number(options.scheduledAt) || Date.now()
  if (activeRuns.has(id)) {
    return insertSkippedRun(task, trigger, scheduledAt, '上一次执行仍在运行')
  }
  if (!task.hostIds.length) {
    return insertSkippedRun(task, trigger, scheduledAt, '没有可执行的目标主机')
  }

  const controller = new AbortController()
  activeRuns.set(id, { runId: null, controller, promise: null })
  try {
    let scriptSnapshot
    try {
      scriptSnapshot = { script: await resolveTaskScript(task) }
    } catch (error) {
      scriptSnapshot = { error }
    }
    const now = Date.now()
    const batch = await runDB.insertAsync({
      kind: 'batch',
      taskId: task._id,
      taskName: task.name,
      trigger,
      scheduledAt,
      startedAt: now,
      status: 'running',
      targetCount: task.hostIds.length,
      counts: {},
      createdAt: now
    })
    const active = activeRuns.get(id)
    active.runId = batch._id
    active.promise = executeBatch(task, batch, controller, scriptSnapshot)
      .catch(error => {
        logger.error(`定时任务「${ task.name }」执行失败:`, error)
        return finalizeWithoutTargets(task, batch, controller.signal.aborted ? 'cancelled' : 'failed', error.message)
      })
      .finally(() => activeRuns.delete(id))
    return publicRecord(batch)
  } catch (error) {
    activeRuns.delete(id)
    throw error
  }
}

export async function listScheduledTaskRuns({ taskId, status, page = 1, pageSize = 20 } = {}) {
  const safePage = Math.max(1, Number.parseInt(page, 10) || 1)
  const safeSize = Math.min(100, Math.max(1, Number.parseInt(pageSize, 10) || 20))
  const query = { kind: 'batch' }
  if (taskId) query.taskId = taskId
  if (status) query.status = status
  const records = (await runDB.findAsync(query)).sort((left, right) => right.createdAt - left.createdAt)
  const start = (safePage - 1) * safeSize
  return {
    items: records.slice(start, start + safeSize).map(publicRecord),
    total: records.length,
    page: safePage,
    pageSize: safeSize
  }
}

export async function getScheduledTaskRun(id, { includeOutput = true } = {}) {
  const run = await runDB.findOneAsync({ _id: id, kind: 'batch' })
  if (!run) throw new ScheduledTaskError('执行记录不存在', 404, 'SCHEDULED_TASK_RUN_NOT_FOUND')
  const targets = (await runDB.findAsync({ kind: 'target', runId: id }))
    .sort((left, right) => left.order - right.order)
    .map(target => {
      const result = publicRecord(target)
      if (!includeOutput) {
        delete result.stdout
        delete result.stderr
      }
      return result
    })
  return { ...publicRecord(run), targets }
}

export async function stopScheduledTaskRun(id) {
  const run = await runDB.findOneAsync({ _id: id, kind: 'batch' })
  if (!run) throw new ScheduledTaskError('执行记录不存在', 404, 'SCHEDULED_TASK_RUN_NOT_FOUND')
  if (run.status !== 'running') throw new ScheduledTaskError('该批次已经结束', 409, 'SCHEDULED_TASK_RUN_FINISHED')
  const active = activeRuns.get(run.taskId)
  if (!active || active.runId !== id) {
    throw new ScheduledTaskError('运行状态已失效，请刷新后重试', 409, 'SCHEDULED_TASK_RUN_STALE')
  }
  active.controller.abort()
  return { id, status: 'cancelling' }
}

export async function clearScheduledTaskRuns() {
  const completedBatches = await runDB.findAsync({
    kind: 'batch',
    status: { $ne: 'running' }
  }, { _id: 1 })
  const runIds = completedBatches.map(run => run._id)
  if (!runIds.length) return { batchesRemoved: 0, targetsRemoved: 0 }

  const targetsRemoved = await runDB.removeAsync({
    kind: 'target',
    runId: { $in: runIds }
  }, { multi: true })
  const batchesRemoved = await runDB.removeAsync({
    kind: 'batch',
    _id: { $in: runIds },
    status: { $ne: 'running' }
  }, { multi: true })
  await runDB.compactDatafileAsync()
  return { batchesRemoved, targetsRemoved }
}

export async function pruneScheduledTaskRuns(now = Date.now()) {
  const cutoff = now - TASK_RUN_RETENTION_DAYS * 24 * 60 * 60 * 1000
  const removed = await runDB.removeAsync({
    createdAt: { $lt: cutoff },
    status: { $ne: 'running' }
  }, { multi: true })
  await runDB.compactDatafileAsync()
  return removed
}

export async function recoverInterruptedRuns() {
  const endedAt = Date.now()
  const runningBatches = await runDB.findAsync({ kind: 'batch', status: 'running' })
  await runDB.updateAsync({ kind: 'batch', status: 'running' }, {
    $set: { status: 'interrupted', endedAt, error: '面板进程在执行期间退出' }
  }, { multi: true })
  await runDB.updateAsync({ kind: 'target', status: 'running' }, {
    $set: { status: 'interrupted', endedAt, error: '面板进程在执行期间退出' }
  }, { multi: true })
  const latestByTask = new Map()
  for (const run of runningBatches) {
    if (!run.taskId) continue
    const current = latestByTask.get(run.taskId)
    if (!current || Number(run.startedAt || run.createdAt || 0) > Number(current.startedAt || current.createdAt || 0)) {
      latestByTask.set(run.taskId, run)
    }
  }
  await Promise.all([...latestByTask.entries()].map(async ([taskId, run]) => {
    const task = await findStoredTask(taskId)
    if (!task) return
    const runStartedAt = Number(run.startedAt || run.createdAt || 0)
    if (Number(task.lastRunAt || 0) > runStartedAt) return
    await setTaskRunState(taskId, {
      lastRunAt: endedAt,
      lastRunStatus: 'interrupted'
    })
  }))
}

export async function initializeScheduledTasks() {
  await recoverInterruptedRuns()
  await pruneScheduledTaskRuns()
  const tasks = await listStoredTasks()
  for (const task of tasks) {
    try {
      scheduleStoredTask(task)
    } catch (error) {
      logger.error(`恢复定时任务「${ task.name }」失败:`, error.message)
      await setTaskRunState(task._id, { enabled: false, disabledReason: error.message })
    }
  }
}

export async function disableScheduledTasksForScripts(scriptIds) {
  const taskIds = await disableTasksReferencingScripts(scriptIds)
  taskIds.forEach(cancelJob)
  return taskIds
}

export async function detachHostsFromScheduledTasks(hostIds) {
  const taskIds = await detachHostsFromStoredTasks(hostIds)
  for (const taskId of taskIds) {
    const task = await findStoredTask(taskId)
    scheduleStoredTask(task)
  }
  return taskIds
}

export async function shutdownScheduledTasks() {
  jobs.forEach(job => job.cancel())
  jobs.clear()
  const pending = []
  for (const active of activeRuns.values()) {
    active.controller.abort()
    if (active.promise) pending.push(active.promise)
  }
  await Promise.allSettled(pending)
}

export function isScheduledTaskRunning(taskId) {
  return activeRuns.has(taskId)
}
