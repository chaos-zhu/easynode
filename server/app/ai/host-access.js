/** 目标主机授权与主机级策略的唯一执行入口。 */

import { HostListDB } from '../utils/db-class.js'
import { isEffectAllowed, resolveEffectivePolicy } from './policy.js'

const hostListDB = new HostListDB().getInstance()

export class HostAccessError extends Error {}

export async function resolveHostAccess(hostId, ctx, effect) {
  if (!hostId) throw new HostAccessError('缺少 hostId，请先调用 host_list 获取')
  if (!(ctx.allowedHostIds instanceof Set) || !ctx.allowedHostIds.has(hostId)) {
    throw new HostAccessError('当前会话未授权访问该主机，请先选择目标主机')
  }

  const host = await hostListDB.findOneAsync({ _id: hostId })
  if (!host) throw new HostAccessError(`未找到主机 ${ hostId }`)

  const policy = resolveEffectivePolicy(ctx.sessionMode, host.aiPolicy)
  if (!policy.enabled) throw new HostAccessError(`主机「${ host.name }」已禁止 AI 操作`)
  if (effect && !isEffectAllowed(effect, policy.maxEffect)) {
    throw new HostAccessError(`主机「${ host.name }」仅允许 AI 读取，不能执行${ effect === 'delete' ? '删除' : '写入' }操作`)
  }

  return { host, policy }
}

export function buildAllowedHostIds(hostIds) {
  return new Set(Array.isArray(hostIds) ? hostIds : [])
}
