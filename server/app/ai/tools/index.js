/** 把统一 ToolDefinition 注册表装配成 AI SDK tools。 */

import { dynamicTool, jsonSchema, tool } from 'ai'
import { redactDeep } from '../redact.js'
import { BUILTIN_TOOL_DEFINITIONS, toolInfo } from './registry.js'

export function buildTools(ctx, definitions) {
  const selectedHosts = ctx.allowedHostIds instanceof Set && ctx.allowedHostIds.size > 0
  const available = (definitions || BUILTIN_TOOL_DEFINITIONS).filter((definition) => (
    definition.scopes.includes(ctx.scope || 'ops')
    && (!definition.requiresSelectedHosts || selectedHosts)
  ))
  return Object.fromEntries(available.map((definition) => {
    const config = {
      description: definition.description,
      inputSchema: definition.source?.type === 'mcp'
        ? jsonSchema(definition.inputSchema)
        : definition.inputSchema,
      execute: async (input, options) => runTool(definition, ctx, input, options)
    }
    return [definition.name, definition.source?.type === 'mcp' ? dynamicTool(config) : tool(config)]
  }))
}

async function runTool(definition, ctx, input, options) {
  const startedAt = Date.now()
  const toolCallId = options?.toolCallId
  const allowSensitiveOutput = Boolean(toolCallId && ctx.sensitiveOutputs?.has(toolCallId))
  const info = toolInfo(definition)

  try {
    const result = await definition.execute(ctx, input, { toolCallId, allowSensitiveOutput })
    if (!result?.ok) {
      const error = result?.error || '工具执行失败'
      ctx.onToolEvent?.({ toolCallId, tool: definition.name, toolInfo: info, phase: 'error', error,
        durationMs: Date.now() - startedAt })
      return { error, ...(result?.code ? { code: result.code } : {}) }
    }

    const { data, redacted } = allowSensitiveOutput
      ? { data: result.data, redacted: false }
      : redactDeep(result.data)
    ctx.onToolEvent?.({ toolCallId, tool: definition.name, toolInfo: info, phase: 'done',
      durationMs: Date.now() - startedAt })

    if (redacted && data && typeof data === 'object' && !Array.isArray(data)) {
      return { ...data, _notice: '输出中的凭据类内容已脱敏，如需核对请让用户自行在终端查看' }
    }
    return data
  } catch (error) {
    const message = error?.message || String(error)
    ctx.onToolEvent?.({ toolCallId, tool: definition.name, toolInfo: info, phase: 'error', error: message,
      durationMs: Date.now() - startedAt })
    return { error: message }
  } finally {
    if (toolCallId) ctx.sensitiveOutputs?.delete(toolCallId)
  }
}

export function describeAvailableTools(ctx) {
  const selectedHosts = ctx.allowedHostIds instanceof Set && ctx.allowedHostIds.size > 0
  const definitions = ctx.toolDefinitions || BUILTIN_TOOL_DEFINITIONS.filter((definition) => (
    definition.scopes.includes(ctx.scope || 'ops')
    && (!definition.requiresSelectedHosts || selectedHosts)
  ))
  const lines = definitions.map((definition) => {
    const provider = definition.source?.type === 'mcp' ? `（MCP：${ definition.source.name }）` : ''
    return `- \`${ definition.name }\`${ provider }：${ definition.description }`
  })
  if (!ctx.allowedHostIds?.size && ctx.scope !== 'terminal') {
    lines.unshift('- 当前未选择目标主机，不能直接读取、枚举或操作 EasyNode 主机；面板级定时任务工具和不依赖目标主机的 MCP 工具仍可使用。')
  }
  return lines.join('\n') || '- 当前没有可用工具。'
}

export { getToolSpec, TOOL_SPECS } from './spec.js'
