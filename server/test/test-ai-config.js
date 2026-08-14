import {
  mergeAIProviderConfig,
  mergeAIPreferences,
  normalizeAIConfig
} from '../app/ai/config.js'

let passed = 0
let failed = 0
const failures = []

function expect(label, actual, expected) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    passed += 1
    return
  }
  failed += 1
  failures.push(`${ label }\n  期望: ${ JSON.stringify(expected) }\n  实际: ${ JSON.stringify(actual) }`)
}

expect('旧配置默认显示宠物入口', normalizeAIConfig({}).ui.petEnabled, true)
expect('旧配置默认显示 Native 助手入口', normalizeAIConfig({}).ui.nativeAgentEnabled, true)
expect('保留已关闭的宠物入口状态', normalizeAIConfig({ ui: { petEnabled: false } }).ui.petEnabled, false)
expect(
  '保留已关闭的 Native 助手入口状态',
  normalizeAIConfig({ ui: { nativeAgentEnabled: false } }).ui.nativeAgentEnabled,
  false
)
expect(
  '保存 Provider 时保留界面偏好',
  mergeAIProviderConfig(
    { apiUrl: 'old', ui: { petEnabled: false, nativeAgentEnabled: false, theme: 'robot' } },
    { apiUrl: 'new', apiKey: 'key', models: ['model'] }
  ),
  {
    apiUrl: 'new',
    apiKey: 'key',
    models: ['model'],
    ui: { petEnabled: false, nativeAgentEnabled: false, theme: 'robot' }
  }
)
expect(
  '更新宠物入口状态不丢失其他界面偏好',
  mergeAIPreferences({ ui: { petEnabled: true, theme: 'robot' } }, { petEnabled: false }),
  { petEnabled: false, theme: 'robot' }
)
expect(
  '更新 Native 入口状态不覆盖 Web 入口',
  mergeAIPreferences(
    { ui: { petEnabled: false, nativeAgentEnabled: true, theme: 'robot' } },
    { nativeAgentEnabled: false }
  ),
  { petEnabled: false, nativeAgentEnabled: false, theme: 'robot' }
)

if (failures.length) {
  console.error(`\n❌ AI 配置测试失败 (${ failed } 项)\n${ failures.join('\n') }`)
  process.exit(1)
}

console.log(`\n✅ AI 配置测试全部通过 (${ passed } 项)`)
