/**
 * Agent 执行策略。
 *
 * 会话模式只决定自动执行的范围；主机策略可以进一步限制可写能力和最高权限模式。
 * 命令本身的 effect/risk 由 safety.js 统一分类。
 */

export const Mode = {
  REVIEW: 'review',
  ASSIST: 'assist',
  AUTHORIZED: 'authorized'
}

export const Effect = {
  READ: 'read',
  WRITE: 'write',
  DELETE: 'delete'
}

export const Risk = {
  NORMAL: 'normal',
  HIGH: 'high',
  DENY: 'deny'
}

const MODE_ORDER = [Mode.REVIEW, Mode.ASSIST, Mode.AUTHORIZED]

export const PRESETS = {
  review: {
    key: Mode.REVIEW,
    label: '审查',
    desc: '所有主机操作均需确认'
  },
  assist: {
    key: Mode.ASSIST,
    label: '协助',
    desc: '仅明确只读的操作自动执行，其他操作需确认'
  },
  authorized: {
    key: Mode.AUTHORIZED,
    label: '授权',
    desc: '常规操作自动执行，需审查操作仍要确认'
  }
}

export const DEFAULT_PRESET = Mode.REVIEW

export const DEFAULT_HOST_POLICY = {
  enabled: true,
  maxEffect: Effect.WRITE,
  maxMode: Mode.AUTHORIZED
}

function modeRank(mode) {
  const index = MODE_ORDER.indexOf(mode)
  return index === -1 ? 0 : index
}

export function normalizeMode(mode) {
  return MODE_ORDER.includes(mode) ? mode : DEFAULT_PRESET
}

export function resolveEffectivePolicy(sessionMode, hostPolicy) {
  const requestedMode = normalizeMode(sessionMode)
  const host = { ...DEFAULT_HOST_POLICY, ...(hostPolicy || {}) }
  const hostMode = normalizeMode(host.maxMode)
  const mode = modeRank(requestedMode) <= modeRank(hostMode) ? requestedMode : hostMode
  const maxEffect = host.maxEffect === Effect.READ ? Effect.READ : Effect.WRITE

  return {
    enabled: host.enabled !== false,
    mode,
    maxEffect,
    preset: mode,
    clamped: {
      mode: mode !== requestedMode,
      effect: maxEffect === Effect.READ
    }
  }
}

export function isEffectAllowed(effect, maxEffect) {
  if (effect === Effect.READ) return true
  return maxEffect === Effect.WRITE
}

/**
 * @param {{ mode: string, effect: string, risk: string, hostOperation?: boolean }} operation
 */
export function needsApproval(operation) {
  const { mode, effect, risk, hostOperation = false } = operation
  if (risk === Risk.HIGH) return true
  if (mode === Mode.REVIEW) return hostOperation || effect !== Effect.READ
  if (mode === Mode.ASSIST) return effect !== Effect.READ
  return false
}
