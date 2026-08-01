import {
  listSessions,
  getSession,
  updateSession,
  forkSession,
  removeSession,
  removeSessions,
  truncateForUserEdit
} from '../ai/session-store.js'

async function getAgentSessions({ res, request }) {
  try {
    const { scope, hostId } = request.query || {}
    res.success({ data: await listSessions({ scope, hostId }) })
  } catch (error) {
    logger.error(`获取 agent 会话列表失败: ${ error.message }`)
    res.fail({ msg: '获取会话列表失败' })
  }
}

async function getAgentSessionDetail({ res, request }) {
  const { params: { id } } = request
  if (!id) return res.fail({ msg: '参数错误' })
  try {
    const session = await getSession(id)
    if (!session) return res.fail({ msg: '会话不存在' })
    res.success({ data: session })
  } catch (error) {
    logger.error(`获取 agent 会话详情失败: ${ error.message }`)
    res.fail({ msg: '获取会话详情失败' })
  }
}

async function updateAgentSession({ res, request }) {
  const { params: { id } } = request
  if (!id) return res.fail({ msg: '参数错误' })
  try {
    const session = await updateSession(id, request.body || {})
    if (!session) return res.fail({ msg: '会话不存在' })
    res.success({ data: session })
  } catch (error) {
    logger.error(`更新 agent 会话失败: ${ error.message }`)
    res.fail({ msg: '更新会话失败' })
  }
}

async function forkAgentSession({ res, request }) {
  const { params: { id } } = request
  const turnIndex = Number(request.body?.turnIndex)
  const messageIndex = request.body?.messageIndex === undefined
    ? undefined
    : Number(request.body.messageIndex)
  if (!id || !Number.isInteger(turnIndex) || turnIndex < 0) return res.fail({ msg: '参数错误' })
  if (messageIndex !== undefined && (!Number.isInteger(messageIndex) || messageIndex < 0)) {
    return res.fail({ msg: '参数错误' })
  }

  try {
    res.success({ data: await forkSession(id, turnIndex, messageIndex) })
  } catch (error) {
    logger.error(`分支 agent 会话失败: ${ error.message }`)
    res.fail({ msg: error.message || '创建分支会话失败' })
  }
}

async function removeAgentSession({ res, request }) {
  const { params: { id } } = request
  if (!id) return res.fail({ msg: '参数错误' })
  try {
    const removed = await removeSession(id)
    if (!removed) return res.fail({ msg: '会话不存在' })
    res.success({ data: true })
  } catch (error) {
    logger.error(`删除 agent 会话失败: ${ error.message }`)
    res.fail({ msg: '删除会话失败' })
  }
}

async function clearAgentSessions({ res, request }) {
  const { scope, hostId } = request.query || {}
  if (!['ops', 'terminal'].includes(scope)) return res.fail({ msg: '参数错误' })
  if (scope === 'terminal' && !hostId) return res.fail({ msg: '终端会话缺少主机标识' })
  try {
    const count = await removeSessions({ scope, hostId })
    res.success({ data: { count } })
  } catch (error) {
    logger.error(`清空 agent 会话失败: ${ error.message }`)
    res.fail({ msg: error.message || '清空会话失败' })
  }
}

async function editAgentSessionMessage({ res, request }) {
  const { params: { id } } = request
  const turnIndex = Number(request.params.turnIndex)
  const content = request.body?.content

  if (!id || !Number.isInteger(turnIndex) || turnIndex < 0 || typeof content !== 'string' || !content.trim()) {
    return res.fail({ msg: '参数错误' })
  }

  try {
    const session = await truncateForUserEdit(id, turnIndex, content)
    res.success({ data: session })
  } catch (error) {
    logger.error(`编辑 agent 会话消息失败: ${ error.message }`)
    res.fail({ msg: error.message || '编辑消息失败' })
  }
}

export {
  getAgentSessions,
  getAgentSessionDetail,
  updateAgentSession,
  forkAgentSession,
  removeAgentSession,
  clearAgentSessions,
  editAgentSessionMessage
}
