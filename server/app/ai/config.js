export function normalizeAIConfig(config = {}) {
  const source = config || {}
  return {
    ...source,
    ui: {
      ...(source.ui || {}),
      petEnabled: source.ui?.petEnabled !== false
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
  return {
    ...(existingConfig?.ui || {}),
    petEnabled: preferences.petEnabled
  }
}
