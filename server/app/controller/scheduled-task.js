import {
  clearScheduledTaskRuns,
  createScheduledTask,
  deleteScheduledTask,
  getScheduledTask,
  getScheduledTaskRun,
  listScheduledTaskRuns,
  listScheduledTasks,
  stopScheduledTaskRun,
  triggerScheduledTask,
  updateScheduledTask
} from '../services/scheduled-task-service.js'

function fail(res, error) {
  logger.error(`定时任务接口失败: ${ error.message }`)
  res.fail({
    status: error.status || 500,
    msg: error.message || '定时任务操作失败',
    data: error.code ? { code: error.code } : {}
  })
}

export async function getScheduledTasks({ res, request }) {
  try {
    res.success({ data: await listScheduledTasks(request.query || {}) })
  } catch (error) {
    fail(res, error)
  }
}

export async function getScheduledTaskDetail({ res, request }) {
  try {
    res.success({ data: await getScheduledTask(request.params.id) })
  } catch (error) {
    fail(res, error)
  }
}

export async function addScheduledTask({ res, request }) {
  try {
    res.success({ status: 201, data: await createScheduledTask(request.body || {}) })
  } catch (error) {
    fail(res, error)
  }
}

export async function editScheduledTask({ res, request }) {
  try {
    res.success({ data: await updateScheduledTask(request.params.id, request.body || {}) })
  } catch (error) {
    fail(res, error)
  }
}

export async function removeScheduledTask({ res, request }) {
  try {
    await deleteScheduledTask(request.params.id)
    res.success({ data: true })
  } catch (error) {
    fail(res, error)
  }
}

export async function runScheduledTaskNow({ res, request }) {
  try {
    res.success({ status: 202, data: await triggerScheduledTask(request.params.id, { trigger: 'manual' }) })
  } catch (error) {
    fail(res, error)
  }
}

export async function getScheduledTaskRuns({ res, request }) {
  try {
    res.success({ data: await listScheduledTaskRuns(request.query || {}) })
  } catch (error) {
    fail(res, error)
  }
}

export async function clearScheduledTaskRunsController({ res }) {
  try {
    res.success({ data: await clearScheduledTaskRuns() })
  } catch (error) {
    fail(res, error)
  }
}

export async function getScheduledTaskRunDetail({ res, request }) {
  try {
    res.success({ data: await getScheduledTaskRun(request.params.id) })
  } catch (error) {
    fail(res, error)
  }
}

export async function stopScheduledTaskRunController({ res, request }) {
  try {
    res.success({ data: await stopScheduledTaskRun(request.params.id) })
  } catch (error) {
    fail(res, error)
  }
}
