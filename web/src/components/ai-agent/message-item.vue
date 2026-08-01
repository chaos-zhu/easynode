<template>
  <div
    class="message_item"
    :class="[`is_${message.role}`, { 'is_dark': isDark, 'is_editing': editing }]"
  >
    <div v-if="message.role === 'user'" class="user_message">
      <div v-if="editing" class="message_edit_container">
        <el-input
          ref="editInputRef"
          v-model="editingText"
          class="message_edit_input"
          type="textarea"
          :autosize="{ minRows: 3, maxRows: 10 }"
          placeholder="编辑消息内容"
          resize="none"
          @keydown.esc.stop="emit('cancel-edit')"
          @keyup.enter.ctrl="confirmEdit"
          @keyup.enter.meta="confirmEdit"
        />
        <div class="edit_actions">
          <span class="edit_shortcut">Ctrl / ⌘ + Enter 发送</span>
          <div class="edit_action_buttons">
            <el-button
              size="small"
              round
              @click="emit('cancel-edit')"
            >
              取消
            </el-button>
            <el-button
              type="primary"
              size="small"
              round
              @click="confirmEdit"
            >
              发送
            </el-button>
          </div>
        </div>
      </div>

      <div v-else class="user_content">
        <div class="user_bubble" :class="{ 'is_dark': isDark }">{{ userText }}</div>
        <div class="user_actions">
          <time v-if="formattedTime" class="message_time" :datetime="messageDateTime">
            {{ formattedTime }}
          </time>
          <button
            v-if="editable"
            type="button"
            class="user_edit_button"
            title="编辑消息"
            aria-label="编辑消息"
            @click="emit('start-edit')"
          >
            <el-icon><EditPen /></el-icon>
          </button>
          <button
            type="button"
            class="user_copy_button"
            title="复制消息"
            aria-label="复制消息"
            @click="copyMessage"
          >
            <el-icon><CopyDocument /></el-icon>
          </button>
        </div>
      </div>
    </div>

    <div v-else class="assistant_body" :class="{ 'has_actions': showAssistantActions }">
      <template v-for="(part, index) in message.parts" :key="`${message.id}-${index}`">
        <ReasoningBlock v-if="part.type === 'reasoning'" :part="part" />

        <ToolCallCard v-else-if="part.type === 'tool'" :part="part" />

        <MarkdownRender
          v-else-if="part.text"
          class="markdown_body"
          :content="part.text"
          :is-dark="isDark"
          :typewriter="true"
          :code-block-stream="running"
          :custom-id="codeBlockCustomId"
        />
      </template>

      <div v-if="waitingForModel" class="placeholder">
        <el-icon class="is_spin"><Loading /></el-icon>
        <span>正在分析工具结果…</span>
      </div>
      <div v-else-if="isEmpty" class="placeholder">
        <el-icon class="is_spin"><Loading /></el-icon>
        <span>正在思考…</span>
      </div>

      <div v-if="showAssistantActions" class="assistant_actions">
        <button
          type="button"
          class="assistant_action_button"
          title="复制回答"
          aria-label="复制回答"
          @click="copyAssistantMessage"
        >
          <el-icon><CopyDocument /></el-icon>
        </button>

        <el-tooltip
          :content="usageTooltip"
          placement="top"
          :show-after="250"
        >
          <button
            type="button"
            class="assistant_action_button"
            aria-label="查看 Token 用量"
          >
            <el-icon><InfoFilled /></el-icon>
          </button>
        </el-tooltip>

        <button
          type="button"
          class="assistant_action_button"
          :class="{ 'is_disabled': !regeneratable }"
          :disabled="!regeneratable"
          title="重新生成"
          aria-label="重新生成"
          @click="emit('regenerate', message)"
        >
          <el-icon><RefreshRight /></el-icon>
        </button>

        <button
          type="button"
          class="assistant_action_button"
          title="分支到新对话"
          aria-label="分支到新对话"
          @click="emit('fork', message)"
        >
          <el-icon><Share /></el-icon>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, getCurrentInstance, nextTick, ref, watch } from 'vue'
import MarkdownRender from 'markstream-vue'
import dayjs from 'dayjs'
import {
  CopyDocument, EditPen, InfoFilled, Loading, RefreshRight, Share
} from '@element-plus/icons-vue'
import clipboard from '@/utils/clipboard'
import ReasoningBlock from './reasoning-block.vue'
import ToolCallCard from './tool-call-card.vue'

const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  message: {
    type: Object,
    required: true
  },
  running: {
    type: Boolean,
    default: false
  },
  waitingForModel: {
    type: Boolean,
    default: false
  },
  editable: {
    type: Boolean,
    default: false
  },
  editing: {
    type: Boolean,
    default: false
  },
  regeneratable: {
    type: Boolean,
    default: false
  },
  codeBlockCustomId: {
    type: String,
    default: 'agent'
  }
})

const emit = defineEmits(['start-edit', 'cancel-edit', 'confirm-edit', 'regenerate', 'fork',])

// Drawer 被 teleport 到 body 后，仍以 html.dark 作为兜底主题来源。
const isDark = computed(() => $store.isDark || document.documentElement.classList.contains('dark'))
const editingText = ref('')
const editInputRef = ref(null)

const userText = computed(() => props.message.parts.map((part) => part.text || '').join(''))
const messageTimestamp = computed(() => Number(props.message.createdAt) || 0)
const formattedTime = computed(() => (
  messageTimestamp.value ? dayjs(messageTimestamp.value).format('M月D日 H:mm') : ''
))
const messageDateTime = computed(() => (
  messageTimestamp.value ? new Date(messageTimestamp.value).toISOString() : ''
))
const assistantText = computed(() => props.message.parts
  .filter((part) => part.type === 'text' && part.text)
  .map((part) => part.text)
  .join('\n\n'))
const hasAssistantContent = computed(() => (
  props.message.role === 'assistant' && props.message.parts.length > 0
))
const showAssistantActions = computed(() => hasAssistantContent.value && !props.running)
const usageTooltip = computed(() => {
  const usage = props.message.usage
  if (!usage) return props.running ? '生成完成后显示 Token 用量' : '暂无 Token 用量信息'

  const items = [
    `总计 ${ formatTokens(usage.totalTokens) }`,
    `输入 ${ formatTokens(usage.inputTokens) }`,
    `输出 ${ formatTokens(usage.outputTokens) }`,
  ]
  if (usage.cachedInputTokens) items.push(`缓存 ${ formatTokens(usage.cachedInputTokens) }`)
  if (usage.reasoningTokens) items.push(`推理 ${ formatTokens(usage.reasoningTokens) }`)
  return `Token：${ items.join(' · ') }`
})

// 助手消息刚创建时还没有任何 part，需要占位，否则界面看着像卡住了
const isEmpty = computed(() => props.message.parts.length === 0 && props.running)

watch(() => props.editing, (editing) => {
  if (!editing) return
  editingText.value = userText.value
  nextTick(() => editInputRef.value?.focus())
})

watch(() => props.editable, (editable) => {
  if (!editable && props.editing) emit('cancel-edit')
})

function confirmEdit() {
  emit('confirm-edit', props.message, editingText.value.trim())
}

function copyMessage() {
  clipboard.copy(userText.value)
}

function copyAssistantMessage() {
  clipboard.copy(assistantText.value)
}

function formatTokens(value) {
  return (Number(value) || 0).toLocaleString('en-US')
}
</script>

<style lang="scss" scoped>
.message_item {
  margin-bottom: 16px;

  &.is_user {
    display: flex;
    justify-content: flex-end;

    .user_message {
      max-width: 85%;

      .user_content {
        position: relative;
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        // 固定为 hover 操作区预留高度，显隐时消息列表不会上下跳动。
        padding-bottom: 28px;

        .user_bubble {
          padding: 10px 16px;
          border-radius: 20px;
          background-color: #f2f3f5;
          color: var(--el-text-color-primary);
          font-size: 14px;
          line-height: 1.65;
          white-space: pre-wrap;
          word-break: break-word;

          &.is_dark {
            background-color: #292929;
            color: #e5e7eb;
          }
        }

        .user_actions {
          position: absolute;
          right: 0;
          bottom: 0;
          display: flex;
          align-items: center;
          justify-content: flex-end;
          gap: 4px;
          width: max(100%, 170px);
          height: 28px;
          color: var(--el-text-color-secondary);
          opacity: 0;
          pointer-events: none;
          transform: translateY(-2px);
          transition: opacity 0.15s ease, transform 0.15s ease;

          .message_time {
            margin-right: auto;
            font-size: 12px;
            line-height: 1;
            white-space: nowrap;
          }

          .user_edit_button,
          .user_copy_button {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 28px;
            height: 28px;
            padding: 0;
            border: 0;
            border-radius: 7px;
            background: transparent;
            color: inherit;
            cursor: pointer;
            font-size: 17px;
            transition: color 0.15s ease, background-color 0.15s ease;

            &:hover,
            &:focus-visible {
              outline: none;
              background-color: var(--el-fill-color);
              color: var(--el-text-color-primary);
            }
          }
        }
      }

      &:hover .user_actions,
      &:focus-within .user_actions {
        opacity: 1;
        pointer-events: auto;
        transform: translateY(0);
      }

      .message_edit_container {
        box-sizing: border-box;
        width: 100%;
        padding: 20px 22px;
        border-radius: 24px;
        background-color: #f2f3f5;

        :deep(.message_edit_input .el-textarea__inner) {
          min-height: 96px !important;
          padding: 0;
          border: 0;
          box-shadow: none;
          background: transparent;
          color: var(--el-text-color-primary);
          font-family: inherit;
          font-size: 15px;
          line-height: 1.65;

          &:focus {
            box-shadow: none;
          }
        }

        .edit_actions {
          display: flex;
          align-items: center;
          justify-content: flex-end;
          gap: 12px;
          margin-top: 18px;

          .edit_shortcut {
            margin-right: auto;
            color: var(--el-text-color-secondary);
            font-size: 12px;
          }

          .edit_action_buttons {
            display: flex;
            gap: 8px;

            :deep(.el-button) {
              margin: 0;
            }
          }
        }
      }
    }

    &.is_editing {
      justify-content: flex-end;

      .user_message {
        width: 100%;
        max-width: 100%;
      }
    }

    &.is_dark .message_edit_container {
      background-color: #2d2d2d;
    }
  }

  .assistant_body {
    position: relative;
    font-size: 14px;
    line-height: 1.7;

    &.has_actions {
      padding-bottom: 32px;
    }

    .markdown_body {
      :deep(p:first-child) { margin-top: 0; }
      :deep(p:last-child) { margin-bottom: 0; }

      // 保留流式逐字渲染，但不展示 Markstream 的输入光标。
      :deep(.typewriter-cursor),
      :deep(.markstream-vue.typewriter-simple-cursor .typewriter-simple-cursor-target::after) {
        display: none !important;
      }
    }

    .placeholder {
      display: flex;
      align-items: center;
      gap: 6px;
      color: #909399;
      font-size: 13px;

      .is_spin {
        animation: msg_spin 1s linear infinite;
      }
    }

    .assistant_actions {
      position: absolute;
      bottom: 0;
      left: 0;
      display: flex;
      align-items: center;
      gap: 6px;
      height: 28px;
      color: var(--el-text-color-secondary);
      opacity: 0;
      pointer-events: none;
      transform: translateY(-2px);
      transition: opacity 0.15s ease, transform 0.15s ease;

      .assistant_action_button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
        padding: 0;
        border: 0;
        border-radius: 7px;
        background: transparent;
        color: inherit;
        cursor: pointer;
        font-size: 16px;
        transition: color 0.15s ease, background-color 0.15s ease;

        &:hover,
        &:focus-visible {
          outline: none;
          background-color: var(--el-fill-color);
          color: var(--el-text-color-primary);
        }

        &.is_disabled {
          cursor: not-allowed;
          opacity: 0.45;
        }

      }
    }
  }

  &.is_assistant:hover .assistant_actions,
  &.is_assistant:focus-within .assistant_actions {
    opacity: 1;
    pointer-events: auto;
    transform: translateY(0);
  }
}

@media (hover: none) {
  .message_item.is_user .user_message .user_content .user_actions,
  .message_item.is_assistant .assistant_actions {
    opacity: 1;
    pointer-events: auto;
    transform: translateY(0);
  }
}

@media (max-width: 520px) {
  .message_item.is_user {
    .user_message {
      max-width: 92%;

      .message_edit_container {
        padding: 16px;

        .edit_actions {
          align-items: flex-end;

          .edit_shortcut {
            display: none;
          }
        }
      }
    }

    &.is_editing .user_message {
      max-width: 100%;
    }
  }
}

@keyframes msg_spin {
  to { transform: rotate(360deg); }
}
</style>
