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
          class="code_action_btn code_exec_btn"
          title="在终端执行"
          @click="handleExec"
        >
          执行
        </span>
      </div>
    </div>
    <!-- 代码内容 -->
    <div class="code_block_content">
      <pre><code :class="languageClass" v-html="highlightedCode" /></pre>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { EventBus } from '@/utils'
import { ElMessage } from 'element-plus'
import hljs from 'highlight.js'
import clipboard from '@/utils/clipboard'

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
  customId: {
    type: String,
    default: ''
  },
  indexKey: {
    type: [String, Number,],
    default: ''
  }
})

// 从 store 获取暗色模式状态
import useStore from '@/store'
const $store = useStore()
const isDark = computed(() => $store.isDark)

// 获取语言标签
const languageLabel = computed(() => {
  const lang = props.node?.language || props.node?.lang || ''
  return lang || 'text'
})

// 获取语言类名
const languageClass = computed(() => {
  const lang = props.node?.language || props.node?.lang || ''
  return lang ? `language-${ lang }` : ''
})

// HTML 转义
const escapeHtml = (text) => {
  const map = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    '\'': '&#039;'
  }
  return text.replace(/[&<>"']/g, m => map[m])
}

// 高亮代码
const highlightedCode = computed(() => {
  const code = props.node?.code || props.node?.value || ''
  const lang = props.node?.language || props.node?.lang || ''

  if (!code) return ''

  try {
    if (lang && hljs.getLanguage(lang)) {
      return hljs.highlight(code, { language: lang }).value
    }
    return hljs.highlightAuto(code).value
  } catch (e) {
    // 如果高亮失败，返回转义后的原始代码
    return escapeHtml(code)
  }
})

// 处理复制
const handleCopy = () => {
  const code = props.node?.code || props.node?.value || ''
  clipboard.copy(code)
}

// 处理执行
const handleExec = () => {
  const code = (props.node?.code || props.node?.value || '').trim()
  if (!code) {
    ElMessage.warning('代码内容为空')
    return
  }
  // 通过 EventBus 发送执行命令
  EventBus.$emit('exec_external_command', code)
}
</script>

<style lang="scss" scoped>
.custom_code_block {
  width: 100%;
  border-radius: 6px;
  overflow: hidden;
  margin: 8px 0;
  border: 1px solid rgba(0, 0, 0, 0.1);

  &.is_dark {
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

    .code_block_content {
      background-color: #1e1e1e;

      pre {
        background-color: #1e1e1e;

        code {
          color: #d4d4d4;
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
    background-color: #f6f8fa;

    pre {
      margin: 0;
      padding: 12px;
      overflow-x: auto;
      background-color: #f6f8fa;

      code {
        font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
        font-size: 13px;
        line-height: 1.5;
        color: #24292e;
        white-space: pre;
        word-break: normal;
        word-wrap: normal;
      }
    }
  }
}
</style>