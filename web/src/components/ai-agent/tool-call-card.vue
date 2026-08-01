<template>
  <div class="tool_card" :class="[`is_${part.status}`, { 'is_dark': isDark }]">
    <div class="tool_head" @click="expanded = !expanded">
      <el-icon class="toggle_icon" :class="{ 'is_expanded': expanded }"><ArrowRight /></el-icon>

      <span class="tool_name">{{ toolLabel }}</span>

      <code v-if="summary" class="tool_summary" :title="summary">{{ summary }}</code>

      <span v-else class="tool_spacer" />

      <span v-if="part.risk?.level" class="risk_tag" :class="`risk_${part.risk.level}`">
        {{ part.risk.level === 'deny' ? '已拦截' : '需审查' }}
      </span>

      <span v-if="part.approval" class="approval_tag">
        {{ part.approval.approved ? (part.approval.cached ? '本会话已授权' : '已批准') : '已拒绝' }}
      </span>

      <span v-if="isRunningWithProgress" class="progress_tag">实时输出</span>

      <span v-if="part.durationMs !== undefined" class="duration">{{ formattedDuration }}</span>

      <el-icon v-if="part.status === 'running'" class="status_icon is_spin"><Loading /></el-icon>
      <el-icon v-else-if="part.status === 'awaiting-approval'" class="status_icon is_waiting"><Clock /></el-icon>
      <el-icon v-else-if="part.status === 'done'" class="status_icon is_ok"><CircleCheck /></el-icon>
      <el-icon v-else-if="part.status === 'denied'" class="status_icon is_denied"><CircleClose /></el-icon>
      <el-icon v-else class="status_icon is_error"><WarningFilled /></el-icon>
    </div>

    <div v-if="expanded" class="tool_body">
      <div v-if="part.risk?.reason" class="risk_reason">
        <strong>{{ part.risk.category || '风险提示' }}：</strong>{{ part.risk.reason }}
      </div>

      <div class="body_section">
        <div class="section_label">参数</div>
        <pre class="section_content">{{ formattedInput }}</pre>
      </div>

      <div v-if="part.error" class="body_section">
        <div class="section_label">错误</div>
        <pre class="section_content is_error_text">{{ part.error }}</pre>
      </div>

      <div v-else-if="isRunningWithProgress" class="body_section">
        <div class="section_label">实时终端输出</div>
        <pre class="section_content">{{ part.progressOutput }}</pre>
      </div>

      <div v-else-if="hasOutput" class="body_section">
        <div class="section_label">
          结果
          <el-button
            link
            size="small"
            class="copy_btn"
            @click.stop="copyOutput"
          >
            <el-icon><CopyDocument /></el-icon>
          </el-button>
        </div>
        <pre class="section_content">{{ formattedOutput }}</pre>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance, watch } from 'vue'
import { ArrowRight, Loading, CircleCheck, CircleClose, WarningFilled, Clock, CopyDocument } from '@element-plus/icons-vue'
import clipboard from '@/utils/clipboard'

const { proxy: { $message, $store } } = getCurrentInstance()

const props = defineProps({
  part: {
    type: Object,
    required: true
  }
})

// 失败和被拦截的调用默认展开 —— 用户最需要看的就是这两种
const expanded = ref(['error', 'denied',].includes(props.part.status))
const isDark = computed(() => $store.isDark)

const TOOL_LABELS = {
  host_list: '查询主机列表',
  host_status: '获取主机状态',
  script_list: '查询脚本库',
  run_script: '运行脚本',
  exec_command: '执行命令',
  terminal_command: '提交终端命令',
  read_file: '读取文件',
  write_file: '写入文件',
  list_dir: '列出目录',
  read_output: '回读输出'
}

const toolLabel = computed(() => TOOL_LABELS[props.part.tool] || props.part.tool)

/** 卡片折叠时显示最能说明这次调用干了什么的那个参数 */
const summary = computed(() => {
  const input = props.part.input || {}
  if (props.part.tool === 'run_script') {
    const scriptName = input.scriptName || props.part.output?.scriptName
    if (scriptName) return `脚本: ${ scriptName }`
    if (input.scriptId) return `脚本: ${ input.scriptId }`
  }
  if (props.part.tool === 'host_status' && props.part.output?.name) {
    return `主机: ${ props.part.output.name }`
  }
  if (input.command) return input.command
  if (input.path) return input.path
  if (input.handle) return `handle: ${ String(input.handle).slice(0, 8) }…`
  if (input.keyword) return `关键词: ${ input.keyword }`
  return ''
})

const formattedDuration = computed(() => {
  const ms = props.part.durationMs
  if (ms === undefined) return ''
  return ms < 1000 ? `${ ms }ms` : `${ (ms / 1000).toFixed(1) }s`
})

const formattedInput = computed(() => stringify(props.part.input))

const hasOutput = computed(() => props.part.output !== undefined && props.part.output !== null)
const isRunningWithProgress = computed(() => props.part.status === 'running' && Boolean(props.part.progressOutput))

// 长任务一旦有输出就自动展开，用户不必每隔几秒手动点开查看进度。
watch(() => props.part.progressOutput, (output) => {
  if (output) expanded.value = true
})

const formattedOutput = computed(() => {
  const output = props.part.output
  if (output === null || output === undefined) return ''
  // exec_command 的结果拼成终端风格，比看 JSON 直观得多
  if (typeof output === 'object' && ('stdout' in output || 'stderr' in output)) {
    const lines = []
    if (output.stdout) lines.push(output.stdout.replace(/\n$/, ''))
    if (output.stderr) lines.push(`[stderr]\n${ output.stderr.replace(/\n$/, '') }`)
    if (output.exitCode !== undefined && output.exitCode !== 0) {
      lines.push(`[退出码] ${ output.exitCode === null ? '未知' : output.exitCode }`)
    }
    if (output.note) lines.push(`[说明] ${ output.note }`)
    if (output._notice) lines.push(`[说明] ${ output._notice }`)
    return lines.join('\n\n') || '(无输出)'
  }
  if (typeof output === 'object' && typeof output.content === 'string') return output.content
  return stringify(output)
})

function stringify(value) {
  if (value === null || value === undefined) return ''
  if (typeof value === 'string') return value
  try {
    return JSON.stringify(value, null, 2)
  } catch {
    return String(value)
  }
}

async function copyOutput() {
  const success = await clipboard(formattedOutput.value)
  $message[success ? 'success' : 'error'](success ? '已复制' : '复制失败')
}
</script>

<style lang="scss" scoped>
.tool_card {
  margin: 8px 0;
  border: 1px solid #e4e7ed;
  border-radius: 8px;
  background-color: #fafafa;
  font-size: 13px;
  overflow: hidden;

  &.is_dark {
    border-color: #3a3a3a;
    background-color: rgba(255, 255, 255, 0.03);
  }

  &.is_denied {
    border-color: #f56c6c;
  }

  &.is_error {
    border-color: #e6a23c;
  }

  .tool_head {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    cursor: pointer;
    user-select: none;

    &:hover {
      background-color: rgba(0, 0, 0, 0.03);
    }

    .toggle_icon {
      flex-shrink: 0;
      font-size: 12px;
      transition: transform 0.2s;
      color: #909399;

      &.is_expanded {
        transform: rotate(90deg);
      }
    }

    .tool_name {
      flex-shrink: 0;
      font-weight: 500;
    }

    .tool_summary {
      flex: 1;
      min-width: 0;
      padding: 1px 6px;
      border-radius: 4px;
      background-color: rgba(0, 0, 0, 0.06);
      font-family: 'JetBrains Mono', Menlo, Consolas, monospace;
      font-size: 12px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .tool_spacer {
      flex: 1;
    }

    .risk_tag,
    .approval_tag,
    .progress_tag {
      flex-shrink: 0;
      padding: 1px 6px;
      border-radius: 4px;
      font-size: 11px;
      line-height: 18px;
    }

    .risk_tag {
      &.risk_deny {
        background-color: rgba(245, 108, 108, 0.15);
        color: #f56c6c;
      }
      &.risk_high {
        background-color: rgba(230, 162, 60, 0.15);
        color: #e6a23c;
      }
    }

    .approval_tag {
      background-color: rgba(103, 194, 58, 0.15);
      color: #67c23a;
    }

    .progress_tag {
      background-color: rgba(64, 158, 255, 0.14);
      color: #409eff;
    }

    .duration {
      flex-shrink: 0;
      color: #909399;
      font-size: 12px;
    }

    .status_icon {
      flex-shrink: 0;
      font-size: 15px;

      &.is_ok { color: #67c23a; }
      &.is_denied { color: #f56c6c; }
      &.is_error { color: #e6a23c; }
      &.is_waiting { color: #e6a23c; }
      &.is_spin {
        color: #409eff;
        animation: tool_spin 1s linear infinite;
      }
    }
  }

  .tool_body {
    padding: 0 12px 10px;
    border-top: 1px solid rgba(0, 0, 0, 0.06);

    .risk_reason {
      margin: 8px 0;
      padding: 6px 10px;
      border-radius: 6px;
      background-color: rgba(230, 162, 60, 0.12);
      color: #b88230;
      line-height: 1.6;
    }

    .body_section {
      margin-top: 8px;

      .section_label {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 4px;
        color: #909399;
        font-size: 12px;
      }

      .section_content {
        margin: 0;
        padding: 8px 10px;
        max-height: 320px;
        overflow: auto;
        border-radius: 6px;
        background-color: rgba(0, 0, 0, 0.05);
        font-family: 'JetBrains Mono', Menlo, Consolas, monospace;
        font-size: 12px;
        line-height: 1.6;
        white-space: pre-wrap;
        word-break: break-all;

        &.is_error_text {
          color: #f56c6c;
        }
      }
    }
  }

  &.is_dark {
    .tool_head:hover { background-color: rgba(255, 255, 255, 0.04); }
    .tool_head .tool_summary { background-color: rgba(255, 255, 255, 0.08); }
    .tool_body {
      border-top-color: rgba(255, 255, 255, 0.08);
      .section_content { background-color: rgba(0, 0, 0, 0.3); }
    }
  }
}

@keyframes tool_spin {
  to { transform: rotate(360deg); }
}
</style>
