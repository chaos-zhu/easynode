<template>
  <div class="approval_prompt" :class="{ 'is_dark': isDark }">
    <div class="prompt_head">
      <el-icon class="head_icon"><WarnTriangleFilled /></el-icon>
      <span class="head_title">需要你确认</span>
      <span class="countdown" :class="{ 'is_urgent': remainingSeconds < 60 }">{{ formattedRemaining }}</span>
    </div>

    <div class="prompt_body">
      <p class="prompt_desc">
        <span>
          <template v-if="item.hostName">
            将在 <strong>{{ item.hostName }}</strong> 上
          </template>
          执行 <strong>{{ toolLabel }}</strong>
        </span>
        <span v-if="item.effect" class="effect_tag">{{ effectLabel }}</span>
      </p>

      <div v-if="item.sensitiveDisclosure" class="sensitive_notice">
        <strong>敏感内容披露</strong>
        <span>批准后将把真实文件或命令输出发送给当前 AI Provider。</span>
      </div>

      <div v-if="writePreview" class="write_preview">
        <dl class="preview_meta">
          <div>
            <dt>操作</dt>
            <dd>{{ writePreview.operation === 'create' ? '新建文件' : '覆盖文件' }}</dd>
          </div>
          <div>
            <dt>路径</dt>
            <dd>{{ writePreview.path }}</dd>
          </div>
          <div v-if="writePreview.realPath && writePreview.realPath !== writePreview.path">
            <dt>真实路径</dt>
            <dd>{{ writePreview.realPath }}</dd>
          </div>
          <div>
            <dt>备份</dt>
            <dd>{{ writePreview.backup ? '写入前创建唯一的时间戳备份' : '不创建备份' }}</dd>
          </div>
          <div>
            <dt>大小</dt>
            <dd>{{ formatBytes(writePreview.oldBytes) }} → {{ formatBytes(writePreview.newBytes) }}</dd>
          </div>
          <div v-if="writePreview.oldMode || writePreview.newMode">
            <dt>权限</dt>
            <dd>{{ writePreview.oldMode || '新文件' }} → {{ writePreview.newMode || '保持默认' }}</dd>
          </div>
        </dl>
        <div class="preview_diff_head">
          <span>完整写入差异</span>
          <el-button
            link
            class="copy_btn"
            title="复制完整差异"
            @click="copyText(writePreview.diff)"
          >
            <el-icon><CopyDocument /></el-icon>
          </el-button>
        </div>
        <pre class="prompt_detail write_diff">{{ writePreview.diff }}</pre>
      </div>

      <div v-else-if="readPreview" class="read_preview">
        <p>请求路径：<code>{{ readPreview.path }}</code></p>
        <p>真实路径：<code>{{ readPreview.realPath }}</code></p>
      </div>

      <div v-else-if="detail" class="prompt_detail_wrap">
        <pre class="prompt_detail">{{ detail }}</pre>
        <el-button
          link
          class="copy_btn"
          title="复制命令"
          @click="copyDetail"
        >
          <el-icon><CopyDocument /></el-icon>
        </el-button>
      </div>

      <div v-if="item.targets?.length && !writePreview && !readPreview" class="prompt_targets">
        <span class="target_label">目标</span>
        <div class="target_list">
          <code v-for="target in item.targets" :key="target">{{ target }}</code>
        </div>
      </div>

      <p v-if="item.risk?.reason && !item.sensitiveDisclosure" class="prompt_risk">
        <strong>{{ item.risk.category || '风险' }}：</strong>{{ item.risk.reason }}
      </p>
    </div>

    <div class="prompt_actions">
      <el-button type="primary" size="small" @click="emit('respond', item.requestId, true, 'once')">
        允许
      </el-button>
      <!-- 高危操作后端不接受会话级授权，按钮也不该出现 -->
      <el-button
        v-if="item.grantable !== false"
        size="small"
        :title="item.grantLabel ? `仅复用完全相同的操作：${ item.grantLabel }` : ''"
        @click="emit('respond', item.requestId, true, 'session')"
      >
        本会话允许同一操作
      </el-button>
      <el-button
        type="danger"
        plain
        size="small"
        @click="emit('respond', item.requestId, false)"
      >
        拒绝
      </el-button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount, getCurrentInstance } from 'vue'
import { CopyDocument, WarnTriangleFilled } from '@element-plus/icons-vue'
import { copyText } from '@/utils/clipboard'

const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  item: {
    type: Object,
    required: true
  },
  // 与后端 APPROVAL_TIMEOUT_MS 保持一致
  timeoutMs: {
    type: Number,
    default: 5 * 60 * 1000
  }
})

const emit = defineEmits(['respond',])

const isDark = computed(() => $store.isDark)
const effectLabel = computed(() => ({ read: '读取', write: '写入', delete: '删除' }[props.item.effect] || props.item.effect))
const now = ref(Date.now())
let timer = null

onMounted(() => {
  timer = setInterval(() => {
    now.value = Date.now()
  }, 1000)
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
})

// 倒计时能让用户知道"不点会怎样"，而不是干等一个没有反馈的弹窗
const remainingSeconds = computed(() => {
  const elapsed = now.value - (props.item.createdAt || now.value)
  return Math.max(0, Math.ceil((props.timeoutMs - elapsed) / 1000))
})

const formattedRemaining = computed(() => {
  const total = remainingSeconds.value
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  return `${ minutes }:${ String(seconds).padStart(2, '0') }`
})

const TOOL_LABELS = {
  exec_command: '执行命令',
  terminal_command: '提交终端命令',
  run_script: '运行脚本',
  read_file: '读取文件',
  write_file: '写入文件'
}

const toolLabel = computed(() => TOOL_LABELS[props.item.tool] || props.item.tool)
const writePreview = computed(() => (
  props.item.tool === 'write_file' && props.item.preview?.type === 'write_file'
    ? props.item.preview
    : null
))
const readPreview = computed(() => (
  props.item.tool === 'read_file' && props.item.preview?.type === 'read_file'
    ? props.item.preview
    : null
))

const detail = computed(() => {
  const input = props.item.input || {}
  if (input.scriptName && input.command) return `${ input.scriptName }\n\n${ input.command }`
  if (input.command) return input.command
  if (input.path) return input.path
  try {
    return JSON.stringify(input, null, 2)
  } catch {
    return ''
  }
})

function copyDetail() {
  copyText(detail.value)
}

function formatBytes(value) {
  const bytes = Number(value) || 0
  if (bytes < 1024) return `${ bytes } B`
  return `${ (bytes / 1024).toFixed(1) } KiB`
}
</script>

<style lang="scss" scoped>
.approval_prompt {
  margin: 10px 0;
  border: 1px solid #e6a23c;
  border-radius: 8px;
  background-color: rgba(230, 162, 60, 0.08);
  overflow: hidden;

  &.is_dark {
    background-color: rgba(230, 162, 60, 0.12);
  }

  .prompt_head {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 12px;
    background-color: rgba(230, 162, 60, 0.15);
    font-size: 13px;
    font-weight: 500;

    .head_icon {
      color: #e6a23c;
    }

    .head_title {
      flex: 1;
    }

    .countdown {
      font-family: 'JetBrains Mono', Menlo, Consolas, monospace;
      font-size: 12px;
      color: #909399;

      &.is_urgent {
        color: #f56c6c;
      }
    }
  }

  .prompt_body {
    padding: 10px 12px 0;
    font-size: 13px;

    .prompt_desc {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 6px;
      margin: 0 0 10px;
      line-height: 1.6;

      .effect_tag {
        padding: 1px 7px;
        border-radius: 999px;
        background-color: rgba(230, 162, 60, 0.16);
        color: #b88230;
        font-size: 12px;
        line-height: 1.6;
      }
    }

    .sensitive_notice {
      display: flex;
      gap: 8px;
      margin-bottom: 10px;
      padding: 8px 10px;
      border-radius: 6px;
      background-color: rgba(230, 162, 60, 0.12);
      color: #b88230;
      line-height: 1.55;

      strong {
        flex: none;
      }
    }

    .prompt_detail_wrap {
      position: relative;
      margin-bottom: 10px;

      .copy_btn {
        position: absolute;
        top: 4px;
        right: 4px;
        width: 28px;
        height: 28px;
        color: var(--el-text-color-secondary);
      }
    }

    .write_preview {
      .preview_meta {
        display: grid;
        gap: 5px;
        margin: 0 0 10px;

        > div {
          display: grid;
          grid-template-columns: 64px minmax(0, 1fr);
          gap: 8px;
        }

        dt {
          color: var(--el-text-color-secondary);
        }

        dd {
          margin: 0;
          overflow-wrap: anywhere;
          font-family: 'JetBrains Mono', Menlo, Consolas, monospace;
        }
      }

      .preview_diff_head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 4px;
        font-weight: 500;
      }

      .write_diff {
        max-height: min(46vh, 520px);
      }
    }

    .read_preview {
      margin-bottom: 8px;

      p {
        margin: 4px 0;
        overflow-wrap: anywhere;
      }
    }

    .prompt_targets {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr);
      align-items: start;
      gap: 8px;
      margin-bottom: 10px;

      .target_label {
        padding-top: 3px;
        color: var(--el-text-color-secondary);
        font-size: 12px;
      }

      .target_list {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        min-width: 0;
      }

      code {
        padding: 2px 7px;
        border: 1px solid rgba(230, 162, 60, 0.18);
        border-radius: 5px;
        background-color: rgba(230, 162, 60, 0.08);
        overflow-wrap: anywhere;
        font-size: 12px;
      }
    }

    .prompt_detail {
      margin: 0;
      padding: 8px 40px 8px 10px;
      max-height: 160px;
      overflow: auto;
      border-radius: 6px;
      background-color: rgba(0, 0, 0, 0.06);
      font-family: 'JetBrains Mono', Menlo, Consolas, monospace;
      font-size: 12px;
      line-height: 1.6;
      white-space: pre-wrap;
      word-break: break-all;
    }

    .prompt_risk {
      margin: 0;
      padding: 8px 10px;
      border-left: 3px solid rgba(230, 162, 60, 0.7);
      border-radius: 5px;
      background-color: rgba(230, 162, 60, 0.08);
      color: #b88230;
      line-height: 1.6;
    }
  }

  .prompt_actions {
    display: flex;
    justify-content: flex-end;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 10px;
    padding: 10px 12px;
    border-top: 1px solid rgba(230, 162, 60, 0.18);

    :deep(.el-button) {
      margin-left: 0;
    }
  }

  &.is_dark .prompt_body .prompt_detail {
    background-color: rgba(0, 0, 0, 0.35);
  }
}
</style>
