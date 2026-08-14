export function normalizeAIConfig(config = {}) {
  const source = config || {}
  return {
    ...source,
    ui: {
      ...(source.ui || {}),
      petEnabled: source.ui?.petEnabled !== false,
      nativeAgentEnabled: source.ui?.nativeAgentEnabled !== false
    }
  }
}

export function mergeAIProviderConfig(existingConfig = {}, providerConfig = {}) {
  return normalizeAIConfig({
    ...providerConfig,
    ui: {
      ...(existingConfig?.ui || {}),
      ...(providerConfig.ui || {})
    }
  })
}

export function mergeAIPreferences(existingConfig = {}, preferences = {}) {
  const ui = { ...(existingConfig?.ui || {}) }
  if (typeof preferences.petEnabled === 'boolean') ui.petEnabled = preferences.petEnabled
  if (typeof preferences.nativeAgentEnabled === 'boolean') {
    ui.nativeAgentEnabled = preferences.nativeAgentEnabled
  }
  return ui
}
