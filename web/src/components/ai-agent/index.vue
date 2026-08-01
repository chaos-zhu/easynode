<template>
  <Teleport to="body">
    <section
      v-show="visible"
      ref="windowRef"
      class="agent_window"
      :class="{
        'is_dark': isDark,
        'is_mobile': isMobileScreen,
        'is_maximized': maximized,
        'is_interacting': Boolean(windowInteraction)
      }"
      :style="windowStyle"
      role="dialog"
      aria-label="AI 助手"
    >
      <template v-if="!isMobileScreen && !maximized">
        <i
          v-for="direction in RESIZE_DIRECTIONS"
          :key="direction"
          :class="['resize_handle', `resize_${ direction }`]"
          @pointerdown.stop.prevent="startWindowResize($event, direction)"
        />
      </template>

      <div class="agent_layout" :class="{ 'is_dark': isDark }">
        <transition name="session_panel">
          <SessionList
            v-if="showSessions"
            class="layout_side"
            :sessions="sessions"
            :active-id="state.sessionId"
            clear-scope-label="AI 助手"
            @select="handleSelectSession"
            @create="handleNewSession"
            @remove="handleRemoveSession"
            @clear="handleClearSessions"
            @rename="renameSession"
          />
        </transition>

        <div class="layout_main">
          <header class="agent_header" @pointerdown="startWindowDrag" @dblclick="handleHeaderDoubleClick">
            <el-button link :title="showSessions ? '收起历史' : '展开历史'" @click="showSessions = !showSessions">
              <el-icon><Expand v-if="!showSessions" /><Fold v-else /></el-icon>
            </el-button>

            <span class="header_title" :title="state.title">
              EasyNode · 助手<span v-if="state.title"> · {{ state.title }}</span>
            </span>

            <span class="header_spacer" />

            <el-tag
              v-if="!connected"
              type="danger"
              size="small"
              effect="plain"
            >
              未连接
            </el-tag>

            <AssistantInfoPopover
              scope="ops"
              :tools="options.tools"
              :preset="settings.preset"
              :selected-host-count="settings.hostIds.length"
              :plus-available="options.plusAvailable"
              :connected="connected"
            />
            <el-button
              class="header_icon_button"
              link
              title="新会话"
              @click="handleNewSession"
            >
              <el-icon><Plus /></el-icon>
            </el-button>
            <el-button
              class="header_icon_button"
              link
              title="AI 助手设置"
              @click="openAgentSettings"
            >
              <el-icon><Setting /></el-icon>
            </el-button>
            <el-button
              v-if="!isMobileScreen"
              class="header_icon_button"
              link
              :title="maximized ? '还原窗口' : '最大化窗口'"
              @click="toggleMaximize"
            >
              <el-icon><CopyDocument v-if="maximized" /><FullScreen v-else /></el-icon>
            </el-button>
            <el-button
              class="header_icon_button"
              link
              title="关闭"
              @click="visible = false"
            >
              <el-icon><Close /></el-icon>
            </el-button>
          </header>

          <el-alert
            v-if="connectError"
            class="agent_alert"
            type="error"
            :title="connectError"
            :closable="false"
            show-icon
          />
          <el-alert
            v-else-if="state.plusRequired"
            class="agent_alert plus_required_alert"
            type="warning"
            show-icon
            center
            @close="dismissPlusRequired"
            @mouseenter="pausePlusRequiredTimer"
            @mouseleave="resumePlusRequiredTimer"
          >
            <template #title>
              <span class="plus_alert_message">{{ state.plusRequired.message }}</span>
              <el-button
                class="plus_activation_button"
                type="primary"
                link
                @click="openPlusSettings"
              >
                去激活
              </el-button>
            </template>
          </el-alert>
          <el-alert
            v-else-if="notice"
            class="agent_alert"
            type="warning"
            :title="notice"
            show-icon
            @close="dismissNotice"
          />
          <el-alert
            v-else-if="clampedTip"
            class="agent_alert"
            type="info"
            :title="clampedTip"
            :closable="false"
            show-icon
          />

          <el-scrollbar ref="scrollRef" class="agent_body" @scroll="handleScroll">
            <div ref="bodyRef" class="body_inner">
              <div v-if="!state.messages.length" class="empty_state">
                <el-icon class="empty_icon"><ChatDotRound /></el-icon>
                <p class="empty_title">选择一台或多台主机，我可以帮你排查问题、查看状态和执行运维操作</p>
              </div>

              <MessageItem
                v-for="(message, index) in state.messages"
                :key="message.id"
                :message="message"
                :running="state.running"
                :waiting-for-model="state.waitingForModel && index === state.messages.length - 1"
                :editable="message.role === 'user' && !state.running"
                :editing="editingMessageId === message.id"
                :regeneratable="message.role === 'assistant' && !state.running"
                @start-edit="editingMessageId = message.id"
                @cancel-edit="editingMessageId = ''"
                @confirm-edit="handleConfirmEdit"
                @regenerate="handleRegenerate"
                @fork="handleFork"
              />

              <ApprovalPrompt
                v-for="item in state.pendingApprovals"
                :key="item.requestId"
                :item="item"
                @respond="respondApproval"
              />

              <p v-if="state.error" class="turn_error">{{ state.error }}</p>
              <p v-else-if="state.aborted" class="turn_aborted">已停止生成</p>
            </div>
          </el-scrollbar>

          <el-button
            v-if="!isAtBottom"
            class="to_bottom"
            circle
            size="small"
            @click="scrollToBottom"
          >
            <el-icon><Bottom /></el-icon>
          </el-button>

          <footer class="agent_footer">
            <ChatSender
              ref="senderRef"
              v-model:value="draft"
              :loading="state.running"
              :placeholder="senderPlaceholder"
              @submit="handleSend"
              @cancel="stop"
            />

            <div class="footer_controls">
              <div class="mode_control">
                <ModeSwitcher :model-value="settings.preset" :presets="presets" @change="setPreset" />
              </div>

              <el-select
                :model-value="settings.modelId"
                size="small"
                class="model_select"
                placeholder="选择模型"
                @update:model-value="setModel"
              >
                <el-option
                  v-for="model in options.models"
                  :key="model"
                  :label="model"
                  :value="model"
                />
              </el-select>

              <HostSelector v-model="settings.hostIds" class="host_select" />

              <span class="footer_spacer" />
            </div>
          </footer>
        </div>
      </div>
    </section>
  </Teleport>
</template>

<script setup>
import { ref, reactive, computed, nextTick, onMounted, onBeforeUnmount, getCurrentInstance, watch } from 'vue'
import { setCustomComponents } from 'markstream-vue'
import 'markstream-vue/index.css'
import 'highlight.js/styles/github-dark.css'
import {
  Plus, Close, Setting, Expand, Fold, ChatDotRound, Bottom, CopyDocument, FullScreen
} from '@element-plus/icons-vue'
import CustomCodeBlock from './custom-code-block.vue'
import { EventBus } from '@/utils'
import ChatSender from '../common/chat-sender.vue'
import MessageItem from './message-item.vue'
import ApprovalPrompt from './approval-prompt.vue'
import ModeSwitcher from './mode-switcher.vue'
import HostSelector from './host-selector.vue'
import SessionList from './session-list.vue'
import AssistantInfoPopover from './assistant-info-popover.vue'
import { useAgentSession } from '@/composables/useAgentSession'
import { findPreviousUserMessage, findUserTurnIndex, messageText } from '@/composables/agentMessages'
import useMobileWidth from '@/composables/useMobileWidth'
import { PRESET_FALLBACK } from './presets'

const { proxy: { $api, $message, $store, $router } } = getCurrentInstance()

const visible = defineModel('show', { type: Boolean, default: false })
const emit = defineEmits(['status-change',])

const {
  connected,
  connectError,
  state,
  options,
  settings,
  sessions,
  historyNotice,
  connect,
  send,
  stop,
  dismissPlusRequired,
  pausePlusRequiredTimer,
  resumePlusRequiredTimer,
  respondApproval,
  resetConversation,
  refreshSessions,
  loadSession,
  forkSession,
  removeSession,
  clearSessions,
  renameSession,
  setModel,
  setPreset
} = useAgentSession()

const { isMobileScreen } = useMobileWidth()

const draft = ref('')
const senderRef = ref(null)
const scrollRef = ref(null)
const bodyRef = ref(null)
const showSessions = ref(false)
const isAtBottom = ref(true)
let autoFollow = true
let bodyResizeObserver = null
const dismissedNotice = ref('')
const editingMessageId = ref('')
const windowRef = ref(null)
const maximized = ref(false)
const windowInteraction = ref(null)
const WINDOW_GEOMETRY_KEY = 'agentWindowGeometry'
const LEGACY_DRAWER_WIDTH_KEY = 'agentDrawerWidth'
const WINDOW_EDGE_GAP = 12
const DEFAULT_WINDOW_WIDTH = 420
const DEFAULT_WINDOW_HEIGHT = 680
const MIN_WINDOW_WIDTH = 360
const MIN_WINDOW_HEIGHT = 480
const RESIZE_DIRECTIONS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw',]
const windowGeometry = reactive({
  x: WINDOW_EDGE_GAP,
  y: WINDOW_EDGE_GAP,
  width: DEFAULT_WINDOW_WIDTH,
  height: DEFAULT_WINDOW_HEIGHT
})

const isDark = computed(() => $store.isDark)
const windowStyle = computed(() => {
  if (isMobileScreen.value) return {}
  if (maximized.value) {
    return {
      left: `${ WINDOW_EDGE_GAP }px`,
      top: `${ WINDOW_EDGE_GAP }px`,
      width: `calc(100vw - ${ WINDOW_EDGE_GAP * 2 }px)`,
      height: `calc(100vh - ${ WINDOW_EDGE_GAP * 2 }px)`
    }
  }
  return {
    left: `${ windowGeometry.x }px`,
    top: `${ windowGeometry.y }px`,
    width: `${ windowGeometry.width }px`,
    height: `${ windowGeometry.height }px`
  }
})
const senderPlaceholder = computed(() => (settings.hostIds.length
  ? '输入任务或者问题，Enter 发送'
  : '描述问题，Enter 发送'))

// 后端 ready 事件之前也要有预设可选，否则首次打开是空下拉
const presets = computed(() => (options.presets.length ? options.presets : PRESET_FALLBACK))

const notice = computed(() => (historyNotice.value === dismissedNotice.value ? '' : historyNotice.value))
const clampedTip = computed(() => {
  if (!state.clamped) return ''
  const reasons = []
  if (state.clamped.effect) reasons.push('操作范围')
  if (state.clamped.mode) reasons.push('权限模式')
  if (!reasons.length) return ''
  return `部分目标主机收紧了${ reasons.join('与') }，具体操作将按目标主机策略执行`
})

function dismissNotice() {
  dismissedNotice.value = historyNotice.value
}

function handleOpen() {
  connect()
  refreshSessions()
}

function handleOpened() {
  focusSender()
  if (!bodyResizeObserver && bodyRef.value) {
    bodyResizeObserver = new ResizeObserver(() => {
      if (autoFollow) scrollToBottom()
    })
    bodyResizeObserver.observe(bodyRef.value)
  }
  scrollToBottom()
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function normalizeWindowGeometry(input = {}) {
  const maxWidth = Math.max(1, window.innerWidth - WINDOW_EDGE_GAP * 2)
  const maxHeight = Math.max(1, window.innerHeight - WINDOW_EDGE_GAP * 2)
  const minWidth = Math.min(MIN_WINDOW_WIDTH, maxWidth)
  const minHeight = Math.min(MIN_WINDOW_HEIGHT, maxHeight)
  const width = Math.round(clamp(Number(input.width) || DEFAULT_WINDOW_WIDTH, minWidth, maxWidth))
  const height = Math.round(clamp(Number(input.height) || DEFAULT_WINDOW_HEIGHT, minHeight, maxHeight))
  const maxX = Math.max(WINDOW_EDGE_GAP, window.innerWidth - width - WINDOW_EDGE_GAP)
  const maxY = Math.max(WINDOW_EDGE_GAP, window.innerHeight - height - WINDOW_EDGE_GAP)
  return {
    x: Math.round(clamp(Number(input.x) || WINDOW_EDGE_GAP, WINDOW_EDGE_GAP, maxX)),
    y: Math.round(clamp(Number(input.y) || WINDOW_EDGE_GAP, WINDOW_EDGE_GAP, maxY)),
    width,
    height
  }
}

function applyWindowGeometry(input) {
  Object.assign(windowGeometry, normalizeWindowGeometry(input))
}

function saveWindowGeometry() {
  localStorage.setItem(WINDOW_GEOMETRY_KEY, JSON.stringify({ ...windowGeometry }))
}

function restoreWindowGeometry() {
  try {
    const saved = JSON.parse(localStorage.getItem(WINDOW_GEOMETRY_KEY) || 'null')
    if (saved && ['x', 'y', 'width', 'height',].every((key) => Number.isFinite(Number(saved[key])))) {
      applyWindowGeometry(saved)
      return
    }
  } catch (error) {
    console.warn('读取 AI 助手窗口位置失败:', error.message)
  }

  const legacyWidth = Number(localStorage.getItem(LEGACY_DRAWER_WIDTH_KEY))
  const width = Number.isFinite(legacyWidth) && legacyWidth > 0 ? legacyWidth : DEFAULT_WINDOW_WIDTH
  const initial = normalizeWindowGeometry({ width, height: DEFAULT_WINDOW_HEIGHT })
  applyWindowGeometry({
    ...initial,
    x: window.innerWidth - initial.width - 24,
    y: 24
  })
}

function addWindowInteractionListeners() {
  window.addEventListener('pointermove', handleWindowInteractionMove)
  window.addEventListener('pointerup', finishWindowInteraction)
  window.addEventListener('pointercancel', finishWindowInteraction)
}

function removeWindowInteractionListeners() {
  window.removeEventListener('pointermove', handleWindowInteractionMove)
  window.removeEventListener('pointerup', finishWindowInteraction)
  window.removeEventListener('pointercancel', finishWindowInteraction)
}

function startWindowDrag(event) {
  if (event.button !== 0 || isMobileScreen.value || maximized.value) return
  if (event.target?.closest?.('button, a, input, textarea, select, [role="button"], .el-select')) return
  windowInteraction.value = {
    type: 'move',
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    geometry: { ...windowGeometry }
  }
  addWindowInteractionListeners()
  event.preventDefault()
}

function startWindowResize(event, direction) {
  if (event.button !== 0 || isMobileScreen.value || maximized.value) return
  windowInteraction.value = {
    type: 'resize',
    direction,
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    geometry: { ...windowGeometry }
  }
  addWindowInteractionListeners()
}

function resizeGeometry(interaction, deltaX, deltaY) {
  const { direction, geometry } = interaction
  const next = { ...geometry }
  if (direction.includes('e')) next.width = geometry.width + deltaX
  if (direction.includes('s')) next.height = geometry.height + deltaY
  if (direction.includes('w')) {
    next.width = geometry.width - deltaX
    next.x = geometry.x + deltaX
  }
  if (direction.includes('n')) {
    next.height = geometry.height - deltaY
    next.y = geometry.y + deltaY
  }

  const normalized = normalizeWindowGeometry(next)
  if (direction.includes('w')) normalized.x = geometry.x + geometry.width - normalized.width
  if (direction.includes('n')) normalized.y = geometry.y + geometry.height - normalized.height
  return normalizeWindowGeometry(normalized)
}

function handleWindowInteractionMove(event) {
  const interaction = windowInteraction.value
  if (!interaction || interaction.pointerId !== event.pointerId) return
  const deltaX = event.clientX - interaction.startX
  const deltaY = event.clientY - interaction.startY
  if (interaction.type === 'move') {
    applyWindowGeometry({
      ...interaction.geometry,
      x: interaction.geometry.x + deltaX,
      y: interaction.geometry.y + deltaY
    })
  } else {
    applyWindowGeometry(resizeGeometry(interaction, deltaX, deltaY))
  }
}

function finishWindowInteraction(event) {
  const interaction = windowInteraction.value
  if (!interaction || interaction.pointerId !== event.pointerId) return
  windowInteraction.value = null
  removeWindowInteractionListeners()
  saveWindowGeometry()
}

function toggleMaximize() {
  if (isMobileScreen.value) return
  maximized.value = !maximized.value
  if (!maximized.value) nextTick(() => applyWindowGeometry(windowGeometry))
}

function handleHeaderDoubleClick(event) {
  if (event.target?.closest?.('button, a, input, [role="button"]')) return
  toggleMaximize()
}

function handleViewportResize() {
  if (isMobileScreen.value || maximized.value) return
  applyWindowGeometry(windowGeometry)
  saveWindowGeometry()
}

function openAgentSettings() {
  $router.push({ path: '/setting', query: { tabKey: 'ai-agent' } })
}

function openPlusSettings() {
  $router.push(state.plusRequired?.activationPath || '/setting?tabKey=plus')
}

function focusSender() {
  nextTick(() => {
    requestAnimationFrame(() => senderRef.value?.focus())
  })
}

// 保持与旧 Chat 助手一致：由全局 EventBus 直接唤起并写入输入框。
function handleExternalInput(text) {
  const wasVisible = visible.value
  draft.value = String(text || '')
  visible.value = true
  if (wasVisible) focusSender()
}

EventBus.$on('sendToAIInput', handleExternalInput)

watch(visible, async (show) => {
  if (!show) return
  handleOpen()
  await nextTick()
  handleOpened()
})

watch([() => state.running, connectError, () => state.completionId,], ([running, error, completionId,]) => {
  emit('status-change', { running, connectError: error || '', completionId })
}, { immediate: true })

watch(isMobileScreen, (mobile) => {
  if (mobile) maximized.value = false
  else nextTick(() => applyWindowGeometry(windowGeometry))
})

onMounted(() => {
  restoreWindowGeometry()
  window.addEventListener('resize', handleViewportResize)
  // 让 markdown 里的代码块带上「复制 / 在终端执行」按钮。
  // custom-id 要与 message-item.vue 里传给 MarkdownRender 的一致。
  setCustomComponents('agent', { code_block: CustomCodeBlock })
})

onBeforeUnmount(() => {
  EventBus.$off('sendToAIInput', handleExternalInput)
  window.removeEventListener('resize', handleViewportResize)
  removeWindowInteractionListeners()
  bodyResizeObserver?.disconnect()
})

function handleSend(text) {
  if (!connected.value) return $message.error('未连接到服务端')
  if (!settings.modelId) return $message.warning('请先在 AI 设置中配置模型')
  draft.value = ''
  send(text)
  scrollToBottom()
}

async function handleConfirmEdit(message, content) {
  if (!content) return $message.warning('消息内容不能为空')
  if (state.running) return $message.warning('请等待当前任务结束后再编辑')

  try {
    await editAndResend(message, content)
    editingMessageId.value = ''
    scrollToBottom()
  } catch (error) {
    $message.error(`编辑消息失败: ${ error.message }`)
  }
}

async function handleRegenerate(message) {
  if (state.running) return $message.warning('请等待当前任务结束后再重新生成')
  const userMessage = findPreviousUserMessage(state.messages, message.id)
  if (!userMessage) return $message.warning('未找到这条回答对应的问题')

  const content = messageText(userMessage)
  if (!content) return $message.warning('原消息内容为空，无法重新生成')

  try {
    await editAndResend(userMessage, content)
    editingMessageId.value = ''
    scrollToBottom()
  } catch (error) {
    $message.error(`重新生成失败: ${ error.message }`)
  }
}

async function handleFork(message) {
  if (state.running) return $message.warning('请等待当前任务结束后再创建分支')
  const turnIndex = findUserTurnIndex(state.messages, message.id)
  if (turnIndex === -1) return $message.warning('未找到这条回答对应的会话位置')

  try {
    await forkSession(turnIndex, message.sourceIndex)
    draft.value = ''
    editingMessageId.value = ''
    showSessions.value = false
    scrollToBottom()
    $message.success('已创建并切换到分支会话')
  } catch (error) {
    $message.error(`创建分支失败: ${ error.message }`)
  }
}

function handleNewSession() {
  if (state.running) return $message.warning('当前任务仍在执行，请先停止')
  resetConversation()
  draft.value = ''
  editingMessageId.value = ''
  nextTick(() => senderRef.value?.focus())
}

async function handleSelectSession(id) {
  if (state.running) return $message.warning('当前任务仍在执行，请先停止')
  if (id === state.sessionId) {
    showSessions.value = false
    return
  }
  try {
    await loadSession(id)
    showSessions.value = false
    editingMessageId.value = ''
    scrollToBottom()
  } catch (error) {
    $message.error(`加载会话失败: ${ error.message }`)
  }
}

async function editAndResend(message, content) {
  if (!state.sessionId) throw new Error('当前消息尚未保存，请稍后再试')

  const messageIndex = state.messages.findIndex((item) => item.id === message.id)
  const turnIndex = state.messages
    .filter((item) => item.role === 'user')
    .findIndex((item) => item.id === message.id)

  if (messageIndex === -1 || turnIndex === -1) throw new Error('未找到要编辑的消息')

  const { data } = await $api.editAgentSessionMessage(state.sessionId, { turnIndex, content })

  // 服务端已经从本条用户消息开始截断历史；本地也丢弃同一段，再以新内容开启本轮。
  state.messages.splice(messageIndex)
  state.pendingApprovals.splice(0)
  state.title = data.title
  state.usage = { ...state.usage, ...(data.usage || {}) }
  state.turnUsage = { inputTokens: 0, outputTokens: 0, totalTokens: 0, cachedInputTokens: 0, reasoningTokens: 0 }
  state.aborted = false
  state.error = null
  state.finishReason = ''
  send(content)
}

async function handleRemoveSession(id) {
  try {
    await removeSession(id)
    $message.success('已删除')
  } catch (error) {
    $message.error(`删除失败: ${ error.message }`)
  }
}

async function handleClearSessions() {
  if (state.running) return $message.warning('当前任务仍在执行，请先停止后再清空历史')
  try {
    await clearSessions()
    showSessions.value = false
    $message.success('已清空 AI 助手历史会话')
  } catch (error) {
    $message.error(`清空失败: ${ error.message }`)
  }
}

function scrollToBottom() {
  autoFollow = true
  nextTick(() => {
    const wrap = scrollRef.value?.wrapRef
    if (!wrap) return
    wrap.scrollTop = wrap.scrollHeight
    isAtBottom.value = true
  })
}

function handleScroll({ scrollTop }) {
  const wrap = scrollRef.value?.wrapRef
  if (!wrap) return
  isAtBottom.value = wrap.scrollHeight - scrollTop - wrap.clientHeight < 40
  autoFollow = isAtBottom.value
}
</script>

<style lang="scss" scoped>
.agent_window {
  position: fixed;
  z-index: 1900;
  box-sizing: border-box;
  overflow: hidden;
  border: 1px solid var(--el-border-color);
  border-radius: 12px;
  background-color: var(--el-bg-color);
  box-shadow: 0 18px 48px rgba(16, 24, 40, 0.24);

  &.is_interacting {
    user-select: none;
  }

  &.is_dark {
    box-shadow: 0 18px 52px rgba(0, 0, 0, 0.55);
  }

  &.is_mobile {
    inset: 0 !important;
    width: 100vw !important;
    height: 100dvh !important;
    border: 0;
    border-radius: 0;

    .agent_header {
      height: calc(44px + env(safe-area-inset-top));
      padding-top: calc(8px + env(safe-area-inset-top));
      cursor: default;
    }

    .agent_footer {
      padding-bottom: calc(12px + env(safe-area-inset-bottom));
    }

    .layout_side {
      top: calc(44px + env(safe-area-inset-top));
      height: calc(100% - 44px - env(safe-area-inset-top));
    }
  }
}

.resize_handle {
  position: absolute;
  z-index: 10;
  display: block;
  touch-action: none;

  &.resize_n,
  &.resize_s {
    left: 10px;
    right: 10px;
    height: 7px;
    cursor: ns-resize;
  }

  &.resize_e,
  &.resize_w {
    top: 10px;
    bottom: 10px;
    width: 7px;
    cursor: ew-resize;
  }

  &.resize_n { top: 0; }
  &.resize_s { bottom: 0; }
  &.resize_e { right: 0; }
  &.resize_w { left: 0; }

  &.resize_ne,
  &.resize_nw,
  &.resize_se,
  &.resize_sw {
    width: 12px;
    height: 12px;
  }

  &.resize_ne { top: 0; right: 0; cursor: nesw-resize; }
  &.resize_nw { top: 0; left: 0; cursor: nwse-resize; }
  &.resize_se { right: 0; bottom: 0; cursor: nwse-resize; }
  &.resize_sw { bottom: 0; left: 0; cursor: nesw-resize; }
}

.agent_layout {
  position: relative;
  height: 100%;
  overflow: hidden;
  background-color: var(--el-bg-color);

  .layout_side {
    position: absolute;
    z-index: 3;
    top: 44px;
    height: min(75vh, calc(100% - 44px));
    left: 0;
    width: min(240px, calc(100% - 24px));
    background-color: #fff;
    box-shadow: 8px 0 20px rgba(0, 0, 0, 0.12);
  }

  .layout_main {
    position: relative;
    height: 100%;
    display: flex;
    flex-direction: column;
    container-type: inline-size;
    container-name: agent_main;
  }

  .agent_header {
    display: flex;
    align-items: center;
    height: 44px;
    box-sizing: border-box;
    gap: 6px;
    padding: 8px 10px;
    border-bottom: 1px solid #e4e7ed;
    cursor: move;

    .header_title {
      font-size: 14px;
      font-weight: 500;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      max-width: 50%;
    }

    .header_spacer {
      flex: 1;
    }

    .header_icon_button {
      width: 28px;
      height: 28px;
      margin-left: 0;
      padding: 0;
      border-radius: 7px;
      color: var(--el-text-color-secondary);

      &:hover,
      &:focus-visible {
        outline: none;
        background-color: var(--el-fill-color);
        color: var(--el-text-color-primary);
      }
    }
  }

  .agent_alert {
    border-radius: 0;
  }

  .plus_required_alert {
    --el-alert-padding: 9px 44px;
    flex-shrink: 0;

    :deep(.el-alert__title) {
      display: flex;
      align-items: center;
      justify-content: center;
      flex-wrap: wrap;
      column-gap: 8px;
      font-size: 13px;
      line-height: 22px;
      text-align: center;
    }

    :deep(.el-alert__close-btn) {
      top: 50%;
      right: 14px;
      transform: translateY(-50%);
    }

    .plus_alert_message {
      font-weight: 500;
    }

    .plus_activation_button {
      height: 24px;
      margin: 0;
      padding: 0 4px;
      font-size: 13px;
      font-weight: 600;
    }
  }

  .agent_body {
    flex: 1;
    min-height: 0;

    .body_inner {
      padding: 12px;
    }
  }

  .to_bottom {
    position: absolute;
    right: 16px;
    bottom: 130px;
    z-index: 2;
  }

  .empty_state {
    padding: 40px 12px;
    text-align: center;
    color: #909399;

    .empty_icon {
      font-size: 40px;
      margin-bottom: 12px;
    }

    .empty_title {
      margin: 0 0 16px;
      font-size: 14px;
    }

  }

  .turn_error,
  .turn_aborted {
    margin: 8px 0 0;
    font-size: 13px;
  }

  .turn_error {
    color: #f56c6c;
  }

  .turn_aborted {
    color: #909399;
  }

  .agent_footer {
    padding: 8px 12px 12px;
    border-top: 1px solid #e4e7ed;

    .footer_controls {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-top: 8px;

      .mode_control {
        flex: 0 0 auto;
        min-width: 0;
      }

      .model_select {
        flex: 0 1 150px;
        min-width: 110px;
        width: 150px;
      }

      .host_select {
        flex: 0 1 150px;
        min-width: 110px;
      }

      .footer_spacer {
        flex: 1;
      }
    }
  }

  &.is_dark {
    .layout_side {
      background-color: #1d1e1f;
      box-shadow: 8px 0 20px rgba(0, 0, 0, 0.4);
    }

    .agent_header,
    .agent_footer {
      border-color: #3a3a3a;
    }

  }
}

@container agent_main (max-width: 520px) {
  .agent_footer {
    .footer_controls {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));

      .mode_control {
        grid-column: 1 / -1;
      }

      .model_select,
      .host_select {
        width: 100%;
        min-width: 0;
      }

      .footer_spacer {
        display: none;
      }
    }
  }
}

.session_panel-enter-active,
.session_panel-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.session_panel-enter-from,
.session_panel-leave-to {
  opacity: 0;
  transform: translateX(-12px);
}
</style>
