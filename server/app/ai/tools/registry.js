import { TOOL_SPECS } from './spec.js'
import { EXECUTORS } from './executors.js'
import { loadMcpDefinitions } from '../mcp/registry.js'

const BUILTIN_LABELS = {
  host_metadata_batch_update: '批量修改主机元数据',
  script_get: '查看脚本',
  script_batch_create: '批量新建脚本',
  script_batch_update: '批量修改脚本',
  script_batch_delete: '批量删除脚本',
  script_group_batch_create: '批量新建脚本分组',
  script_group_batch_update: '批量重命名脚本分组',
  script_group_batch_delete: '批量删除脚本分组',
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

const HOST_ARGUMENT_TOOLS = new Set([
  'host_status', 'run_script', 'exec_command', 'read_file', 'write_file', 'list_dir', 'terminal_command'
])

function builtinDefinition(spec) {
  return {
    ...spec,
    displayName: BUILTIN_LABELS[spec.name] || spec.name,
    source: { type: 'builtin', name: 'EasyNode' },
    scopes: spec.name === 'terminal_command'
      ? ['terminal']
      : (spec.name === 'read_output' ? ['ops', 'terminal'] : ['ops']),
    requiresSelectedHosts: ['terminal_command', 'read_output'].includes(spec.name),
    hostArg: HOST_ARGUMENT_TOOLS.has(spec.name) ? 'hostId' : null,
    approvalPolicy: 'policy',
    execute: EXECUTORS[spec.name]
  }
}

export const BUILTIN_TOOL_DEFINITIONS = TOOL_SPECS
  .map(builtinDefinition)
  .filter((definition) => typeof definition.execute === 'function')

export function isToolAvailable(definition, ctx) {
  const scope = ctx.scope || 'ops'
  if (!definition.scopes.includes(scope)) return false
  if (scope === 'terminal' && definition.requiresSelectedHosts && !(ctx.allowedHostIds instanceof Set && ctx.allowedHostIds.size > 0)) return false
  return true
}

export async function loadToolDefinitions(ctx) {
  const names = new Set()
  return [...BUILTIN_TOOL_DEFINITIONS, ...await loadMcpDefinitions()].filter((definition) => {
    if (!isToolAvailable(definition, ctx) || names.has(definition.name)) return false
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
