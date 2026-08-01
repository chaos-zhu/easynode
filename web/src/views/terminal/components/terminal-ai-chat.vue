<template>
  <section
    class="terminal_ai_chat"
    :class="{ 'is_dark': isDark }"
    @pointerdown.stop
    @mousedown.stop
    @click.stop
    @keydown.stop
  >
    <header class="chat_header">
      <el-button link title="历史会话" @click="showSessions = !showSessions">
        <el-icon><Expand v-if="!showSessions" /><Fold v-else /></el-icon>
      </el-button>
      <span class="chat_title" :title="host.name">{{ state.title || `${ host.name } AI 助手` }}</span>
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
        scope="terminal"
        :tools="options.tools"
        :preset="settings.terminalPermission"
        :selected-host-count="1"
        :host-name="host.name"
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
        @click="emit('close')"
      >
        <el-icon><Close /></el-icon>
      </el-button>
    </header>

    <SessionList
      v-if="showSessions"
      class="session_list"
      :sessions="sessions"
      :active-id="state.sessionId"
      :clear-scope-label="`当前终端「${ host.name }」`"
      @select="handleSelectSession"
      @create="handleNewSession"
      @remove="handleRemoveSession"
      @clear="handleClearSessions"
      @rename="renameSession"
    />

    <el-alert
      v-if="connectError"
      class="chat_alert"
      type="error"
      :title="connectError"
      :closable="false"
      show-icon
    />
    <el-alert
      v-else-if="state.plusRequired"
      class="chat_alert plus_required_alert"
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
      v-else-if="historyNotice"
      class="chat_alert"
      type="warning"
      :title="historyNotice"
      show-icon
    />

    <el-scrollbar ref="scrollRef" class="chat_body" @scroll="handleScroll">
      <div ref="bodyRef" class="body_inner">
        <div v-if="!state.messages.length" class="empty_state">
          <el-icon class="empty_icon"><ChatDotRound /></el-icon>
          <p>{{ host.name }} 的终端 AI 助手</p>
          <span>AI 命令会在当前终端执行，并自动读取本次输出</span>
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
          :code-block-custom-id="codeBlockCustomId"
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
        <p v-if="state.stopping" class="turn_stopping">正在中断远端命令，等待终端确认…</p>
        <p v-else-if="state.terminalCancelWarning" class="turn_error">{{ state.terminalCancelWarning }}</p>
        <p v-else-if="state.aborted" class="turn_aborted">已停止生成</p>
      </div>
    </el-scrollbar>

    <footer class="chat_footer">
      <ChatSender
        ref="senderRef"
        v-model:value="draft"
        :loading="state.running"
        placeholder="输入任务或问题，Enter 发送"
        @submit="handleSend"
        @cancel="stop"
      />
      <div class="footer_controls">
        <ModeSwitcher :model-value="settings.terminalPermission" :presets="presets" @change="setTerminalPermission" />
        <el-select
          :model-value="settings.modelId"
          size="small"
          class="model_select"
          placeholder="选择模型"
          filterable
          @update:model-value="setModel"
        >
          <el-option
            v-for="model in options.models"
            :key="model"
            :label="model"
            :value="model"
          />
        </el-select>
      </div>
    </footer>
  </section>
</template>

<script setup>
import { computed, getCurrentInstance, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { ChatDotRound, Close, Expand, Fold, Plus, Setting } from '@element-plus/icons-vue'
import { setCustomComponents } from 'markstream-vue'
import ChatSender from '@/components/common/chat-sender.vue'
import MessageItem from '@/components/ai-agent/message-item.vue'
import ApprovalPrompt from '@/components/ai-agent/approval-prompt.vue'
import ModeSwitcher from '@/components/ai-agent/mode-switcher.vue'
import SessionList from '@/components/ai-agent/session-list.vue'
import AssistantInfoPopover from '@/components/ai-agent/assistant-info-popover.vue'
import { useAgentSession } from '@/composables/useAgentSession'
import { findPreviousUserMessage, findUserTurnIndex, messageText } from '@/composables/agentMessages'
import $api from '@/api'
import CustomCodeBlock from '@/components/ai-agent/custom-code-block.vue'
import { PRESET_FALLBACK } from '@/components/ai-agent/presets'
import { EventBus } from '@/utils'

const props = defineProps({
  host: { type: Object, required: true },
  terminal: { type: Function, required: true },
  prefill: { type: String, default: '' }
})

const emit = defineEmits(['close', 'consume-prefill',])
const vueInstance = getCurrentInstance()
const { proxy: { $message, $store, $router } } = vueInstance
const codeBlockCustomId = `terminal-agent-${ vueInstance.uid }`
const senderRef = ref(null)
const scrollRef = ref(null)
const bodyRef = ref(null)
const draft = ref('')
const showSessions = ref(false)
const editingMessageId = ref('')
let autoFollow = true
let bodyResizeObserver = null
const isDark = computed(() => $store.isDark)
const presets = computed(() => (options.presets.length ? options.presets : PRESET_FALLBACK))

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
  setTerminalPermission
} = useAgentSession({
  scope: 'terminal',
  hostId: props.host.id,
  onTerminalCommand: ({ command, hostId, requestId, reportProgress }) => {
    if (hostId !== props.host.id) return { ok: false, error: '终端命令目标已变化' }
    return props.terminal()?.executeAiCommand(command, { requestId, onProgress: reportProgress }) || { ok: false, error: '当前终端不可用' }
  },
  onTerminalCommandCancel: ({ requestId }) => {
    return props.terminal()?.cancelAiCommand?.(requestId) || { ok: false, error: '当前终端不可用，无法确认命令已停止' }
  }
})

function focusSender() {
  nextTick(() => {
    requestAnimationFrame(() => {
      senderRef.value?.refreshLayout?.()
      senderRef.value?.focus()
    })
  })
}

function openAgentSettings() {
  $router.push({ path: '/setting', query: { tabKey: 'ai-agent' } })
}

function openPlusSettings() {
  $router.push(state.plusRequired?.activationPath || '/setting?tabKey=plus')
}

function handleCodeBlockExecution({ channel, command } = {}) {
  if (channel !== codeBlockCustomId) return
  const result = props.terminal()?.executeManualCommand?.(command)
  if (!result?.ok) return $message.error(result?.error || '当前终端不可用')
  $message.success('命令已发送到当前终端')
}

function terminalContext() {
  const terminal = props.terminal()
  if (!terminal?.isAiTerminalConnected?.()) return null
  return {
    hostName: props.host.name,
    capturedAt: Date.now(),
    // 终端画面属于展示层，不能每轮原样塞入模型上下文。AI 命令结果会以
    // 结构化 tool result 持久化；这里只声明当前交互终端仍可用。
    output: ''
  }
}

function handleSend(text) {
  if (!connected.value) return $message.error('未连接到服务端')
  if (!settings.modelId) return $message.warning('请先在 AI 设置中配置模型')
  const context = terminalContext()
  if (!context) return $message.warning('当前终端未连接，无法读取上下文')
  draft.value = ''
  send(text, { terminalContext: context })
  scrollToBottom()
}

function handleNewSession() {
  if (state.running) return $message.warning('请先停止当前对话')
  resetConversation()
  showSessions.value = false
  focusSender()
}

async function handleSelectSession(id) {
  try {
    await loadSession(id)
    showSessions.value = false
    scrollToBottom()
  } catch (error) {
    $message.error(error.message || '加载会话失败')
  }
}

async function handleRemoveSession(id) {
  await removeSession(id)
}

async function handleClearSessions() {
  if (state.running) return $message.warning('当前任务仍在执行，请先停止后再清空历史')
  try {
    await clearSessions()
    showSessions.value = false
    $message.success(`已清空 ${ props.host.name } 的终端助手历史会话`)
  } catch (error) {
    $message.error(error.message || '清空历史会话失败')
  }
}

async function handleConfirmEdit(message, content) {
  if (!content) return $message.warning('消息内容不能为空')
  try {
    const context = terminalContext()
    if (!context) return $message.warning('当前终端未连接，无法读取上下文')
    await editAndResend(message, content, { terminalContext: context })
    editingMessageId.value = ''
    scrollToBottom()
  } catch (error) {
    $message.error(error.message || '编辑消息失败')
  }
}

async function handleRegenerate(message) {
  if (state.running) return $message.warning('请等待当前任务结束后再重新生成')
  const userMessage = findPreviousUserMessage(state.messages, message.id)
  if (!userMessage) return $message.warning('未找到这条回答对应的问题')

  const content = messageText(userMessage)
  if (!content) return $message.warning('原消息内容为空，无法重新生成')

  try {
    const context = terminalContext()
    if (!context) return $message.warning('当前终端未连接，无法读取上下文')
    await editAndResend(userMessage, content, { terminalContext: context })
    editingMessageId.value = ''
    scrollToBottom()
  } catch (error) {
    $message.error(error.message || '重新生成失败')
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
    $message.error(error.message || '创建分支会话失败')
  }
}

async function editAndResend(message, content, extra) {
  if (!state.sessionId) throw new Error('当前消息尚未保存，请稍后再试')
  const messageIndex = state.messages.findIndex((item) => item.id === message.id)
  const turnIndex = state.messages
    .filter((item) => item.role === 'user')
    .findIndex((item) => item.id === message.id)
  if (messageIndex === -1 || turnIndex === -1) throw new Error('未找到要编辑的消息')

  const { data } = await $api.editAgentSessionMessage(state.sessionId, { turnIndex, content })
  state.messages.splice(messageIndex)
  state.pendingApprovals.splice(0)
  state.title = data.title
  state.usage = { ...state.usage, ...(data.usage || {}) }
  state.turnUsage = { inputTokens: 0, outputTokens: 0, totalTokens: 0, cachedInputTokens: 0, reasoningTokens: 0 }
  state.aborted = false
  state.error = null
  state.finishReason = ''
  send(content, extra)
}

function scrollToBottom() {
  autoFollow = true
  nextTick(() => {
    const wrap = scrollRef.value?.wrapRef
    if (!wrap) return
    wrap.scrollTop = wrap.scrollHeight
  })
}

function handleScroll({ scrollTop }) {
  const wrap = scrollRef.value?.wrapRef
  if (!wrap) return
  autoFollow = wrap.scrollHeight - scrollTop - wrap.clientHeight < 40
}

watch(() => props.prefill, (value) => {
  if (!value) return
  draft.value = value
  emit('consume-prefill')
  focusSender()
}, { immediate: true })

onMounted(() => {
  // 终端助手专用的代码块带执行按钮；channel 与当前面板绑定，避免跨 tab 发送。
  setCustomComponents(codeBlockCustomId, { code_block: CustomCodeBlock })
  EventBus.$on('terminal_ai_execute_code', handleCodeBlockExecution)
  connect()
  refreshSessions()
  focusSender()
  bodyResizeObserver = new ResizeObserver(() => {
    if (autoFollow) scrollToBottom()
  })
  if (bodyRef.value) bodyResizeObserver.observe(bodyRef.value)
  scrollToBottom()
  // 终端 tab 可能在同一帧留下一个延迟 focus；等侧栏最终宽度落定后再刷新一次。
  window.setTimeout(focusSender, 80)
})

onBeforeUnmount(() => {
  EventBus.$off('terminal_ai_execute_code', handleCodeBlockExecution)
  bodyResizeObserver?.disconnect()
})
</script>

<style lang="scss" scoped>
.terminal_ai_chat {
  height: 100%;
  min-width: 0;
  display: flex;
  flex-direction: column;
  position: relative;
  z-index: 1;
  pointer-events: auto;
  isolation: isolate;
  border-left: 1px solid var(--el-border-color);
  background: var(--el-bg-color);

  &.is_dark { background: #141414; }

  .chat_header, .chat_footer {
    flex-shrink: 0;
    padding: 8px 10px;
    border-bottom: 1px solid var(--el-border-color);
  }

  .chat_header {
    min-height: 42px;
    display: flex;
    align-items: center;
    gap: 6px;
    .chat_title { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 600; }
    .header_spacer { flex: 1; }
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

  .session_list {
    position: absolute;
    z-index: 20;
    top: 43px;
    height: min(75vh, calc(100% - 43px));
    left: 0;
    width: 78%;
    max-width: 340px;
    border-right: 1px solid var(--el-border-color);
    background: var(--el-bg-color);
    box-shadow: 4px 0 12px rgba(0, 0, 0, 0.14);
  }

  .chat_alert { margin: 8px 10px 0; }
  .plus_required_alert {
    --el-alert-padding: 9px 40px;
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
      right: 12px;
      transform: translateY(-50%);
    }

    .plus_alert_message { font-weight: 500; }
    .plus_activation_button {
      height: 24px;
      margin: 0;
      padding: 0 4px;
      font-size: 13px;
      font-weight: 600;
    }
  }
  .chat_body { flex: 1; min-height: 0; }
  .body_inner { padding: 14px 12px; }
  .empty_state { padding: 48px 12px; text-align: center; color: var(--el-text-color-secondary); }
  .empty_icon { font-size: 32px; }
  .empty_state p { margin: 12px 0 6px; font-size: 16px; color: var(--el-text-color-primary); }
  .empty_state span { font-size: 12px; }
  .turn_error, .turn_aborted, .turn_stopping { padding: 8px 10px; color: var(--el-color-danger); }
  .turn_aborted { color: var(--el-color-warning); }
  .turn_stopping { color: var(--el-color-warning); }

  .chat_footer { border-top: 1px solid var(--el-border-color); border-bottom: 0; }
  .footer_controls { display: flex; gap: 8px; margin-top: 8px; align-items: center; }
  .model_select { width: 150px; }
}
</style>
