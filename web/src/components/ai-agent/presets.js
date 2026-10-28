/**
 * 权限预设的前端兜底文案
 *
 * 真值在后端 app/ai/policy.js，socket 的 ready 事件会下发。这里只是
 * 在连接建立之前先有东西可渲染，避免首次打开面板时下拉框是空的。
 * 两边的 key 必须一致。
 */
export const DEFAULT_PRESET = 'assist'

export const PRESET_FALLBACK = [
  { key: 'assist', label: '协助', desc: '可识别的只读操作放行，其他需确认' },
  { key: 'authorized', label: '授权', desc: '只读和可识别的编辑操作放行，其他需确认' },
  { key: 'full_access', label: '完全', desc: '仅拦截内置高危指令，其他指令一律放行' },
]

export function normalizeMode(mode) {
  return PRESET_FALLBACK.some(preset => preset.key === mode) ? mode : DEFAULT_PRESET
}
