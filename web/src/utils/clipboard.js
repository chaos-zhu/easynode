/**
 * 通用剪贴板工具
 * - HTTPS环境: 使用 navigator.clipboard API
 * - HTTP环境: 降级到 document.execCommand (兼容内网部署)
 */

import { ElMessage, ElMessageBox } from 'element-plus'

/**
 * 检测是否支持现代剪贴板API
 */
function isModernAPISupported() {
  return !!(navigator.clipboard && window.isSecureContext)
}

/**
 * 使用传统方法复制文本 (HTTP环境兼容)
 */
function copyWithLegacyAPI(text) {
  const textarea = document.createElement('textarea')
  textarea.value = text
  textarea.style.position = 'fixed'
  textarea.style.left = '-9999px'
  textarea.style.opacity = '0'
  textarea.setAttribute('readonly', '')

  document.body.appendChild(textarea)

  try {
    textarea.select()
    textarea.setSelectionRange(0, textarea.value.length)
    const successful = document.execCommand('copy')
    return successful
  } catch (err) {
    console.error('复制失败:', err)
    return false
  } finally {
    document.body.removeChild(textarea)
  }
}

/**
 * 复制文本到剪贴板
 * @param {string} text - 要复制的文本
 * @param {boolean} showMessage - 是否显示提示消息,默认true
 * @returns {Promise<boolean>} 是否成功
 */
export async function copyText(text, showMessage = true) {
  if (!text) {
    if (showMessage) ElMessage.warning('复制内容为空')
    return false
  }

  let success = false

  // 优先尝试现代API (HTTPS环境)
  if (isModernAPISupported()) {
    try {
      await navigator.clipboard.writeText(text)
      success = true
    } catch (err) {
      console.warn('现代API复制失败,降级到传统方法:', err)
      success = copyWithLegacyAPI(text)
    }
  } else {
    // HTTP环境使用传统方法
    success = copyWithLegacyAPI(text)
  }

  if (showMessage) {
    success ? ElMessage.success('复制成功') : ElMessage.error('复制失败')
  }

  return success
}

/**
 * 从剪贴板读取文本
 * 注意: HTTP环境下无法读取剪贴板
 * @param {boolean} showMessage - 是否显示提示消息,默认false
 * @returns {Promise<string>} 剪贴板文本
 */
export async function pasteText(showMessage = false) {
  if (!isModernAPISupported()) {
    ElMessageBox.confirm('浏览器安全限制,不支持剪贴板读取，需配置https', '提示', {
      confirmButtonText: '好的',
      showCancelButton: false,
      type: 'warning',
      dangerouslyUseHTMLString: true
    }).catch(() => {})
    const errorMsg = 'HTTP环境不支持读取剪贴板,请使用 Ctrl+V 或右键粘贴'
    throw new Error(errorMsg)
  }

  try {
    const text = await navigator.clipboard.readText()
    return text
  } catch (err) {
    if (showMessage) ElMessage.error('读取剪贴板失败')
    throw err
  }
}

// 默认导出
export default {
  copy: copyText,
  paste: pasteText
}
