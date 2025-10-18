<template>
  <el-dialog
    v-model="visible"
    :width="dialogWidth"
    center
    modal-penetrable
    :modal="true"
    :align-center="true"
    :show-close="false"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :fullscreen="fullscreen"
    class="rdp_content"
    header-class="rdp_header"
    body-class="rdp_body"
    @close="handleClose"
  >
    <template #header>
      <div class="rdp_dialog_header">
        <div class="rdp_left">
          <div class="host_info">
            <span v-show="!isMobile()" class="hostname">{{ name }}</span>
            <div class="status_info">
              <el-icon :color="currentStatusInfo.color" class="status_icon">
                <Connection v-if="currentStatus === rdpStatus.CONNECTED" />
                <Loading v-else-if="isConnecting" />
                <Close v-else-if="isError" />
                <Clock v-else />
              </el-icon>
              <span class="status_text" :style="{ color: currentStatusInfo.color }">
                {{ currentStatusInfo.label }}
              </span>
            </div>
          </div>
        </div>

        <div class="rdp_center">
          <div class="resolution_controls">
            <el-select
              v-model="displayMode"
              class="display_mode_select"
              size="small"
              :disabled="isConnecting"
              placeholder="选择显示模式"
              @change="handleDisplayModeChange"
            >
              <el-option label="最大化" value="maximize" />
              <el-option label="自适应" value="adaptive" />
              <el-option label="自定义" value="custom" @click="handleCustomOptionClick" />
            </el-select>
          </div>
        </div>

        <div class="rdp_right">
          <el-button
            type="primary"
            size="small"
            :disabled="isConnecting"
            :loading="isConnecting"
            @click="connectRdp"
          >
            {{ isConnecting ? '连接中' : '重连' }}
          </el-button>
          <el-button type="info" size="small" @click="moveToBackground"> 挂起 </el-button>
          <el-button
            v-show="isMobile()"
            type="success"
            size="small"
            @click="toggleKeyboard"
          >
            键盘
          </el-button>
        </div>
      </div>
    </template>
    <div
      ref="rdpContainer"
      v-loading="isConnecting"
      element-loading-text="连接中..."
      class="rdp_container"
    />
  </el-dialog>

  <!-- 自定义分辨率设置对话框 -->
  <el-dialog
    v-model="customDialogVisible"
    title="自定义分辨率"
    width="400px"
    :close-on-click-modal="false"
  >
    <el-form label-width="60px">
      <el-form-item label="宽度">
        <el-input
          v-model="tempCustomWidth"
          type="number"
          :max="maxWidth"
          :placeholder="`最大${maxWidth}`"
        >
          <template #append>px</template>
        </el-input>
      </el-form-item>
      <el-form-item label="高度">
        <el-input
          v-model="tempCustomHeight"
          type="number"
          :max="maxHeight"
          :placeholder="`最大${maxHeight}`"
        >
          <template #append>px</template>
        </el-input>
      </el-form-item>
      <el-alert type="info" :closable="false">
        <template #default>
          <div style="display: flex; align-items: center; gap: 8px;">
            <span>最大可用分辨率:</span>
            <el-link
              type="primary"
              :underline="false"
              style="font-weight: 600;"
              @click="applyMaxResolution"
            >
              {{ maxWidth }}x{{ maxHeight }}
            </el-link>
          </div>
        </template>
      </el-alert>
    </el-form>
    <template #footer>
      <el-button @click="cancelCustomSettings">取消</el-button>
      <el-button type="primary" @click="confirmCustomSettings">确定</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance, onBeforeUnmount, watch } from 'vue'
import { Connection, Loading, Close, Clock } from '@element-plus/icons-vue'
import Guacamole from 'guacamole-common-js'
import { rdpStatus, rdpStatusList } from '@/utils/enum'
import { isMobile } from '@/utils'

const { proxy: { $api, $message, $isDev } } = getCurrentInstance()
const props = defineProps({
  host: {
    type: Object,
    required: true
  }
})

const emit = defineEmits(['close:dialog', 'status:change',])

const rdpContainer = ref(null)
let client = ref(null)
let mouse
let touch
let keyboard

const host = computed(() => props.host)
const hostId = computed(() => props.host.id)
const name = computed(() => host.value.name)
const show = computed(() => host.value.show)
const fullscreen = computed(() => host.value.fullscreen || false)

// 从localStorage获取缓存的显示配置
const getCachedDisplayConfig = () => {
  const cached = localStorage.getItem('rdp_display_config')
  if (cached) {
    try {
      return JSON.parse(cached)
    } catch (error) {
      console.warn('解析缓存的显示配置失败:', error)
    }
  }
  // 默认返回自适应模式
  return {
    mode: 'adaptive',
    customWidth: '1366',
    customHeight: '768'
  }
}

// 显示模式：maximize(最大化)、adaptive(自适应)、custom(自定义)
const displayMode = ref(isMobile() ? 'maximize' : 'adaptive')

// 自定义宽高
const customWidth = ref('1366')
const customHeight = ref('768')

// 自定义设置对话框
const customDialogVisible = ref(false)
const tempCustomWidth = ref('1366')
const tempCustomHeight = ref('768')

// 初始化显示配置
const initDisplayConfig = () => {
  const config = getCachedDisplayConfig()
  displayMode.value = config.mode || (isMobile() ? 'maximize' : 'adaptive')
  customWidth.value = config.customWidth || '1366'
  customHeight.value = config.customHeight || '768'
}

initDisplayConfig()

// 实际应用的配置
const appliedConfig = ref({
  width: '1366',
  height: '768'
})

// 浏览器可视区域限制
const maxWidth = computed(() => Math.floor(window.innerWidth))
const maxHeight = computed(() => Math.floor(window.innerHeight - 46)) // 减去header的高度

const tunnel = ref(null)
const display = ref(null)
const currentStatus = ref(rdpStatus.IDLE)
const connectionTimeout = ref(null)

const visible = computed(() => show.value)

// 保存显示配置到localStorage
const saveDisplayConfigToCache = () => {
  const config = {
    mode: displayMode.value,
    customWidth: customWidth.value,
    customHeight: customHeight.value
  }
  localStorage.setItem('rdp_display_config', JSON.stringify(config))
}

// 根据显示模式计算实际宽高
const calculateResolution = () => {
  const maxW = maxWidth.value
  const maxH = maxHeight.value

  let width, height

  switch (displayMode.value) {
    case 'maximize':
      // 最大化：使用最大可用空间
      width = maxW
      height = maxH
      break
    case 'adaptive':
      // 自适应：宽80%，高90%
      width = Math.floor(maxW * 0.8)
      height = Math.floor(maxH * 0.9)
      break
    case 'custom':
      // 自定义：使用用户设置的值
      width = parseInt(customWidth.value) || 1366
      height = parseInt(customHeight.value) || 768
      // 确保不超过最大值
      width = Math.min(width, maxW)
      height = Math.min(height, maxH)
      break
    default:
      width = 1366
      height = 768
  }

  return { width, height }
}

// 显示模式变化处理
const handleDisplayModeChange = (mode) => {
  if (mode === 'custom') {
    // 打开自定义设置对话框
    openCustomDialog()
  } else {
    // 直接重连
    saveDisplayConfigToCache()
    connectRdp()
  }
}

// 处理自定义选项点击（包括重复点击）
const handleCustomOptionClick = () => {
  if (displayMode.value === 'custom') {
    // 如果已经是自定义模式，直接打开对话框
    openCustomDialog()
  }
}

// 打开自定义设置对话框
const openCustomDialog = () => {
  tempCustomWidth.value = customWidth.value
  tempCustomHeight.value = customHeight.value
  customDialogVisible.value = true
}

// 应用最大分辨率
const applyMaxResolution = () => {
  tempCustomWidth.value = maxWidth.value.toString()
  tempCustomHeight.value = maxHeight.value.toString()
}

// 确认自定义设置
const confirmCustomSettings = () => {
  customWidth.value = tempCustomWidth.value
  customHeight.value = tempCustomHeight.value
  customDialogVisible.value = false
  saveDisplayConfigToCache()
  connectRdp()
}

// 取消自定义设置
const cancelCustomSettings = () => {
  // 恢复到上次的模式
  const lastConfig = getCachedDisplayConfig()
  displayMode.value = lastConfig.mode === 'custom' ? 'adaptive' : (isMobile() ? 'maximize' : 'adaptive')
  customDialogVisible.value = false
}

// 计算dialog的宽度和高度（基于实际应用的配置）
const dialogWidth = computed(() => {
  const rdpWidth = parseInt(appliedConfig.value.width) || 1366
  // 考虑dialog的padding和边框，增加最小的必要空间
  return rdpWidth + 'px'
})

const dialogBodyHeight = computed(() => {
  const rdpHeight = parseInt(appliedConfig.value.height) || 768
  return rdpHeight + 'px' // 为header和padding留出空间
})

// 状态相关计算属性
const currentStatusInfo = computed(() => {
  return rdpStatusList.find(item => item.value === currentStatus.value) || rdpStatusList[0]
})

const isConnecting = computed(() => {
  return [rdpStatus.CONNECTING, rdpStatus.WAITING,].includes(currentStatus.value)
})

const isError = computed(() => {
  return [rdpStatus.ERROR, rdpStatus.TIMEOUT, rdpStatus.DISCONNECTED,].includes(currentStatus.value)
})

// const canDisconnect = computed(() => {
//   return [rdpStatus.CONNECTED, rdpStatus.CONNECTING, rdpStatus.WAITING,].includes(currentStatus.value)
// })

// 监听dialog显示状态，首次打开自动连接
watch(visible, (newVisible) => {
  if (newVisible && (currentStatus.value === rdpStatus.IDLE || currentStatus.value === rdpStatus.DISCONNECTED)) {
    // dialog打开时自动连接
    setTimeout(() => {
      connectRdp()
    }, 200) // 稍微延迟以确保DOM已渲染
  }
}, { immediate: true })

// 监听状态变化并发射事件给父组件
watch(currentStatus, (newStatus) => {
  emit('status:change', newStatus)
}, { immediate: true })

const handleClose = () => {
  emit('close:dialog')
}

const moveToBackground = () => {
  emit('close:dialog')
}

const getRdpWsUrl = async () => {
  const { width, height } = appliedConfig.value
  const { data } = await $api.getRdpToken({ hostId: hostId.value, width, height })
  if (!data) return $message.error('获取RDP WS URL失败')
  const wsHost = $isDev ? `ws://${ location.hostname }:8082` : location.origin.replace('http', 'ws')
  return `${ wsHost }/guac?token=${ encodeURIComponent(data) }`
}

const connectRdp = async () => {
  try {
    // 根据显示模式计算实际分辨率
    const { width, height } = calculateResolution()

    // 更新实际应用的配置
    appliedConfig.value = {
      width: width.toString(),
      height: height.toString()
    }

    // 保存到localStorage
    saveDisplayConfigToCache()

    // 清理之前的连接
    clearConnectionTimeout()
    disconnectRdp()

    currentStatus.value = rdpStatus.CONNECTING

    const wsUrl = await getRdpWsUrl()
    console.log('wsUrl:', wsUrl)

    // 设置连接超时（30秒）
    connectionTimeout.value = setTimeout(() => {
      if (isConnecting.value) {
        console.warn('⏰ RDP连接超时')
        currentStatus.value = rdpStatus.TIMEOUT
        $message.error('RDP连接超时，请检查网络或目标主机状态')
        disconnectRdp()
      }
    }, 30000)

    // 开始建立连接
    tunnel.value = new Guacamole.WebSocketTunnel(wsUrl)

    // 添加隧道事件监听
    tunnel.value.onerror = (error) => {
      console.error('🚇 WebSocket 隧道错误:', error)
      currentStatus.value = rdpStatus.ERROR
      $message.error('WebSocket连接错误')
      clearConnectionTimeout()
    }

    // tunnel.value.onstatechange = (state) => {
    //   console.log('🚇 WebSocket 隧道状态变化:', state)
    // }

    client.value = new Guacamole.Client(tunnel.value)
    display.value = client.value.getDisplay()

    // 设置事件处理器
    setupEventHandlers()
    console.log('🚀 开始RDP连接...')
    client.value.connect()

  } catch (error) {
    console.error('RDP连接失败:', error)
    currentStatus.value = rdpStatus.ERROR
    $message.error('RDP连接失败: ' + error.message)
    clearConnectionTimeout()
  }
}

const getStateText = (state) => {
  const stateMap = {
    0: 'IDLE',
    1: 'CONNECTING',
    2: 'WAITING',
    3: 'CONNECTED',
    4: 'DISCONNECTING',
    5: 'DISCONNECTED'
  }
  return stateMap[state] || `UNKNOWN(${ state })`
}

function mapGuacError(status) {
  const code = status?.code
  const msg = (status?.message || '').toLowerCase()

  // 1) 直接从 message 关键词判断（不同版本/系统更稳）
  if (msg.includes('auth') || msg.includes('credential') || msg.includes('logon') || msg.includes('password'))
    return '认证失败：用户名或密码错误，或账户被锁定。'

  if (msg.includes('security') && msg.includes('negotiation'))
    return '安全协商失败：目标主机需要的安全级别不匹配（可能是 NLA/TLS 相关）。'

  // 2) 用状态码兜底（不同版本的码值不完全一致）
  // 提示：这些常量在不同版本可能有差异，保守用“范围 + 兜底”
  try {
    const C = Guacamole.Status.Code // 常量枚举（如果有的话）
    if (code === C?.CLIENT_UNAUTHORIZED || code === C?.UPSTREAM_UNAUTHORIZED)
      return '认证失败：用户名或密码错误，或账户被禁用。'

    if (code === C?.UPSTREAM_NOT_FOUND)
      return '无法连接目标：主机/端口不可达或未开放 RDP。'

    if (code === C?.UPSTREAM_TIMEOUT)
      return '连接超时：网络不通或目标服务器响应过慢。'

    if (code === C?.UPSTREAM_ERROR)
      return '上游服务错误：RDP/guacd 发生异常。'
  } catch (_) {
    console.error('❌ Guac error:', status, 'code:', status?.code, 'msg:', status?.message)
  }

  // 3) 最后兜底
  return '连接失败：可能是凭证不正确、NLA 要求或网络问题。'
}

const setupEventHandlers = () => {
  client.value.onstatechange = (state) => {
    console.log('🔄 RDP连接状态变化:', state, '对应状态:', getStateText(state))
    switch (state) {
      case 0: // IDLE
        currentStatus.value = rdpStatus.IDLE
        break
      case 1: // CONNECTING
        currentStatus.value = rdpStatus.CONNECTING
        break
      case 2: // WAITING
        currentStatus.value = rdpStatus.WAITING
        break
      case 3: // CONNECTED
        console.log('🎉 RDP连接已建立！')
        currentStatus.value = rdpStatus.CONNECTED
        clearConnectionTimeout()
        onConnected()
        break
      case 4: // DISCONNECTING
        currentStatus.value = rdpStatus.DISCONNECTING
        break
      case 5: // DISCONNECTED
        currentStatus.value = rdpStatus.DISCONNECTED
        onDisconnected()
        break
      default:
        console.warn('未知RDP连接状态:', state)
        currentStatus.value = rdpStatus.ERROR
        break
    }
  }
  client.value.onerror = (status) => {
  // 有些环境 message 可能为空，这里都打印出来，方便定位
    console.error('❌ Guac error:', status, 'code:', status?.code, 'msg:', status?.message)

    // 友好文案映射
    const humanMsg = mapGuacError(status)
    $message.error(humanMsg)
  }
}

let hiddenInput = null

const toggleKeyboard = () => {
  if (!hiddenInput) return
  hiddenInput.focus()
}

const enableMobileKeyboard = () => {
  if (hiddenInput) return // 避免重复创建

  // 创建隐藏 input
  hiddenInput = document.createElement('input')
  hiddenInput.type = 'text'
  hiddenInput.autocapitalize = 'off'
  hiddenInput.autocorrect = 'off'
  hiddenInput.spellcheck = false
  hiddenInput.style.position = 'absolute'
  hiddenInput.style.opacity = '0'
  hiddenInput.style.height = '1px'
  hiddenInput.style.width = '1px'
  hiddenInput.style.fontSize = '16px' // 防止 iOS 放大
  hiddenInput.style.zIndex = '-1'
  document.body.appendChild(hiddenInput)

  let composing = false

  // 中文拼音等输入法
  hiddenInput.addEventListener('compositionstart', () => {
    composing = true
  })
  hiddenInput.addEventListener('compositionend', (e) => {
    composing = false
    sendText(e.data)
    hiddenInput.value = ''
  })

  // 普通输入
  hiddenInput.addEventListener('input', (e) => {
    if (composing) return
    const text = e.target.value
    if (!text) return
    sendText(text)
    hiddenInput.value = ''
  })

  // 处理特殊键（如删除键、回车键等）
  hiddenInput.addEventListener('keydown', (e) => {
    // 如果正在输入中文拼音，跳过
    if (composing) return
    const specialKeys = {
      'Backspace': 0xFF08, // Backspace
      'Delete': 0xFFFF, // Delete
      'Enter': 0xFF0D, // Enter/Return
      'Tab': 0xFF09, // Tab
      'Escape': 0xFF1B, // Escape
      'ArrowLeft': 0xFF51, // Left Arrow
      'ArrowUp': 0xFF52, // Up Arrow
      'ArrowRight': 0xFF53, // Right Arrow
      'ArrowDown': 0xFF54 // Down Arrow
    }
    const keysym = specialKeys[e.key]
    if (keysym) {
      e.preventDefault()
      client.value.sendKeyEvent(1, keysym)
      client.value.sendKeyEvent(0, keysym)
    }
  })

  const sendText = (text) => {
    for (const ch of text) {
      let keysym = null
      if (Guacamole.Keyboard.fromUnicode) {
        keysym = Guacamole.Keyboard.fromUnicode(ch)
      } else {
        keysym = ch.charCodeAt(0)
      }
      if (!keysym) continue
      client.value.sendKeyEvent(1, keysym)
      client.value.sendKeyEvent(0, keysym)
    }
  }

  // 点击远程桌面时自动 focus，调出键盘
  // const displayElement = client.value.getDisplay().getElement()
  // displayElement.addEventListener('touchend', () => {
  //   hiddenInput.focus()
  // })
}

const disableMobileKeyboard = () => {
  if (hiddenInput) {
    hiddenInput.remove()
    hiddenInput = null
  }
}

// 设置剪贴板事件处理
const setupClipboardHandlers = () => {
  if (!client.value) return
  client.value.onclipboard = (stream, mimetype) => {
    // console.log('📋 接收到远程剪贴板数据，类型:', mimetype)
    let clipboardData = ''
    stream.onblob = (data) => {
      try {
        // console.log('📋 接收到数据块，类型:', typeof data, '长度:', data?.length || data?.byteLength || 'unknown')
        if (data instanceof ArrayBuffer) {
          // 如果是 ArrayBuffer，直接转换为字符串
          const decoder = new TextDecoder('utf-8')
          clipboardData += decoder.decode(data)
        } else if (typeof data === 'string') {
          // 如果已经是字符串，可能是 base64 编码的
          try {
            const decoded = atob(data)
            clipboardData += decodeURIComponent(escape(decoded))
          } catch (e) {
            clipboardData += data
          }
        } else if (data && data.constructor === Uint8Array) {
          const decoder = new TextDecoder('utf-8')
          clipboardData += decoder.decode(data)
        } else {
          clipboardData += String(data)
        }
      } catch (error) {
        console.warn('❌ 处理剪贴板数据时出错:', error, data)
      }
    }

    stream.onend = () => {
      if (clipboardData && mimetype === 'text/plain') {
        navigator.clipboard.writeText(clipboardData) // 异步写入本地剪贴板
        console.log('📋 已将远程剪贴板内容写入本地:', clipboardData.substring(0, 50))
      }
    }

    if (stream.onerror) {
      stream.onerror = (error) => {
        console.warn('❌ 剪贴板流错误:', error)
      }
    }
  }
}

// 发送剪贴板内容到远程服务器
const sendClipboardToRemote = async (text) => {
  if (!client.value || !text) return
  try {
    console.log('📋 发送本地剪贴板内容到远程:', text.substring(0, 50))
    // 按 RDP 习惯把 \n 规范成 \r\n
    const normalized = text.replace(/\r?\n/g, '\r\n')
    // createClipboardStream + StringWriter
    const stream = client.value.createClipboardStream('text/plain')
    const writer = new Guacamole.StringWriter(stream)
    writer.sendText(normalized)
    writer.sendEnd()
  } catch (err) {
    console.warn('❌ 发送剪贴板内容到远程失败:', err)
  }
}

const onConnected = () => {
  // 清空容器并添加显示元素
  if (rdpContainer.value) {
    rdpContainer.value.innerHTML = ''
    const display = client.value.getDisplay()
    const displayElement = display.getElement()

    // 重要：设置显示缩放为1:1，确保鼠标位置准确
    display.scale(1.0)

    // 不要设置CSS尺寸，让Guacamole自己管理canvas尺寸
    displayElement.style.display = 'block'

    rdpContainer.value.appendChild(displayElement)
  }

  // 设置鼠标事件
  const displayElement = client.value.getDisplay().getElement()
  mouse = new Guacamole.Mouse(displayElement)
  mouse.onmousedown = mouse.onmouseup = mouse.onmousemove = (e) => {
    client.value.sendMouseState(e.state ?? e)
  }

  // 设置触摸事件（移动端支持）
  if (isMobile()) {
    const touchscreen = new Guacamole.Mouse.Touchscreen(displayElement)
    touchscreen.onEach(['mousedown', 'mousemove', 'mouseup',], (e) => {
      // 第二个 true 表示这是来自触屏的事件（新版本示例用法）
      client.value.sendMouseState(e.state ?? e, true)
    })
  }

  // 让 canvas 可以获得焦点，捕获键盘事件
  displayElement.setAttribute('tabindex', '0')
  displayElement.focus()
  // 当用户点击 canvas 时，重新获得焦点（解决切换窗口后失焦问题）
  displayElement.addEventListener('mousedown', () => {
    displayElement.focus()
  })
  // 当用户聚焦 RDP 容器时，推送一次本地剪贴板
  displayElement.addEventListener('focus', async () => {
    try {
      if (!navigator.clipboard?.readText) return
      const text = await navigator.clipboard.readText()
      if (!text) return
      sendClipboardToRemote(text)
    } catch (err) {
      console.debug('无法读取本地剪贴板:', err.message)
    }
  })

  keyboard = new Guacamole.Keyboard(displayElement)
  keyboard.onkeydown = (keysym) => client.value.sendKeyEvent(1, keysym)
  keyboard.onkeyup = (keysym) => client.value.sendKeyEvent(0, keysym)

  // 处理显示尺寸变化
  const display = client.value.getDisplay()
  display.onresize = (width, height) => {
    console.log('RDP显示尺寸变化:', width, 'x', height)
    // 确保显示缩放始终为1:1
    display.scale(1.0)
  }

  // 处理移动端键盘输入
  if (isMobile()) {
    enableMobileKeyboard()
  }

  setupClipboardHandlers()
}

const onDisconnected = () => {
  console.log('RDP连接已断开')
  clearConnectionTimeout()
  cleanupResources()
  disableMobileKeyboard()
}

const disconnectRdp = () => {
  if (client.value) {
    try {
      client.value.disconnect()
    } catch (error) {
      console.warn('断开RDP连接时出错:', error)
    }
  }
  currentStatus.value = rdpStatus.DISCONNECTED
  clearConnectionTimeout()
  cleanupResources()
}

const clearConnectionTimeout = () => {
  if (connectionTimeout.value) {
    clearTimeout(connectionTimeout.value)
    connectionTimeout.value = null
  }
}

const cleanupResources = () => {
  // 清理鼠标和键盘事件
  if (mouse) {
    mouse.onmousedown = mouse.onmouseup = mouse.onmousemove = null
    mouse = null
  }
  // 清理触摸事件
  if (touch) {
    touch.onmousedown = touch.onmouseup = touch.onmousemove = null
    touch = null
  }
  if (keyboard) {
    keyboard.onkeydown = keyboard.onkeyup = null
    keyboard = null
  }

  // 清理客户端和隧道
  if (client.value) {
    client.value = null
  }
  if (tunnel.value) {
    try {
      tunnel.value.disconnect()
    } catch (error) {
      console.warn('关闭WebSocket隧道时出错:', error)
    }
    tunnel.value = null
  }

  // 清空显示容器
  if (rdpContainer.value) {
    rdpContainer.value.innerHTML = ''
  }
}

// 组件销毁时清理资源
onBeforeUnmount(() => {
  disconnectRdp()
})

// 暴露给父组件的方法
defineExpose({
  disconnectRdp
})

</script>

<style scoped lang="scss">
.rdp_container {
  width: 100%;
  min-height: 400px;
  height: 100%;
  position: relative;
  z-index: 1;
  overflow-y: auto;
  overflow-x: hidden;
  display: flex;
  justify-content: center;
  align-items: center;
  background-color: #000;

  // 隐藏本地鼠标指针，避免与远程指针重合
  :deep(canvas) {
    cursor: none !important;
    display: block;
  }
}
.rdp_dialog_header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  padding: 0 4px;

  .rdp_left {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: flex-start;
    .host_info {
      display: flex;
      align-items: center;
      .hostname {
        font-size: 16px;
        font-weight: 600;
        color: var(--el-text-color-primary);
        margin-right: 12px;
      }
      .status_info {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        .status_icon {
          font-size: 14px;
        }
        .status_text {
          font-size: 13px;
          font-weight: 500;
        }
      }
    }
  }

  .rdp_center {
    flex: 0 0 auto;
    margin: 0 16px;
    .resolution_controls {
      display: flex;
      align-items: center;
      gap: 8px;
      .display_mode_select {
        width: 80px;
      }
      .info_icon {
        margin-left: 4px;
        font-size: 14px;
        color: var(--el-color-info);
        cursor: help;
      }
    }
  }

  .rdp_right {
    flex: 0 0 auto;
    display: flex;
    align-items: center;
    gap: 8px;
  }
}
</style>

<style>
.rdp_content {
  padding: 0!important;
  /* margin: 0 auto!important; */
  .rdp_header {
    padding: 8px;
  }
}
.rdp_body {
  height: v-bind(dialogBodyHeight);
}
</style>