/**
 * 权限预设的前端兜底文案
 *
 * 真值在后端 app/ai/policy.js，socket 的 ready 事件会下发。这里只是
 * 在连接建立之前先有东西可渲染，避免首次打开面板时下拉框是空的。
 * 两边的 key 必须一致。
 */
export const DEFAULT_PRESET = 'review'

export const PRESET_FALLBACK = [
  { key: 'review', label: '审查', desc: '所有主机操作均需确认' },
  { key: 'assist', label: '协助', desc: '仅明确只读的操作自动执行，其他操作需确认' },
  { key: 'authorized', label: '授权', desc: '常规操作自动执行，需审查操作仍要确认' },
]
