<template>
  <div class="file-transfer-container">
    <!-- 工具栏 -->
    <div class="toolbar">
      <div class="toolbar-left">
        <div class="transfer-method-info">
          <el-tag type="success" size="large">
            在传输前需在服务器上安装好
            <el-tooltip
              content="问AI?"
              raw-content
            >
              <span class="link" @click="handleAskAI">sshpass、rsync</span>
            </el-tooltip>
          </el-tag>
          <!-- <el-tooltip
            content="一次性传输海量小文件（例如node_modules、vendor、.m2、.gradle、.cache…）<br>会让传输速度比蜗牛还慢, 且进度不可控<br>建议先压缩 → 再传输"
            raw-content
          >
            <el-icon style="color: var(--el-color-warning);"><Warning /></el-icon>
          </el-tooltip> -->
        </div>
      </div>

      <div class="toolbar-right">
        <el-button
          type="primary"
          :icon="List"
          @click="showTaskManager"
        >
          任务管理
          <el-badge
            v-if="activeTaskCount > 0"
            :value="activeTaskCount"
            class="task-badge"
          />
        </el-button>
        <el-button @click="showTransferOptions = !showTransferOptions">
          <el-icon><Setting /></el-icon>
          传输选项
        </el-button>
      </div>
    </div>

    <!-- 传输选项面板 -->
    <el-collapse-transition>
      <div v-if="showTransferOptions" class="transfer-options">
        <div class="options-content">
          <h4>传输选项</h4>
          <div class="options-grid">
            <el-checkbox v-model="transferOptions.delete">
              删除目标多余文件 (--delete)
            </el-checkbox>
            <el-checkbox v-model="transferOptions.partial">
              支持断点续传 (--partial)
            </el-checkbox>
            <el-checkbox v-model="transferOptions.compress">
              启用压缩传输 (-z)
            </el-checkbox>
          </div>
        </div>
      </div>
    </el-collapse-transition>

    <!-- 双面板布局 -->
    <div class="dual-panel">
      <!-- 左侧服务器面板 -->
      <div class="panel left-panel">
        <sftp-panel
          ref="leftPanelRef"
          panel-side="left"
          @server-change="onServerChange"
          @exec-script="$emit('exec-script', $event)"
        />
      </div>

      <!-- 中间传输控制区域 -->
      <div class="transfer-controls">
        <div class="transfer-buttons">
          <el-button
            type="primary"
            size="large"
            :disabled="!canTransferToRight"
            :loading="isTransferring"
            @click="transferToRight"
          >
            传输
            <el-icon><ArrowRight /></el-icon>
          </el-button>

          <el-button
            type="primary"
            size="large"
            style="margin-left: 0;"
            :disabled="!canTransferToLeft"
            :loading="isTransferring"
            @click="transferToLeft"
          >
            <el-icon><ArrowLeft /></el-icon>
            传输
          </el-button>
        </div>
      </div>

      <!-- 右侧服务器面板 -->
      <div class="panel right-panel">
        <sftp-panel
          ref="rightPanelRef"
          panel-side="right"
          @server-change="onServerChange"
          @exec-script="$emit('exec-script', $event)"
        />
      </div>
    </div>

    <!-- 任务管理器对话框 -->
    <el-dialog
      v-model="showTaskDialog"
      title="传输任务管理"
      width="80%"
      :close-on-click-modal="false"
    >
      <transfer-task-manager
        :tasks="transferTasks"
        @cancel-task="cancelTask"
        @retry-task="retryTask"
        @delete-task="deleteTask"
        @refresh="refreshTasks"
      />

      <template #footer>
        <el-button @click="showTaskDialog = false">关闭</el-button>
        <el-button type="danger" @click="clearCompletedTasks">清空任务列表</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, getCurrentInstance } from 'vue'
import { List, Setting, ArrowRight, ArrowLeft } from '@element-plus/icons-vue'
import SftpPanel from '@/components/file-transfer/sftp-panel.vue'
import TransferTaskManager from '@/components/file-transfer/transfer-task-manager.vue'
import { EventBus, generateSocketInstance } from '@/utils'

defineEmits(['exec-script',])

const { proxy: { $message, $router } } = getCurrentInstance()

// 传输配置（仅支持Rsync）
const transferOptions = ref({
  delete: false,
  partial: true,
  compress: true
})
const showTransferOptions = ref(false)

// 服务器状态
const leftServer = ref(null)
const rightServer = ref(null)
const leftPanelRef = ref(null)
const rightPanelRef = ref(null)

// 传输状态
const isTransferring = ref(false)

// 任务管理
const transferTasks = ref([])
const showTaskDialog = ref(false)
const activeTaskCount = computed(() => {
  return transferTasks.value.filter(task => task.status === 'running').length
})

// Socket连接
const socket = ref(null)

// 计算属性
const canTransferToRight = computed(() => {
  return leftServer.value &&
         rightServer.value &&
         leftPanelRef.value?.connectionStatus === 'connected' &&
         rightPanelRef.value?.connectionStatus === 'connected' &&
         !isTransferring.value
})

const canTransferToLeft = computed(() => {
  return leftServer.value &&
         rightServer.value &&
         leftPanelRef.value?.connectionStatus === 'connected' &&
         rightPanelRef.value?.connectionStatus === 'connected' &&
         !isTransferring.value
})

// 生命周期
onMounted(() => {
  initializeSocket()
  refreshTasks()
})

onUnmounted(() => {
  if (socket.value) {
    socket.value.disconnect()
  }
})

// Socket连接
const initializeSocket = () => {
  socket.value = generateSocketInstance('/file-transfer')

  socket.value.on('connect', () => {
    console.log('文件传输WebSocket已连接')
    refreshTasks()
  })

  socket.value.on('tasks_list', (tasks) => {
    transferTasks.value = tasks
  })

  socket.value.on('task_started', ({ message }) => {
    $message.success(message)
    refreshTasks()
  })

  socket.value.on('task_failed', ({ message }) => {
    $message.error(message)
    refreshTasks()
  })

  socket.value.on('task_progress', (progressData) => {
    console.log(`接收到进度更新 [${ progressData.taskId }]:`, progressData)
    updateTaskProgress(progressData.taskId, progressData)
  })

  socket.value.on('task_status_changed', ({ taskId, status, errorMessage }) => {
    updateTaskStatus(taskId, status, errorMessage)
  })

  socket.value.on('task_cancelled', ({ message }) => {
    $message.info(message)
    refreshTasks()
  })

  socket.value.on('error', ({ message, error }) => {
    $message.error(`${ message }: ${ error }`)
  })

  socket.value.on('user_verify_fail', () => {
    $message.error('登录态校验失败，请重新登录')
    $router.push('/login')
  })

  socket.value.on('task_deleted', ({ message }) => {
    $message.success(message)
    // 任务列表会通过 tasks_list 事件自动更新
  })

  socket.value.on('tasks_cleared', ({ message }) => {
    $message.success(message)
    // 任务列表会通过 tasks_list 事件自动更新
  })
}

// 服务器变化处理
const onServerChange = ({ side, server }) => {
  if (side === 'left') {
    leftServer.value = server
  } else {
    rightServer.value = server
  }
}

// 传输操作
const transferToRight = () => {
  performTransfer('left', 'right')
}

const transferToLeft = () => {
  performTransfer('right', 'left')
}

const performTransfer = (fromSide, toSide) => {
  const fromPanel = fromSide === 'left' ? leftPanelRef.value : rightPanelRef.value
  const toPanel = toSide === 'left' ? leftPanelRef.value : rightPanelRef.value
  const fromServer = fromSide === 'left' ? leftServer.value : rightServer.value
  const toServer = toSide === 'left' ? leftServer.value : rightServer.value

  const selectedFiles = fromPanel.getSelectedFiles()
  if (!selectedFiles || selectedFiles.length === 0) {
    $message.warning('请先选择要传输的文件或文件夹')
    return
  }

  const targetPath = toPanel.getCurrentPath()

  const transferConfig = {
    sourceHostId: fromServer._id,
    targetHostId: toServer._id,
    sourcePaths: selectedFiles.map(file => ({
      path: `${ fromPanel.getCurrentPath() }/${ file.name }`.replace(/\/+/g, '/'),
      type: file.type,
      size: file.size || 0
    })),
    targetPath,
    method: 'rsync',
    options: transferOptions.value
  }

  isTransferring.value = true
  socket.value.emit('start_transfer', transferConfig)
}

// 任务管理
const showTaskManager = () => {
  showTaskDialog.value = true
  refreshTasks()
}

const refreshTasks = () => {
  if (socket.value) {
    socket.value.emit('get_tasks')
  }
}

const cancelTask = (taskId) => {
  socket.value.emit('cancel_task', { taskId })
}

const retryTask = (taskId) => {
  socket.value.emit('retry_task', { taskId })
}

const clearCompletedTasks = () => {
  // 发送清空请求到后端
  if (socket.value) {
    socket.value.emit('clear_completed_tasks')
  }
}

const deleteTask = (taskId) => {
  // 发送删除请求到后端
  if (socket.value) {
    socket.value.emit('delete_task', { taskId })
  }
}

// 更新任务状态
const updateTaskProgress = (taskId, progressData) => {
  console.log(`更新任务进度 [${ taskId }]:`, progressData)
  const task = transferTasks.value.find(t => t.taskId === taskId)
  if (task) {
    // 更新任务基本进度（向后兼容）
    task.progress = progressData.overallProgress || progressData.progress || 0
    task.speed = progressData.speed || 0
    // 新增字段
    task.completedFiles = progressData.completedFiles || 0
    task.totalFiles = progressData.totalFiles || 1
    task.currentFile = progressData.currentFile
    task.isVerifying = progressData.isVerifying || false
    console.log('任务状态已更新:', task)
  } else {
    console.warn(`未找到任务: ${ taskId }`)
  }
}

const updateTaskStatus = (taskId, status, errorMessage) => {
  const task = transferTasks.value.find(t => t.taskId === taskId)
  if (task) {
    task.status = status
    if (errorMessage) {
      task.errorMessage = errorMessage
    }
  }

  if (status === 'completed' || status === 'failed' || status === 'cancelled') {
    isTransferring.value = false

    // 刷新两侧面板
    setTimeout(() => {
      refreshLeftPanel()
      refreshRightPanel()
    }, 1000)
  }
}

// 面板刷新
const refreshLeftPanel = () => {
  leftPanelRef.value?.refresh()
}

const refreshRightPanel = () => {
  rightPanelRef.value?.refresh()
}

const handleAskAI = () => {
  EventBus.$emit('sendToAIInput', '如何在不同的Linux发行版中安装sshpass与rsync?')
}
</script>

<style lang="scss" scoped>
.file-transfer-container {
  display: flex;
  flex-direction: column;
  height: 100%;

  .toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px;
    background-color: var(--el-bg-color-page);
    border-bottom: 1px solid var(--el-border-color);

          .toolbar-left {
        display: flex;
        align-items: center;
        gap: 12px;

        .transfer-method-info {
          display: flex;
          align-items: center;
          gap: 8px;
          .method-description {
            font-size: 12px;
            color: var(--el-text-color-secondary);
          }
        }

        .task-badge {
          margin-left: 8px;
        }
      }
  }

  .transfer-options {
    background-color: var(--el-bg-color-page);
    border-bottom: 1px solid var(--el-border-color);

    .options-content {
      padding: 16px;

      h4 {
        margin: 0 0 12px 0;
        font-size: 14px;
        color: var(--el-text-color-primary);
      }

      .options-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
        gap: 12px;
      }
    }
  }

  .dual-panel {
    display: flex;
    flex: 1;
    gap: 16px;
    padding: 16px;
    overflow: hidden;

    .panel {
      flex: 1;
      display: flex;
      flex-direction: column;
      min-width: 0;

      .panel-title {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 8px;
        font-weight: 500;
        color: var(--el-text-color-primary);
      }
    }

    .transfer-controls {
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      width: 140px;
      flex-shrink: 0;

      .transfer-buttons {
        display: flex;
        flex-direction: column;
        gap: 12px;
        margin-bottom: 16px;
      }
    }
  }
}
</style>
