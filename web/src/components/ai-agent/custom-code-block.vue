<template>
  <div class="custom_code_block" :class="{ 'is_dark': isDark }">
    <!-- 代码块头部 -->
    <div class="code_block_header">
      <span class="language_label">{{ languageLabel }}</span>
      <div class="code_header_actions">
        <span
          class="code_action_btn code_copy_btn"
          title="复制代码"
          @click="handleCopy"
        >
          复制
        </span>
        <span
          v-if="canExecute"
          class="code_action_btn code_exec_btn"
          title="发送到当前终端执行"
          @click="handleExec"
        >
          执行
        </span>
      </div>
    </div>
    <!-- 代码内容 -->
    <CodeBlockNode
      class="code_block_content"
      :node="node"
      :is-dark="isDark"
      :loading="loading"
      :stream="stream"
      :theme="codeBlockTheme"
      :code-block-options="codeBlockOptions"
      :show-header="false"
    />
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { ElMessage } from 'element-plus'
import { CodeBlockNode } from 'markstream-vue'
import clipboard from '@/utils/clipboard'
import { EventBus } from '@/utils'

const props = defineProps({
  node: {
    type: Object,
    required: true
  },
  loading: {
    type: Boolean,
    default: false
  },
  stream: {
    type: Boolean,
    default: false
  },
  isDark: {
    type: Boolean,
    default: false
  },
  customId: {
    type: String,
    default: ''
  }
})

const codeBlockTheme = { dark: 'dark-plus', light: 'github-light' }
const codeBlockOptions = {
  fontFamily: 'SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace',
  fontSize: 13,
  lineHeight: 19.5,
  padding: 12,
  disableLineNumbers: true,
  overflow: 'scroll',
  diffStyle: 'unified',
  mergeConflict: false
}

// 全局 AI 助手的代码块没有执行入口；只有绑定到某个 Web 终端的 AI 对话才允许。
const canExecute = computed(() => props.customId.startsWith('terminal-agent-'))

// 获取语言标签
const languageLabel = computed(() => {
  return props.node.language || (props.node.diff ? 'diff' : 'text')
})

// 处理复制
const handleCopy = () => {
  const code = props.node.diff ? props.node.raw : props.node.code
  clipboard.copy(code)
}

const handleExec = () => {
  const command = String(props.node?.code || props.node?.value || '').trim()
  if (!command) return ElMessage.warning('代码内容为空')
  // 通过唯一 channel 回到对应的终端 AI 面板，避免多个终端 tab 同时执行。
  EventBus.$emit('terminal_ai_execute_code', { channel: props.customId, command })
}

</script>

<style lang="scss" scoped>
.custom_code_block {
  --markstream-code-theme-bg: #fff;
  --markstream-code-theme-fg: #24292e;
  width: 100%;
  border-radius: 6px;
  overflow: hidden;
  margin: 8px 0;
  border: 1px solid rgba(0, 0, 0, 0.1);

  &.is_dark {
    --markstream-code-theme-bg: #1e1e1e;
    --markstream-code-theme-fg: #d4d4d4;
    border-color: rgba(255, 255, 255, 0.1);

    .code_block_header {
      background-color: #2d2d2d;
      border-bottom-color: rgba(255, 255, 255, 0.1);

      .language_label {
        color: #aaa;
      }

      .code_action_btn {
        color: #8b949e;

        &:hover {
          color: #58a6ff;
          background-color: rgba(255, 255, 255, 0.1);
        }
      }
    }
  }

  .code_block_header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 12px;
    background-color: #f6f8fa;
    border-bottom: 1px solid rgba(0, 0, 0, 0.1);

    .language_label {
      font-size: 12px;
      color: #666;
      font-weight: 500;
    }

    .code_header_actions {
      display: flex;
      align-items: center;
      flex-shrink: 0;

      .code_action_btn {
        padding: 4px 6px;
        font-size: 12px;
        color: #666;
        cursor: pointer;
        border-radius: 4px;
        transition: all 0.2s;
        white-space: nowrap;
        user-select: none;

        &:hover {
          color: var(--el-color-primary);
          background-color: rgba(0, 0, 0, 0.05);
        }

        &.code_exec_btn:hover {
          color: var(--el-color-primary);
        }
      }
    }
  }

  .code_block_content {
    min-width: 0;
    margin: 0;
    border: 0;
    border-radius: 0;
    box-shadow: none;
  }
}
</style>
