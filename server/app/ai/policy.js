/**
 * Agent 执行策略。
 *
 * 会话模式只决定自动执行的范围；主机策略可以进一步限制可写能力和最高权限模式。
 * 命令本身的 effect/risk 由 safety.js 统一分类。
 */

export const Mode = {
  ASSIST: 'assist',
  AUTHORIZED: 'authorized',
  FULL_ACCESS: 'full_access'
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

const MODE_ORDER = [Mode.ASSIST, Mode.AUTHORIZED, Mode.FULL_ACCESS]

export const PRESETS = {
  assist: {
    key: Mode.ASSIST,
    label: '协助',
    desc: '可识别的只读操作放行，其他需确认'
  },
  authorized: {
    key: Mode.AUTHORIZED,
    label: '授权',
    desc: '只读和可识别的编辑操作放行，其他需确认'
  },
  full_access: {
    key: Mode.FULL_ACCESS,
    label: '完全',
    desc: '仅拦截内置高危指令，其他指令一律放行'
  }
}

export const DEFAULT_PRESET = Mode.ASSIST

export const DEFAULT_HOST_POLICY = {
  enabled: true,
  maxEffect: Effect.WRITE,
  maxMode: Mode.FULL_ACCESS
}

function modeRank(mode) {
  const index = MODE_ORDER.indexOf(mode)
  return index === -1 ? 0 : index
}

export function normalizeMode(mode) {
  // 旧 review 和未知模式统一回退到协助，不改写历史数据库。
  return MODE_ORDER.includes(mode) ? mode : DEFAULT_PRESET
}

export function normalizeHostPolicy(policy) {
  const host = { ...DEFAULT_HOST_POLICY, ...(policy || {}) }
  return {
    enabled: host.enabled !== false,
    maxEffect: host.maxEffect === Effect.READ ? Effect.READ : Effect.WRITE,
    maxMode: normalizeMode(host.maxMode ?? DEFAULT_HOST_POLICY.maxMode)
  }
}

export function resolveEffectivePolicy(sessionMode, hostPolicy) {
  const requestedMode = normalizeMode(sessionMode)
  const host = normalizeHostPolicy(hostPolicy)
  const hostMode = host.maxMode
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

export function strongerEffect(...effects) {
  if (effects.includes(Effect.DELETE)) return Effect.DELETE
  if (effects.includes(Effect.WRITE)) return Effect.WRITE
  return Effect.READ
}

/**
 * 永久拒绝由运行时先行拦截，此处只决定是否请求人工审批。
 * @param {{ mode: string, effect: string, risk: string, approvalPolicy?: string }} operation
 */
export function needsApproval(operation) {
  const { effect, risk, approvalPolicy } = operation
  const mode = normalizeMode(operation.mode)
  if (risk === Risk.DENY) return false
  if (mode === Mode.FULL_ACCESS) return false
  if (approvalPolicy === 'always') return true
  if (risk === Risk.HIGH) return true
  if (mode === Mode.ASSIST) return effect !== Effect.READ
  return false
}
