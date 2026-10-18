import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

const cwd = process.cwd()
const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'easynode-panel-batch-'))
await fs.mkdir(path.join(directory, 'app/db'), { recursive: true })
process.chdir(directory)
global.logger = { info() {}, warn() {}, error() {} }
try {
  const { HostListDB, GroupDB, ScriptGroupDB, ScriptsDB, ScheduledTaskDB } = await import('../app/utils/db-class.js')
  const { preparePanelBatch, executePanelBatch, executeAuthorizedPanelBatch } = await import('../app/services/panel-batch.js')
  const { listBuiltinScripts } = await import('../app/services/script-library.js')
  const { resolveTaskScript } = await import('../app/services/scheduled-task-store.js')
  const { initializeOrderSystem, getLayout, updateOrder, ORDER_DOMAIN } = await import('../app/services/order-service.js')
  const { scheduleStoredTask, shutdownScheduledTasks } = await import('../app/services/scheduled-task-service.js')
  const { hostList, scriptList, scriptGet } = await import('../app/ai/tools/executors.js')
  const hosts = new HostListDB().getInstance()
  const scripts = new ScriptsDB().getInstance()
  const groups = new ScriptGroupDB().getInstance()
  const tasks = new ScheduledTaskDB().getInstance()
  await new GroupDB().getInstance().insertAsync([{ _id: 'default', name: 'Default' }, { _id: 'empty', name: 'Empty' }])
  await groups.insertAsync([{ _id: 'default', name: 'Default' }, { _id: 'builtin', name: 'Builtin' }, { _id: 'tools', name: 'Tools' }])
  await hosts.insertAsync([
    { _id: 'a', name: 'A', host: '127.0.0.1', password: 'secret', group: 'default', tag: ['old'], expired: '1', expiredNotify: true },
    { _id: 'b', name: 'B', group: 'default', aiPolicy: { enabled: false } },
    { _id: 'c', name: 'C', group: 'default', aiPolicy: { maxEffect: 'read' } }
  ])
  await scripts.insertAsync({ _id: 's', name: 'Script', command: 'echo old', group: 'tools' })
  await tasks.insertAsync({ _id: 't', name: 'Task', enabled: true, script: { type: 'library', scriptId: 's' } })
  await initializeOrderSystem()
  const notices = []
  const run = async (tool, input, options = {}) => executePanelBatch(await preparePanelBatch(tool, input), { onChange: domains => notices.push(domains), ...options })
  assert.ok((await hostList({ scope: 'ops' }, {})).data.groups.some(group => group.groupId === 'empty'))
  assert.equal((await scriptList({}, {})).data.groups.length, 3)
  assert.equal((await scriptGet({}, { scriptId: 's' })).data.affectedTasks[0].taskId, 't')
  for (const changes of [{ password: 'overwrite' }, {}, { tagMode: 'add' }, { consoleUrl: 'javascript:alert(1)' }]) {
    await assert.rejects(preparePanelBatch('host_metadata_batch_update', { items: [{ hostId: 'a', changes }] }))
  }
  await assert.rejects(preparePanelBatch('host_metadata_batch_update', { items: [{ hostId: 'a', changes: { name: 'x' } }, { hostId: 'a', changes: { name: 'y' } }] }), /重复/)
  await assert.rejects(preparePanelBatch('script_batch_create', { items: Array.from({ length: 51 }, () => ({ name: 'x', command: 'true' })) }))
  await run('host_metadata_batch_update', { items: [{ hostId: 'a', changes: { tag: ['new', 'old'], tagMode: 'add', groupId: 'empty', expired: null, consoleUrl: '' } }] })
  let host = await hosts.findOneAsync({ _id: 'a' })
  assert.deepEqual(host.tag, ['old', 'new'])
  assert.equal(host.password, 'secret')
  assert.equal(host.host, '127.0.0.1')
  assert.equal(host.expired, null)
  assert.equal(host.expiredNotify, false)
  await run('host_metadata_batch_update', { items: [{ hostId: 'a', changes: { tag: ['old'], tagMode: 'remove' } }] })
  assert.deepEqual((await hosts.findOneAsync({ _id: 'a' })).tag, ['new'])
  assert.ok((await getLayout(ORDER_DOMAIN.HOSTS)).sections.find(group => group.groupId === 'empty').itemIds.includes('a'))
  const count = notices.length
  await run('host_metadata_batch_update', { items: [{ hostId: 'a', changes: { name: 'A' } }] })
  assert.equal(notices.length, count, 'no-op must not refresh')
  await run('host_metadata_batch_update', { items: [{ hostId: 'a', changes: { tag: [], tagMode: 'replace' } }] })
  assert.deepEqual((await hosts.findOneAsync({ _id: 'a' })).tag, [])
  await assert.rejects(preparePanelBatch('host_metadata_batch_update', { items: [{ hostId: 'a', changes: { groupId: 'missing' } }] }), /分组不存在/)
  await assert.rejects(preparePanelBatch('script_batch_update', { items: [{ scriptId: 's', changes: { builtin: true } }] }))
  await assert.rejects(preparePanelBatch('script_group_batch_update', { items: [{ groupId: 'tools', name: 'Valid', extra: true }] }))
  await assert.rejects(preparePanelBatch('script_batch_delete', { items: [{ scriptId: 's' }, { scriptId: 's' }] }), /重复/)
  await run('script_batch_update', { items: [{ scriptId: 's', changes: { description: 'Description' } }] })
  await run('script_batch_update', { items: [{ scriptId: 's', changes: { description: '' } }] })
  assert.equal((await scripts.findOneAsync({ _id: 's' })).description, '')
  assert.equal((await scripts.findOneAsync({ _id: 's' })).command, 'echo old')
  await run('script_group_batch_update', { items: [{ groupId: 'default', name: 'Renamed default' }] })
  assert.equal((await groups.findOneAsync({ _id: 'default' })).name, 'Renamed default')
  const builtin = listBuiltinScripts()[0]
  for (const tool of ['script_batch_update', 'script_batch_delete']) {
    await assert.rejects(preparePanelBatch(tool, { items: [{ scriptId: builtin.id, ...(tool.endsWith('update') ? { changes: { name: 'changed' } } : {}) }] }), /内置/)
  }
  for (const tool of ['script_group_batch_update', 'script_group_batch_delete']) {
    await assert.rejects(preparePanelBatch(tool, { items: [{ groupId: 'builtin', ...(tool.endsWith('update') ? { name: 'changed' } : {}) }] }), /内置/)
  }
  await assert.rejects(preparePanelBatch('script_batch_create', { items: [{ name: 'Bad', command: 'true', groupId: 'builtin' }] }), /内置/)
  await assert.rejects(preparePanelBatch('script_group_batch_delete', { items: [{ groupId: 'default' }] }), /默认/)
  await run('script_batch_create', { items: [{ name: 'Copy', command: builtin.command }] })
  const copy = await scripts.findOneAsync({ name: 'Copy' })
  assert.notEqual(copy._id, builtin.id)
  const prepared = await preparePanelBatch('script_batch_update', { items: [{ scriptId: 's', changes: { command: 'echo new' } }] })
  assert.ok(prepared.items[0].changes[0].diff.includes('+echo new'))
  assert.equal(prepared.items[0].affectedTasks[0].taskId, 't')
  await executePanelBatch(prepared)
  assert.equal((await resolveTaskScript(await tasks.findOneAsync({ _id: 't' }))).command, 'echo new')
  assert.equal((await tasks.findOneAsync({ _id: 't' })).enabled, true)
  await run('script_group_batch_create', { items: [{ name: 'New group' }] })
  const newGroup = await groups.findOneAsync({ name: 'New group' })
  await run('script_group_batch_update', { items: [{ groupId: newGroup._id, name: 'Renamed' }] })
  await run('script_batch_update', { items: [{ scriptId: 's', changes: { groupId: newGroup._id } }] })
  await run('script_group_batch_delete', { items: [{ groupId: newGroup._id }] })
  assert.equal((await scripts.findOneAsync({ _id: 's' })).group, 'default')
  assert.ok(!(await getLayout(ORDER_DOMAIN.SCRIPTS)).sections.some(group => group.groupId === newGroup._id))
  await run('script_batch_delete', { items: [{ scriptId: 's' }] })
  assert.equal((await tasks.findOneAsync({ _id: 't' })).enabled, false)
  assert.deepEqual(new Set(notices.at(-1)), new Set(['scripts', 'scheduled_tasks']))
  const partial = await run('script_batch_create', { items: [{ name: 'one', command: 'true' }, { name: 'two', command: 'true' }, { name: 'three', command: 'true' }] }, {
    beforeItem: item => { if (item.name === 'two') throw new Error('simulated failure') }
  })
  assert.equal(partial.status, 'partial')
  assert.deepEqual(partial.results.map(item => item.status), ['completed', 'failed', 'not_executed'])
  const controller = new AbortController()
  controller.abort()
  const stopped = await run('script_batch_delete', { items: [{ scriptId: copy._id }] }, { signal: controller.signal })
  assert.equal(stopped.results[0].status, 'not_executed')
  assert.ok(await scripts.findOneAsync({ _id: copy._id }))

  // Deleting a group preserves the user's member order, including in the snapshot.
  await groups.insertAsync({ _id: 'ordered', name: 'Ordered' })
  await scripts.insertAsync(['s1', 's2', 's3'].map(id => ({ _id: id, name: id, command: 'true', group: 'ordered' })))
  let layout = await getLayout(ORDER_DOMAIN.SCRIPTS)
  const orderedIds = ['s3', 's1', 's2']
  await updateOrder(ORDER_DOMAIN.SCRIPTS, layout.revision, [{ scope: 'groupItems', groupId: 'ordered', orderedIds }])
  const deleteGroup = { items: [{ groupId: 'ordered' }] }
  const orderedPreview = await preparePanelBatch('script_group_batch_delete', deleteGroup)
  assert.deepEqual(orderedPreview.items[0].members.map(member => member.id), orderedIds)
  layout = await getLayout(ORDER_DOMAIN.SCRIPTS)
  await updateOrder(ORDER_DOMAIN.SCRIPTS, layout.revision, [{ scope: 'groupItems', groupId: 'ordered', orderedIds: ['s2', 's3', 's1'] }])
  assert.notEqual((await preparePanelBatch('script_group_batch_delete', deleteGroup)).fingerprint, orderedPreview.fingerprint)
  layout = await getLayout(ORDER_DOMAIN.SCRIPTS)
  await updateOrder(ORDER_DOMAIN.SCRIPTS, layout.revision, [{ scope: 'groupItems', groupId: 'ordered', orderedIds }])
  const defaultIds = (await getLayout(ORDER_DOMAIN.SCRIPTS)).sections.find(section => section.groupId === 'default').itemIds
  await executePanelBatch(orderedPreview)
  assert.deepEqual((await getLayout(ORDER_DOMAIN.SCRIPTS)).sections.find(section => section.groupId === 'default').itemIds, [...orderedIds, ...defaultIds])

  // Real NeDB zero-row results must fail and stop the remaining items without notifying.
  for (const [db, toolName, first, second] of [
    [hosts, 'host_metadata_batch_update', { hostId: 'gone-host', changes: { name: 'Changed' } }, { hostId: 'a', changes: { name: 'Not reached' } }],
    [scripts, 'script_batch_update', { scriptId: 'gone-script', changes: { name: 'Changed' } }, { scriptId: copy._id, changes: { name: 'Not reached' } }],
    [groups, 'script_group_batch_update', { groupId: 'gone-group', name: 'Changed' }, { groupId: 'tools', name: 'Not reached' }]
  ]) {
    const id = first.hostId || first.scriptId || first.groupId
    await db.insertAsync({ _id: id, name: 'Gone', command: 'true', group: 'default' })
    const snapshot = await preparePanelBatch(toolName, { items: [first, second] })
    const update = db.updateAsync
    const noticeCount = notices.length
    db.updateAsync = async (query, ...args) => {
      if (query._id === id) await db.removeAsync(query)
      return update.call(db, query, ...args)
    }
    try {
      const result = await executePanelBatch(snapshot, { onChange: domains => notices.push(domains) })
      assert.equal(result.status, 'failed')
      assert.deepEqual(result.results.map(item => item.status), ['failed', 'not_executed'])
      assert.equal(result.results[0].changed, false)
      assert.equal(notices.length, noticeCount)
    } finally {
      db.updateAsync = update
    }
  }
  // A zero-row move followed by failed deletion must not report a phantom change.
  await groups.insertAsync({ _id: 'empty-delete', name: 'Empty deletion' })
  const emptyDelete = await preparePanelBatch('script_group_batch_delete', { items: [{ groupId: 'empty-delete' }] })
  const removeGroup = groups.removeAsync
  groups.removeAsync = async () => { throw new Error('delete failed') }
  const beforeEmptyDelete = notices.length
  try {
    const result = await executePanelBatch(emptyDelete, { onChange: domains => notices.push(domains) })
    assert.equal(result.status, 'failed')
    assert.equal(result.results[0].changed, false)
    assert.equal(notices.length, beforeEmptyDelete)
  } finally {
    groups.removeAsync = removeGroup
  }

  // A failed task disable must cancel/notify each committed write, even if the script survives.
  await scripts.insertAsync({ _id: 'linked', name: 'Linked', command: 'true', group: 'default' })
  const linkedTasks = await tasks.insertAsync(['linked-1', 'linked-2', 'linked-3'].map(id => ({
    _id: id, name: id, enabled: true, hostIds: ['a'], cron: '0 0 1 1 *', timezone: 'UTC',
    script: { type: 'library', scriptId: 'linked' }
  })))
  const jobs = new Map(linkedTasks.map(task => [task._id, scheduleStoredTask(task)]))
  const updateTask = tasks.updateAsync
  try {
    for (const failAt of [1, 2]) {
      let writes = 0
      tasks.updateAsync = async (...args) => {
        if (++writes === failAt) throw new Error('task write failed')
        return updateTask.apply(tasks, args)
      }
      const noticeCount = notices.length
      const audits = []
      const result = await run('script_batch_delete', { items: [{ scriptId: 'linked' }, { scriptId: copy._id }] }, { audit: entry => audits.push(entry) })
      assert.equal(result.status, failAt === 1 ? 'failed' : 'partial')
      assert.deepEqual(result.results.map(item => item.status), ['failed', 'not_executed'])
      assert.equal(result.results[0].changed, failAt === 2)
      assert.ok(await scripts.findOneAsync({ _id: 'linked' }))
      assert.ok(await scripts.findOneAsync({ _id: copy._id }))
      if (failAt === 1) {
        assert.equal(notices.length, noticeCount)
        assert.ok([...jobs.values()].every(job => job.nextInvocation()))
      } else {
        const [disabledId] = result.results[0].disabledTaskIds
        assert.equal(result.results[0].disabledTaskIds.length, 1)
        assert.equal((await tasks.findOneAsync({ _id: disabledId })).enabled, false)
        assert.equal(jobs.get(disabledId).nextInvocation(), null)
        for (const [id, job] of jobs) {
          if (id !== disabledId) {
            assert.equal((await tasks.findOneAsync({ _id: id })).enabled, true)
            assert.ok(job.nextInvocation())
          }
        }
        assert.deepEqual(notices.at(-1), ['scheduled_tasks'])
        assert.match(audits[0].error, /已禁用关联任务/)
      }
    }
    tasks.updateAsync = updateTask
    const result = await run('script_batch_delete', { items: [{ scriptId: 'linked' }] })
    assert.equal(result.status, 'success')
    assert.equal(result.results[0].disabledTaskIds.length, 3)
    assert.ok([...jobs.values()].every(job => job.nextInvocation() === null))
    assert.deepEqual(new Set(notices.at(-1)), new Set(['scheduled_tasks', 'scripts']))
  } finally {
    tasks.updateAsync = updateTask
    await shutdownScheduledTasks()
  }

  // Exercise the same Plus execution entry used by the runtime, including snapshot/policy rechecks.
  let plusAvailable = true
  const executeRestrictedTool = (tool, ctx, input, options) => executeAuthorizedPanelBatch(tool, ctx, input, options, () => {
    if (!plusAvailable) throw new Error('Plus 授权已失效')
  })
  const tool = 'host_metadata_batch_update'
  const input = { items: [{ hostId: 'a', changes: { name: 'Approved name' } }] }
  const operation = await preparePanelBatch(tool, input)
  const ctx = { scope: 'ops', sessionMode: 'authorized', toolMeta: { call: { effect: 'write', risk: 'normal' } },
    authorizedPanelBatches: new Map([['call', operation.fingerprint]]), emit: event => notices.push(event) }
  const sameGroupInput = { items: [
    { name: 'Same group first', command: 'echo first', groupId: 'tools' },
    { name: 'Same group second', command: 'echo second', groupId: 'tools' }
  ] }
  const sameGroupPreview = await preparePanelBatch('script_batch_create', sameGroupInput)
  assert.deepEqual(sameGroupPreview.items.map(item => item.id), ['new-1', 'new-2'])
  ctx.authorizedPanelBatches.set('same-group', sameGroupPreview.fingerprint)
  ctx.toolMeta['same-group'] = { effect: 'write', risk: 'normal' }
  const sameGroupResult = await executeRestrictedTool('script_batch_create', ctx, sameGroupInput, { toolCallId: 'same-group' })
  assert.equal(sameGroupResult.data.status, 'success')
  assert.equal(sameGroupResult.data.completed, 2)
  const createdIds = sameGroupResult.data.results.map(item => item.id)
  assert.equal(new Set(createdIds).size, 2)
  const sameGroupOrder = (await getLayout(ORDER_DOMAIN.SCRIPTS)).sections.find(group => group.groupId === 'tools').itemIds
  for (const [index, id] of createdIds.entries()) {
    assert.notEqual(id, 'tools')
    const script = await scripts.findOneAsync({ _id: id })
    assert.equal(script.group, 'tools')
    assert.equal(script.name, sameGroupInput.items[index].name)
    assert.ok(sameGroupOrder.includes(id))
  }
  await hosts.updateAsync({ _id: 'a' }, { $set: { name: 'Concurrent change' } })
  assert.equal((await executeRestrictedTool(tool, ctx, input, { toolCallId: 'call' })).ok, false)
  const current = await preparePanelBatch(tool, input)
  ctx.authorizedPanelBatches.set('call', current.fingerprint)
  assert.equal((await executeRestrictedTool(tool, ctx, input, { toolCallId: 'call' })).ok, true)
  assert.equal((await hosts.findOneAsync({ _id: 'a' })).name, 'Approved name')
  for (const hostId of ['b', 'c']) {
    const deniedInput = { items: [{ hostId, changes: { name: 'Denied' } }] }
    ctx.authorizedPanelBatches.set('call', (await preparePanelBatch(tool, deniedInput)).fingerprint)
    await assert.rejects(executeRestrictedTool(tool, ctx, deniedInput, { toolCallId: 'call' }), /禁止|仅允许/)
  }
  const deniedBatch = { items: [{ hostId: 'a', changes: { name: 'Must not write' } }, { hostId: 'b', changes: { name: 'Disabled' } }] }
  ctx.authorizedPanelBatches.set('call', (await preparePanelBatch(tool, deniedBatch)).fingerprint)
  await assert.rejects(executeRestrictedTool(tool, ctx, deniedBatch, { toolCallId: 'call' }), /禁止/)
  assert.equal((await hosts.findOneAsync({ _id: 'a' })).name, 'Approved name', 'all host policies checked before any write')

  // Referenced script mutations must recheck task targets and policies before writing.
  await scripts.insertAsync({ _id: 'policy-script', name: 'Policy script', command: 'echo original', group: 'default' })
  await tasks.insertAsync({ _id: 'policy-task', name: 'Policy task', enabled: true, hostIds: ['a'],
    script: { type: 'library', scriptId: 'policy-script' } })
  const scriptTool = 'script_batch_update'
  const scriptInput = { items: [{ scriptId: 'policy-script', changes: { command: 'echo updated' } }] }
  const authorize = async (input = scriptInput) => {
    ctx.authorizedPanelBatches.set('call', (await preparePanelBatch(scriptTool, input)).fingerprint)
  }
  const executeScriptUpdate = (input = scriptInput) => executeRestrictedTool(scriptTool, ctx, input, { toolCallId: 'call' })
  for (const aiPolicy of [{ enabled: false }, { maxEffect: 'read' }, { maxMode: 'review' }]) {
    await authorize()
    await hosts.updateAsync({ _id: 'a' }, { $set: { aiPolicy } })
    assert.equal((await executeScriptUpdate()).ok, false, 'policy changes invalidate prior approval')
    assert.equal((await scripts.findOneAsync({ _id: 'policy-script' })).command, 'echo original')
    await hosts.updateAsync({ _id: 'a' }, { $unset: { aiPolicy: true } })
  }
  await authorize()
  await tasks.updateAsync({ _id: 'policy-task' }, { $set: { hostIds: ['b'] } })
  assert.equal((await executeScriptUpdate()).ok, false, 'retargeting a task invalidates prior approval')
  for (const enabled of [true, false]) {
    await tasks.updateAsync({ _id: 'policy-task' }, { $set: { enabled } })
    await authorize()
    await assert.rejects(executeScriptUpdate(), /禁止 AI/)
    const encoding = { items: [{ scriptId: 'policy-script', changes: { useBase64: true } }] }
    await authorize(encoding)
    await assert.rejects(executeScriptUpdate(encoding), /禁止 AI/)
  }
  await tasks.updateAsync({ _id: 'policy-task' }, { $set: { hostIds: ['a'], enabled: true } })
  const forbidden = { items: [{ scriptId: 'policy-script', changes: { command: 'rm -rf /' } }] }
  await authorize(forbidden)
  await assert.rejects(executeScriptUpdate(forbidden), /永久拒绝/)

  // A blocked later item must prevent earlier items in the batch from being written.
  await tasks.updateAsync({ _id: 'policy-task' }, { $set: { hostIds: ['c'] } })
  const mixed = { items: [{ scriptId: copy._id, changes: { name: 'Must not change' } }, ...scriptInput.items] }
  await authorize(mixed)
  await assert.rejects(executeScriptUpdate(mixed), /仅允许/)
  assert.equal((await scripts.findOneAsync({ _id: copy._id })).name, copy.name)

  // Recheck each item too, if a task's target changes after the batch preflight.
  await tasks.updateAsync({ _id: 'policy-task' }, { $set: { hostIds: ['a'] } })
  await authorize(mixed)
  const updateScript = scripts.updateAsync
  scripts.updateAsync = async (query, ...args) => {
    const result = await updateScript.call(scripts, query, ...args)
    if (query._id === copy._id) await tasks.updateAsync({ _id: 'policy-task' }, { $set: { hostIds: ['b'] } })
    return result
  }
  try {
    const result = await executeScriptUpdate(mixed)
    assert.equal(result.data.status, 'partial')
    assert.deepEqual(result.data.results.map(item => item.status), ['completed', 'failed'])
    assert.equal((await scripts.findOneAsync({ _id: 'policy-script' })).command, 'echo original')
  } finally {
    scripts.updateAsync = updateScript
  }

  const createInput = { items: [{ name: 'Before expiry', command: 'true' }, { name: 'After expiry', command: 'true' }] }
  ctx.authorizedPanelBatches.set('call', (await preparePanelBatch('script_batch_create', createInput)).fingerprint)
  let licenseChecks = 0
  const expiry = await executeAuthorizedPanelBatch('script_batch_create', ctx, createInput, { toolCallId: 'call' }, () => {
    if (++licenseChecks > 2) throw new Error('Plus expired')
  })
  assert.equal(expiry.data.status, 'partial')
  assert.deepEqual(expiry.data.results.map(item => item.status), ['completed', 'failed'])
  assert.equal(await scripts.countAsync({ name: 'After expiry' }), 0)
  const stopController = new AbortController()
  const stoppedMidway = await run('script_batch_create', { items: [{ name: 'Before stop', command: 'true' }, { name: 'After stop', command: 'true' }] }, {
    signal: stopController.signal,
    audit: ({ status }) => { if (status === 'completed') stopController.abort() }
  })
  assert.deepEqual(stoppedMidway.results.map(item => item.status), ['completed', 'not_executed'])
  assert.equal(stoppedMidway.status, 'partial')
  plusAvailable = false
  await assert.rejects(executeRestrictedTool(tool, ctx, input, { toolCallId: 'call' }), /Plus/)
  console.log('面板批量管理、内置边界、关联任务、部分失败和 Plus 执行复核通过')
} finally {
  process.chdir(cwd)
  await fs.rm(directory, { recursive: true, force: true })
}
process.exit(0)
