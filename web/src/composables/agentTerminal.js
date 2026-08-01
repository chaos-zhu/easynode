/**
 * Agent 与 Web 终端之间的请求标识必须端到端保持一致。
 *
 * 允许注入 factory，方便在不依赖浏览器 crypto 的 Node 测试中验证回退路径。
 */
export function resolveTerminalRequestId(options = {}, factory = defaultRequestId) {
  const provided = String(options.requestId || '').trim()
  return provided || factory()
}

function defaultRequestId() {
  return globalThis.crypto?.randomUUID?.() || `${ Date.now() }-${ Math.random() }`
}
