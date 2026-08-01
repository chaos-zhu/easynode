<template>
  <el-drawer
    v-model="visible"
    :size="drawerSize"
    :with-header="false"
    :close-on-press-escape="false"
    :modal="false"
    :resizable="!isMobileScreen"
    append-to-body
    modal-class="agent_drawer_overlay"
    direction="rtl"
    class="agent_drawer"
    @open="handleOpen"
    @opened="handleOpened"
    @mousedown="handleDrawerMouseDown"
  >
    <div class="agent_layout" :class="{ 'is_dark': isDark }">
      <transition name="session_panel">
        <SessionList
          v-if="showSessions"
          class="layout_side"
          :sessions="sessions"
          :active-id="state.sessionId"
          clear-scope-label="运维助手"
          @select="handleSelectSession"
          @create="handleNewSession"
          @remove="handleRemoveSession"
          @clear="handleClearSessions"
          @rename="renameSession"
        />
      </transition>

      <div class="layout_main">
        <header class="agent_header">
          <el-button link :title="showSessions ? '收起历史' : '展开历史'" @click="showSessions = !showSessions">
            <el-icon><Expand v-if="!showSessions" /><Fold v-else /></el-icon>
          </el-button>

          <span class="header_title" :title="state.title">{{ state.title || 'AI 运维助手' }}</span>

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
            title="AI助手设置"
            @click="openAgentSettings"
          >
            <el-icon><Setting /></el-icon>
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
            <el-button class="plus_activation_button" type="primary" link @click="openPlusSettings">去激活</el-button>
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
              <p class="empty_title">我可以帮你排查问题、查看状态、执行运维操作</p>
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
  </el-drawer>
</template>

<script setup>
import { ref, computed, nextTick, onMounted, onBeforeUnmount, getCurrentInstance } from 'vue'
import { setCustomComponents } from 'markstream-vue'
import 'markstream-vue/index.css'
import 'highlight.js/styles/github-dark.css'
import {
  Plus, Close, Setting, Expand, Fold, ChatDotRound, Bottom
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
const DRAWER_WIDTH_KEY = 'agentDrawerWidth'
const MIN_DRAWER_WIDTH = 300
const DEFAULT_DRAWER_WIDTH = 350
const savedDrawerWidth = ref(readSavedDrawerWidth())

const isDark = computed(() => $store.isDark)
const drawerSize = computed(() => {
  if (isMobileScreen.value) return '100%'
  return `${ savedDrawerWidth.value || DEFAULT_DRAWER_WIDTH }px`
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
  if (!bodyResizeObserver) {
    bodyResizeObserver = new ResizeObserver(() => {
      if (autoFollow) scrollToBottom()
    })
    bodyResizeObserver.observe(bodyRef.value)
  }
  scrollToBottom()
}

function readSavedDrawerWidth() {
  const width = Number(localStorage.getItem(DRAWER_WIDTH_KEY))
  return Number.isFinite(width) && width > 0 ? Math.max(MIN_DRAWER_WIDTH, Math.round(width)) : 0
}

function handleDrawerMouseDown(event) {
  if (isMobileScreen.value || !event.target?.closest?.('.el-drawer__dragger')) return
  window.removeEventListener('mouseup', rememberDrawerWidth)
  window.addEventListener('mouseup', rememberDrawerWidth, { once: true })
}

function rememberDrawerWidth() {
  requestAnimationFrame(() => {
    const drawer = document.querySelector('.agent_drawer.el-drawer')
    if (!drawer) return
    const width = Math.max(MIN_DRAWER_WIDTH, Math.round(drawer.getBoundingClientRect().width))
    savedDrawerWidth.value = width
    localStorage.setItem(DRAWER_WIDTH_KEY, String(width))
  })
}

function openAgentSettings() {
  $router.push({ path: '/setting', query: { tabKey: 'ai-agent' } })
}

function openPlusSettings() {
  $router.push(state.plusRequired?.activationPath || '/setting?tabKey=plus')
}

// Drawer 的 focus trap 会在打开期间接管焦点；等 opened 后再聚焦输入框。
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

onMounted(() => {
  // 让 markdown 里的代码块带上「复制 / 在终端执行」按钮。
  // custom-id 要与 message-item.vue 里传给 MarkdownRender 的一致。
  setCustomComponents('agent', { code_block: CustomCodeBlock })
})

onBeforeUnmount(() => {
  window.removeEventListener('mouseup', rememberDrawerWidth)
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
    $message.success('已清空运维助手历史会话')
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
.agent_layout {
  position: relative;
  height: 100%;
  overflow: hidden;

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

<style lang="scss">
.agent_drawer {
  &.el-drawer {
    // AI 面板挂在 sticky 顶栏中时，Element Plus 的进入过渡会叠加一次布局
    // 重算，表现为右侧滑入后回弹。移到 body 后禁用这条默认过渡。
    max-width: 100vw;
    transition: none !important;
  }

  .el-drawer__body {
    padding: 0;
    overflow: hidden;
  }
}

@media (min-width: 968px) {
  .agent_drawer.el-drawer {
    min-width: 350px;
  }
}

// modal=false 下 Element Plus 仍会渲染一个全屏容器。让其穿透，
// 仅保留抽屉本身接收点击，背景页面即可继续操作。
.agent_drawer_overlay {
  pointer-events: none;

  .agent_drawer {
    pointer-events: auto;
  }
}
</style>
