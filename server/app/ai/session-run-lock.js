/**
 * A session is server-owned history. Two sockets appending turns to the same
 * session concurrently can overwrite or interleave that history, so a turn
 * holds an exclusive lock until its final persistence step has completed.
 */
const owners = new Map()

export function claimSessionRun(sessionId, ownerId) {
  if (!sessionId || !ownerId) return false
  if (owners.has(sessionId)) return false
  owners.set(sessionId, ownerId)
  return true
}

export function releaseSessionRun(sessionId, ownerId) {
  if (owners.get(sessionId) !== ownerId) return false
  owners.delete(sessionId)
  return true
}

export function clearSessionRunLocks() {
  owners.clear()
}
