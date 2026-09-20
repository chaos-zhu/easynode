import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

const originalCwd = process.cwd()
const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'easynode-scheduled-tasks-'))
await fs.mkdir(path.join(tempRoot, 'app', 'db'), { recursive: true })
process.chdir(tempRoot)
global.logger = { info() {}, warn() {}, error() {} }

try {
  const { HostListDB, NotifyDB, ScheduledTaskRunDB, ScriptsDB } = await import('../app/utils/db-class.js')
  const {
    MAX_TASK_SCRIPT_BYTES,
    ScheduledTaskError,
    detachHostsFromStoredTasks,
    disableTasksReferencingScripts,
    getNextCronRuns,
    insertStoredTask,
    parseCronExpression,
    resolveTaskScript,
    scheduledTaskFingerprint,
    setTaskRunState
  } = await import('../app/services/scheduled-task-store.js')
  const { listBuiltinScripts } = await import('../app/services/script-library.js')
  const {
    clearScheduledTaskRuns,
    createScheduledTask,
    deleteScheduledTask,
    getScheduledTask,
    getScheduledTaskRun,
    listScheduledTasks,
    pruneScheduledTaskRuns,
    recoverInterruptedRuns,
    triggerScheduledTask,
    updateScheduledTask
  } = await import('../app/services/scheduled-task-service.js')
  const {
    SCHEDULED_TASK_OUTPUT_LIMIT,
    buildScheduledScriptCommand,
    createOutputCollector,
    executeScheduledHost
  } = await import('../app/services/scheduled-task-runner.js')

  const hosts = new HostListDB().getInstance()
  const scripts = new ScriptsDB().getInstance()
  const notifications = new NotifyDB().getInstance()
  const runs = new ScheduledTaskRunDB().getInstance()
  await notifications.insertAsync({ type: 'login', desc: 'existing', sw: true })
  const { default: initializeDatabase } = await import('../app/db.js')
  await initializeDatabase()
  assert.equal((await notifications.findAsync({ type: 'login' })).length, 1)
  assert.equal((await notifications.findAsync({ type: 'scheduled_task_execution' })).length, 1)
  await hosts.insertAsync([
    { _id: 'host-a', name: 'Alpha', authType: 'password', password: 'encrypted' },
    { _id: 'host-b', name: 'Beta', authType: 'privateKey', privateKey: 'encrypted' },
    { _id: 'rdp', name: 'RDP', connectType: 'rdp', authType: 'password', password: 'encrypted' }
  ])
  await scripts.insertAsync({
    _id: 'script-a',
    name: 'Library script',
    command: 'echo first',
    useBase64: true
  })

  const parsed = parseCronExpression('*/5 * * * *', 'Asia/Shanghai', new Date('2026-01-01T00:00:00Z'))
  assert.equal(parsed.expression, '*/5 * * * *')
  assert.equal(parsed.timezone, 'Asia/Shanghai')
  assert.ok(parsed.nextRunAt > Date.parse('2026-01-01T00:00:00Z'))
  const weeklyRuns = getNextCronRuns('0 0 * * 1', 'Asia/Shanghai', 5, new Date('2026-01-01T00:00:00Z')).runTimes
  assert.equal(weeklyRuns.length, 5)
  assert.ok(weeklyRuns.every((time, index) => index === 0 || time > weeklyRuns[index - 1]))
  assert.throws(() => parseCronExpression('0 0 1 * * *'), ScheduledTaskError)
  assert.throws(() => parseCronExpression('0 0 * * *', 'Mars/Olympus'), ScheduledTaskError)

  await assert.rejects(insertStoredTask({
    name: 'RDP task', hostIds: ['rdp'], cron: '* * * * *', script: { type: 'inline', command: 'true' }
  }), /SSH/)
  await assert.rejects(insertStoredTask({
    name: 'Too long', hostIds: ['host-a'], cron: '* * * * *',
    script: { type: 'inline', command: 'x'.repeat(MAX_TASK_SCRIPT_BYTES + 1) }
  }), /256 KiB/)
  await assert.rejects(insertStoredTask({
    name: 'Timeout', hostIds: ['host-a'], cron: '* * * * *', timeoutSeconds: 1801,
    script: { type: 'inline', command: 'true' }
  }), /1-1800/)

  const imported = await insertStoredTask({
    name: 'Imported', description: 'legacy description', hostIds: ['host-a'], cron: '0 2 * * *',
    script: { type: 'inline', command: 'echo first', useBase64: true }
  })
  assert.equal(imported.script.type, 'inline')
  assert.equal(imported.description, undefined)
  const importedListItem = (await listScheduledTasks()).find(task => task.id === imported._id)
  assert.equal(importedListItem.script.command, undefined)
  assert.equal((await getScheduledTask(imported._id)).script.command, 'echo first')

  const referenced = await insertStoredTask({
    name: 'Referenced', hostIds: ['host-a', 'host-b'], cron: '0 3 * * *',
    script: { type: 'library', scriptId: 'script-a' }
  })
  const firstFingerprint = await scheduledTaskFingerprint(referenced)
  await scripts.updateAsync({ _id: 'script-a' }, { $set: { command: 'echo second', useBase64: false } })
  const latestReferencedScript = await resolveTaskScript(referenced)
  assert.equal(latestReferencedScript.command, 'echo second')
  assert.equal(latestReferencedScript.useBase64, false)
  const unchangedImportedScript = await resolveTaskScript(imported)
  assert.equal(unchangedImportedScript.command, 'echo first')
  assert.equal(unchangedImportedScript.useBase64, true)
  assert.notEqual(await scheduledTaskFingerprint(referenced), firstFingerprint)

  const scheduled = await createScheduledTask({
    name: 'Scheduled', hostIds: ['host-a'], cron: '5 4 * * *',
    script: { type: 'inline', command: 'true' }
  })
  assert.ok(scheduled.nextRunAt)
  const scheduleModule = (await import('node-schedule')).default
  const originalScheduleJob = scheduleModule.scheduleJob
  scheduleModule.scheduleJob = () => null
  await assert.rejects(updateScheduledTask(scheduled.id, { name: 'Should roll back' }), /无法注册 Cron/)
  scheduleModule.scheduleJob = originalScheduleJob
  const rolledBack = await getScheduledTask(scheduled.id)
  assert.equal(rolledBack.name, 'Scheduled')
  assert.ok(rolledBack.nextRunAt)
  await deleteScheduledTask(scheduled.id)

  const disabledIds = await disableTasksReferencingScripts(['script-a'])
  assert.deepEqual(disabledIds, [referenced._id])

  await detachHostsFromStoredTasks(['host-a', 'host-b'])
  const storedReferenced = (await import('../app/services/scheduled-task-store.js')).findStoredTask
  const detached = await storedReferenced(referenced._id)
  assert.deepEqual(detached.hostIds, [])
  assert.equal(detached.enabled, false)

  const oldCreatedAt = Date.now() - 91 * 24 * 60 * 60 * 1000
  await runs.insertAsync([
    { kind: 'batch', status: 'success', createdAt: oldCreatedAt },
    { kind: 'target', status: 'success', createdAt: oldCreatedAt },
    { kind: 'batch', status: 'success', createdAt: Date.now() }
  ])
  assert.equal(await pruneScheduledTaskRuns(), 2)
  assert.equal((await runs.findAsync({})).length, 1)

  const completedBatch = await runs.insertAsync({
    kind: 'batch', status: 'success', createdAt: Date.now()
  })
  const completedTarget = await runs.insertAsync({
    kind: 'target', runId: completedBatch._id, status: 'success', createdAt: Date.now()
  })
  const runningBatch = await runs.insertAsync({
    kind: 'batch', status: 'running', createdAt: Date.now()
  })
  const finishedRunningTarget = await runs.insertAsync({
    kind: 'target', runId: runningBatch._id, status: 'success', createdAt: Date.now()
  })
  const runningTarget = await runs.insertAsync({
    kind: 'target', runId: runningBatch._id, status: 'running', createdAt: Date.now()
  })
  const cleared = await clearScheduledTaskRuns()
  assert.ok(cleared.batchesRemoved >= 1)
  assert.equal(await runs.findOneAsync({ _id: completedBatch._id }), null)
  assert.equal(await runs.findOneAsync({ _id: completedTarget._id }), null)
  assert.ok(await runs.findOneAsync({ _id: runningBatch._id }))
  assert.ok(await runs.findOneAsync({ _id: finishedRunningTarget._id }))
  assert.ok(await runs.findOneAsync({ _id: runningTarget._id }))
  await runs.removeAsync({ runId: runningBatch._id }, { multi: true })
  await runs.removeAsync({ _id: runningBatch._id })

  const skipped = await triggerScheduledTask(referenced._id)
  assert.equal(skipped.status, 'skipped')
  assert.equal(skipped.targetCount, 0)
  assert.equal(skipped.reason, '没有可执行的目标主机')

  const interruptedBatch = await runs.insertAsync({
    kind: 'batch', taskId: referenced._id, taskName: referenced.name,
    status: 'running', startedAt: Date.now(), createdAt: Date.now()
  })
  const interruptedTarget = await runs.insertAsync({
    kind: 'target', runId: interruptedBatch._id, taskId: referenced._id,
    status: 'running', startedAt: Date.now(), createdAt: Date.now()
  })
  await recoverInterruptedRuns()
  assert.equal((await getScheduledTaskRun(interruptedBatch._id)).status, 'interrupted')
  assert.equal((await runs.findOneAsync({ _id: interruptedTarget._id })).status, 'interrupted')
  assert.equal((await getScheduledTask(referenced._id)).lastRunStatus, 'interrupted')

  const newerResultTask = await insertStoredTask({
    name: 'Newer result', hostIds: ['host-a'], cron: '0 4 * * *',
    script: { type: 'inline', command: 'true' }
  })
  const staleStartedAt = Date.now() - 10_000
  await runs.insertAsync({
    kind: 'batch', taskId: newerResultTask._id, taskName: newerResultTask.name,
    status: 'running', startedAt: staleStartedAt, createdAt: staleStartedAt
  })
  const newerLastRunAt = Date.now()
  await setTaskRunState(newerResultTask._id, { lastRunAt: newerLastRunAt, lastRunStatus: 'success' })
  await recoverInterruptedRuns()
  const preservedTask = await getScheduledTask(newerResultTask._id)
  assert.equal(preservedTask.lastRunAt, newerLastRunAt)
  assert.equal(preservedTask.lastRunStatus, 'success')

  const builtinIds = listBuiltinScripts().map(script => script.id)
  assert.ok(builtinIds.length > 0)
  assert.equal(new Set(builtinIds).size, builtinIds.length)
  assert.ok(builtinIds.every(id => /^builtin-[a-z0-9-]+$/.test(id)))

  const collector = createOutputCollector()
  collector.appendStdout(Buffer.alloc(SCHEDULED_TASK_OUTPUT_LIMIT - 10, 97))
  collector.appendStderr(Buffer.alloc(20, 98))
  collector.appendStdout('ignored')
  const collected = collector.result()
  assert.equal(Buffer.byteLength(collected.stdout) + Buffer.byteLength(collected.stderr), SCHEDULED_TASK_OUTPUT_LIMIT)
  assert.equal(collected.truncated, true)
  assert.equal(collected.bytes, SCHEDULED_TASK_OUTPUT_LIMIT)

  const invalidUtf8 = createOutputCollector(4)
  invalidUtf8.appendStdout(Buffer.from([0xff, 0xff, 0xff, 0xff]))
  const invalidResult = invalidUtf8.result()
  assert.ok(Buffer.byteLength(invalidResult.stdout) <= 4)

  assert.match(buildScheduledScriptCommand('echo ok', true), /base64 -d/)
  assert.match(buildScheduledScriptCommand('echo ok', false), /echo ok/)

  class FakeClient extends EventEmitter {
    constructor({ ready = true, output = '', complete = true } = {}) {
      super()
      this.ready = ready
      this.output = output
      this.complete = complete
      this.closed = false
    }
    connect() {
      if (this.ready) queueMicrotask(() => this.emit('ready'))
    }
    exec(command, callback) {
      const stream = new EventEmitter()
      stream.stderr = new EventEmitter()
      stream.signal = () => { stream.closed = true }
      stream.close = () => { stream.closed = true }
      stream.end = () => { stream.closed = true }
      stream.destroy = () => { stream.closed = true }
      this.stream = stream
      callback(null, stream)
      if (!this.complete) return
      queueMicrotask(() => {
        stream.emit('data', this.output)
        stream.emit('close', 0, null)
      })
    }
    end() { this.closed = true }
    destroy() { this.closed = true }
  }

  const adapters = client => ({
    getConnectionOptions: async () => ({ authInfo: { host: '127.0.0.1', port: 22 }, hostInfo: {} }),
    handleProxyAndJumpHostConnection: async ({ targetConnectionOptions }) => ({
      targetConnectionOptions,
      jumpSshClients: []
    }),
    createClient: () => client
  })

  const successClient = new FakeClient({ output: 'done\n' })
  const success = await executeScheduledHost({
    host: { _id: 'host-a' }, command: 'true', timeoutSeconds: 1, adapters: adapters(successClient)
  })
  assert.equal(success.status, 'success')
  assert.equal(success.stdout, 'done\n')
  assert.equal(successClient.closed, true)

  const timeoutClient = new FakeClient({ ready: false })
  const timeout = await executeScheduledHost({
    host: { _id: 'host-a' }, command: 'true', timeoutSeconds: 0.01, adapters: adapters(timeoutClient)
  })
  assert.equal(timeout.status, 'timeout')
  assert.equal(timeout.timeoutPhase, 'ssh_connection')
  assert.match(timeout.error, /SSH 连接与认证阶段超时/)
  assert.equal(timeoutClient.closed, true)

  const hangingScriptClient = new FakeClient({ complete: false })
  const hangingScript = await executeScheduledHost({
    host: { _id: 'host-a' }, command: 'sleep 10', timeoutSeconds: 0.01,
    adapters: adapters(hangingScriptClient)
  })
  assert.equal(hangingScript.status, 'timeout')
  assert.equal(hangingScript.timeoutPhase, 'script_execution')
  assert.match(hangingScript.error, /脚本执行阶段超时/)
  assert.equal(hangingScriptClient.stream.closed, true)

  const cancelClient = new FakeClient({ ready: false })
  const controller = new AbortController()
  const cancelledPromise = executeScheduledHost({
    host: { _id: 'host-a' }, command: 'true', timeoutSeconds: 1, signal: controller.signal,
    adapters: adapters(cancelClient)
  })
  await new Promise(resolve => setTimeout(resolve, 0))
  controller.abort()
  const cancelled = await cancelledPromise
  assert.equal(cancelled.status, 'cancelled')
  assert.equal(cancelClient.closed, true)

  console.log('定时任务测试通过')
} catch (error) {
  console.error(error)
  process.exitCode = 1
} finally {
  process.chdir(originalCwd)
  await fs.rm(tempRoot, { recursive: true, force: true })
}

process.exit(process.exitCode || 0)
