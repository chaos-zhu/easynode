<template>
  <el-popover
    placement="bottom-end"
    trigger="hover"
    popper-class="assistant_info_popover"
    :width="420"
    :show-after="180"
    :hide-after="80"
  >
    <template #reference>
      <el-button
        class="assistant_info_button"
        link
        aria-label="查看助手说明与可用工具"
      >
        <el-icon><InfoFilled /></el-icon>
      </el-button>
    </template>

    <div class="assistant_info">
      <h3>助手类型</h3>
      <div class="assistant_comparison">
        <section :class="{ 'is_current': scope === 'ops' }">
          <strong>运维助手</strong>
          <p>面向所选的一台或多台主机，通过独立 SSH / SFTP 查询状态、执行脚本和读写文件，不共享 Web 终端的当前目录与环境。</p>
        </section>
        <section :class="{ 'is_current': scope === 'terminal' }">
          <strong>终端助手</strong>
          <p>仅绑定当前终端和单台主机，命令会写入当前 PTY，继承当前目录、环境变量及会话状态。</p>
        </section>
      </div>

      <div class="tool_heading">
        <h3>当前可用工具</h3>
        <span v-if="availableTools.length">{{ availableTools.length }} 个</span>
      </div>
      <p class="current_context">{{ contextDescription }}</p>

      <div v-if="availableTools.length" class="tool_list">
        <div v-for="tool in availableTools" :key="tool.name" class="tool_item">
          <div class="tool_name">
            <strong>{{ toolLabel(tool.name) }}</strong>
            <code>{{ tool.name }}</code>
            <span :class="agentToolAccessClass(tool)">
              {{ agentToolAccessLabel(tool, plusAvailable) }}
            </span>
          </div>
          <p>{{ shortDescription(tool.description) }}</p>
        </div>
      </div>
      <p v-else class="empty_tools">{{ emptyDescription }}</p>

      <p class="tool_notice">{{ toolNotice }}</p>
    </div>
  </el-popover>
</template>

<script setup>
import { computed } from 'vue'
import { InfoFilled } from '@element-plus/icons-vue'
import { agentToolAccessClass, agentToolAccessLabel, availableAgentTools } from '@/composables/agentTools'

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

const props = defineProps({
  scope: {
    type: String,
    default: 'ops',
    validator: (value) => ['ops', 'terminal',].includes(value)
  },
  tools: {
    type: Array,
    default: () => []
  },
  preset: {
    type: String,
    default: 'review'
  },
  selectedHostCount: {
    type: Number,
    default: 0
  },
  hostName: {
    type: String,
    default: ''
  },
  plusAvailable: {
    type: Boolean,
    default: false
  },
  connected: {
    type: Boolean,
    default: false
  }
})

const availableTools = computed(() => availableAgentTools(props.tools, {
  scope: props.scope,
  preset: props.preset,
  hasSelectedHosts: props.selectedHostCount > 0,
  plusAvailable: props.plusAvailable
}))

const contextDescription = computed(() => {
  if (props.scope === 'terminal') {
    return `当前绑定终端：${ props.hostName || '当前主机' }`
  }
  if (!props.selectedHostCount) return '当前未选择目标主机，处于纯聊天模式'
  return `当前已选择 ${ props.selectedHostCount } 台目标主机`
})

const emptyDescription = computed(() => {
  if (!props.connected || !props.tools.length) return '连接服务端后显示工具列表'
  if (props.scope === 'ops' && !props.selectedHostCount) return '选择目标主机后，才会向模型开放运维工具'
  return '当前模式下暂无可用工具'
})

const toolNotice = computed(() => (
  props.scope === 'terminal'
    ? '终端命令按当前权限模式执行；需审查操作需要确认，永久禁止的操作始终拦截。'
    : '工具按权限模式和目标主机策略执行；需审查操作需要确认，永久禁止的操作始终拦截。'
))

function toolLabel(name) {
  return TOOL_LABELS[name] || name
}

function shortDescription(description) {
  const text = String(description || '').trim()
  const firstSentence = text.split('。')[0]
  return firstSentence ? `${ firstSentence }。` : '暂无说明'
}
</script>

<style lang="scss" scoped>
:global(.assistant_info_popover) {
  max-width: calc(100vw - 24px);
}

.assistant_info_button {
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

.assistant_info {
  color: var(--el-text-color-primary);

  h3 {
    margin: 0;
    font-size: 14px;
    line-height: 1.4;
  }

  p {
    margin: 0;
  }
}

.assistant_comparison {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  margin-top: 10px;

  section {
    padding: 10px;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
    background: var(--el-fill-color-lighter);

    &.is_current {
      border-color: var(--el-color-primary-light-5);
      background: var(--el-color-primary-light-9);
    }

    strong {
      font-size: 13px;
    }

    p {
      margin-top: 5px;
      color: var(--el-text-color-secondary);
      font-size: 12px;
      line-height: 1.55;
    }
  }
}

.tool_heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 16px;

  span {
    color: var(--el-text-color-secondary);
    font-size: 12px;
  }
}

.current_context {
  margin-top: 5px !important;
  color: var(--el-text-color-secondary);
  font-size: 12px;
}

.tool_list {
  max-height: 280px;
  margin-top: 9px;
  overflow-y: auto;
  border-top: 1px solid var(--el-border-color-lighter);
}

.tool_item {
  padding: 9px 2px;
  border-bottom: 1px solid var(--el-border-color-lighter);

  .tool_name {
    display: flex;
    align-items: center;
    gap: 6px;

    strong {
      font-size: 12px;
    }

    code {
      color: var(--el-text-color-secondary);
      font-size: 11px;
    }

    span {
      margin-left: auto;
      padding: 1px 5px;
      border-radius: 4px;
      font-size: 10px;

      &.is_readonly {
        background: var(--el-color-success-light-9);
        color: var(--el-color-success);
      }

      &.is_write {
        background: var(--el-color-warning-light-9);
        color: var(--el-color-warning);
      }

      &.is_mixed {
        background: var(--el-color-warning-light-9);
        color: var(--el-color-warning);
      }

      &.is_plus {
        background: var(--el-color-primary-light-9);
        color: var(--el-color-primary);
      }
    }
  }

  p {
    margin-top: 4px;
    color: var(--el-text-color-secondary);
    font-size: 12px;
    line-height: 1.45;
  }
}

.empty_tools {
  margin-top: 10px !important;
  padding: 14px;
  border-radius: 7px;
  background: var(--el-fill-color-lighter);
  color: var(--el-text-color-secondary);
  font-size: 12px;
  text-align: center;
}

.tool_notice {
  margin-top: 10px !important;
  color: var(--el-text-color-placeholder);
  font-size: 11px;
  line-height: 1.5;
}

@media (max-width: 520px) {
  .assistant_comparison {
    grid-template-columns: 1fr;
  }
}
</style>
