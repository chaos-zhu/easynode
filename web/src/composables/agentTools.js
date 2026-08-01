export function availableAgentTools(tools = [], options = {}) {
  const scope = options.scope === 'terminal' ? 'terminal' : 'ops'
  if (scope === 'terminal') {
    return tools.filter((tool) => ['terminal_command', 'read_output',].includes(tool.name))
  }
  if (!options.hasSelectedHosts) return []

  return tools.filter((tool) => {
    if (!tool?.name || tool.name === 'terminal_command') return false
    return true
  })
}

export function agentToolAccessLabel(tool, plusAvailable = false) {
  if (tool?.plusPolicy === 'required') return plusAvailable ? 'Plus' : '需要 Plus'
  if (tool?.plusPolicy === 'by-effect') return '只读免费 · 变更 Plus'
  return '免费只读'
}

export function agentToolAccessClass(tool) {
  if (tool?.plusPolicy === 'required') return 'is_plus'
  if (tool?.plusPolicy === 'by-effect') return 'is_mixed'
  return 'is_readonly'
}
