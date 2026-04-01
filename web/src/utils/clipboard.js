/**
 * 通用剪贴板工具
 * - HTTPS环境: 使用 navigator.clipboard API
 * - HTTP环境: 降级到 document.execCommand (兼容内网部署)
 */

import { ElMessage, ElMessageBox } from 'element-plus'
import i18n from '@/i18n'

const { t } = i18n.global

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
    console.error('Copy failed:', err)
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
    if (showMessage) ElMessage.warning(t('common.emptyCopyContent'))
    return false
  }

  let success = false

  // 优先尝试现代API (HTTPS环境)
  if (isModernAPISupported()) {
    try {
      await navigator.clipboard.writeText(text)
      success = true
    } catch (err) {
      console.warn('Modern clipboard API copy failed, falling back to legacy method:', err)
      success = copyWithLegacyAPI(text)
    }
  } else {
    // HTTP环境使用传统方法
    success = copyWithLegacyAPI(text)
  }

  if (showMessage) {
    success ? ElMessage.success(t('common.copySuccess')) : ElMessage.error(t('common.copyFailed'))
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
    ElMessageBox.confirm(t('common.clipboardReadRequiresHttps'), t('settings.common.tip'), {
      confirmButtonText: t('common.gotIt'),
      showCancelButton: false,
      type: 'warning',
      dangerouslyUseHTMLString: true
    }).catch(() => {})
    const errorMsg = t('common.httpClipboardReadUnsupported')
    throw new Error(errorMsg)
  }

  try {
    const text = await navigator.clipboard.readText()
    return text
  } catch (err) {
    if (showMessage) ElMessage.error(t('common.readClipboardFailed'))
    throw err
  }
}

// 默认导出
export default {
  copy: copyText,
  paste: pasteText
}
