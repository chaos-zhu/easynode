/**
 * 把 spec 表装配成 AI SDK 的 tools
 *
 * 会话模式不裁剪工具；审批与主机限制在每次调用时按实际操作判定。
 */

import { tool } from 'ai'
import { TOOL_SPECS, getToolSpec } from './spec.js'
import { EXECUTORS } from './executors.js'
import { redactDeep } from '../redact.js'

function hasSelectedHosts(ctx) {
  return ctx.allowedHostIds instanceof Set && ctx.allowedHostIds.size > 0
}

/**
 * @param {object} ctx
 * @param {object} ctx.policy 生效策略 { mode, maxEffect }
 * @param {string} ctx.sessionId
 * @param {string} [ctx.userId]
 * @param {AbortSignal} [ctx.signal]
 * @param {(event: object) => void} [ctx.onToolEvent] 工具开始/结束时的回调，用于推事件给前端
 */
export function buildTools(ctx) {
  if (ctx.scope === 'terminal') {
    const names = ['terminal_command', 'read_output']
    return Object.fromEntries(names.map((name) => {
      const spec = getToolSpec(name)
      const executor = EXECUTORS[name]
      if (!spec || !executor) return null
      return [name, tool({
        description: spec.description,
        inputSchema: spec.inputSchema,
        execute: async (input, options) => runTool(spec, executor, ctx, input, options)
      })]
    }).filter(Boolean))
  }

  // AI 助手未选择主机时是纯聊天模式。不能仅在 executor 里拒绝：
  // 那样模型仍可通过 host_list 枚举资产，并反复尝试越权工具调用。
  if (!hasSelectedHosts(ctx)) return {}

  const available = TOOL_SPECS.filter((spec) => spec.name !== 'terminal_command')

  const tools = {}

  for (const spec of available) {
    const executor = EXECUTORS[spec.name]
    if (!executor) continue

    tools[spec.name] = tool({
      description: spec.description,
      inputSchema: spec.inputSchema,
      execute: async (input, options) => runTool(spec, executor, ctx, input, options)
    })
  }

  return tools
}

async function runTool(spec, executor, ctx, input, options) {
  const startedAt = Date.now()
  const toolCallId = options?.toolCallId
  const allowSensitiveOutput = Boolean(toolCallId && ctx.sensitiveOutputs?.has(toolCallId))

  try {
    const result = await executor(ctx, input, { toolCallId, allowSensitiveOutput })

    if (!result?.ok) {
      const error = result?.error || '工具执行失败'
      ctx.onToolEvent?.({ toolCallId, tool: spec.name, phase: 'error', error, durationMs: Date.now() - startedAt })
      // 以数据形式回传错误而不是抛异常：模型看到明确的失败原因才能自行纠正
      return { error, ...(result?.code ? { code: result.code } : {}) }
    }

    const { data, redacted } = allowSensitiveOutput
      ? { data: result.data, redacted: false }
      : redactDeep(result.data)
    ctx.onToolEvent?.({ toolCallId, tool: spec.name, phase: 'done', durationMs: Date.now() - startedAt })

    if (redacted) {
      return { ...data, _notice: '输出中的凭据类内容已脱敏，如需核对请让用户自行在终端查看' }
    }
    return data
  } catch (error) {
    const message = error?.message || String(error)
    ctx.onToolEvent?.({ toolCallId, tool: spec.name, phase: 'error', error: message, durationMs: Date.now() - startedAt })
    return { error: message }
  } finally {
    if (toolCallId) ctx.sensitiveOutputs?.delete(toolCallId)
  }
}

/** 供 prompt 组装使用：列出当前档位下可用的工具名与说明 */
export function describeAvailableTools(ctx) {
  if (ctx.scope === 'terminal') {
    return ['terminal_command', 'read_output']
      .map((name) => getToolSpec(name))
      .filter(Boolean)
      .map((spec) => `- \`${ spec.name }\`：${ spec.description }`)
      .join('\n')
  }
  if (!hasSelectedHosts(ctx)) {
    return '- 当前未选择目标主机，处于纯聊天模式，不能读取、枚举或操作任何主机。'
  }
  return TOOL_SPECS
    .filter((spec) => spec.name !== 'terminal_command')
    .map((spec) => `- \`${ spec.name }\`：${ spec.description }`)
    .join('\n')
}

export { getToolSpec, TOOL_SPECS }
