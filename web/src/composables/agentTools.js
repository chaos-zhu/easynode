export function availableAgentTools(tools = [], options = {}) {
  const scope = options.scope === 'terminal' ? 'terminal' : 'ops'
  return tools.filter((tool) => {
    if (!tool?.name) return false
    if (Array.isArray(tool.scopes) && !tool.scopes.includes(scope)) return false
    if (!Array.isArray(tool.scopes)) {
      if (scope === 'terminal') return ['terminal_command', 'read_output',].includes(tool.name)
      if (tool.name === 'terminal_command') return false
    }
    const requiresSelectedHosts = tool.requiresSelectedHosts === undefined
      ? tool.source?.type !== 'mcp'
      : tool.requiresSelectedHosts
    if (scope === 'terminal' && requiresSelectedHosts && !options.hasSelectedHosts) return false
    return true
  })
}

export function agentToolAccessLabel(tool, plusAvailable = false) {
  if (tool?.source?.type === 'mcp') return 'MCP · 外部操作 · 免费'
  if (tool?.plusPolicy === 'required') return plusAvailable ? 'Plus' : '需要 Plus'
  if (tool?.plusPolicy === 'by-effect') return '只读免费 · 变更 Plus'
  return '免费只读'
}

export function agentToolAccessClass(tool) {
  if (tool?.source?.type === 'mcp') return 'is_mixed'
  if (tool?.plusPolicy === 'required') return 'is_plus'
  if (tool?.plusPolicy === 'by-effect') return 'is_mixed'
  return 'is_readonly'
}
