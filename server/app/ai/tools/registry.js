import { TOOL_SPECS } from './spec.js'
import { EXECUTORS } from './executors.js'
import { loadMcpDefinitions } from '../mcp/registry.js'

const BUILTIN_LABELS = {
  host_list: '查询主机列表',
  host_status: '获取主机状态',
  script_list: '查询脚本库',
  run_script: '运行脚本',
  scheduled_task_list: '查询定时任务',
  scheduled_task_get: '查看定时任务',
  scheduled_task_create: '创建定时任务',
  scheduled_task_update: '修改定时任务',
  scheduled_task_delete: '删除定时任务',
  exec_command: '执行命令',
  terminal_command: '提交终端命令',
  read_file: '读取文件',
  write_file: '写入文件',
  list_dir: '列出目录',
  read_output: '回读输出'
}

const SELECTED_HOST_TOOLS = new Set([
  'host_list', 'host_status', 'script_list', 'run_script', 'exec_command', 'read_file', 'write_file', 'list_dir',
  'read_output', 'terminal_command'
])

function builtinDefinition(spec) {
  return {
    ...spec,
    displayName: BUILTIN_LABELS[spec.name] || spec.name,
    source: { type: 'builtin', name: 'EasyNode' },
    scopes: spec.name === 'terminal_command'
      ? ['terminal']
      : (spec.name === 'read_output' ? ['ops', 'terminal'] : ['ops']),
    requiresSelectedHosts: SELECTED_HOST_TOOLS.has(spec.name),
    hostArg: SELECTED_HOST_TOOLS.has(spec.name) ? 'hostId' : null,
    approvalPolicy: 'policy',
    execute: EXECUTORS[spec.name]
  }
}

export const BUILTIN_TOOL_DEFINITIONS = TOOL_SPECS
  .map(builtinDefinition)
  .filter((definition) => typeof definition.execute === 'function')

function isAvailable(definition, ctx) {
  if (!definition.scopes.includes(ctx.scope)) return false
  if (definition.requiresSelectedHosts && !(ctx.allowedHostIds instanceof Set && ctx.allowedHostIds.size > 0)) return false
  return true
}

export async function loadToolDefinitions(ctx) {
  const names = new Set()
  return [...BUILTIN_TOOL_DEFINITIONS, ...await loadMcpDefinitions()].filter((definition) => {
    if (!isAvailable(definition, ctx) || names.has(definition.name)) return false
    names.add(definition.name)
    return true
  })
}

export function publicToolMetadata(definition) {
  return {
    name: definition.name,
    displayName: definition.displayName,
    source: definition.source,
    scopes: definition.scopes,
    requiresSelectedHosts: definition.requiresSelectedHosts,
    effect: definition.effect,
    plusPolicy: definition.plusPolicy,
    approvalPolicy: definition.approvalPolicy,
    description: definition.description
  }
}

export async function listToolMetadata() {
  return [...BUILTIN_TOOL_DEFINITIONS, ...await loadMcpDefinitions()].map(publicToolMetadata)
}

export function toolInfo(definition) {
  if (!definition) return undefined
  return {
    displayName: definition.displayName,
    source: definition.source?.type,
    providerId: definition.source?.id,
    providerName: definition.source?.name,
    remoteName: definition.source?.remoteName
  }
}
