<template>
  <div class="transfer-task-manager">
    <div class="task-filter">
      <el-radio-group v-model="filterStatus" size="">
        <el-radio-button label="all">{{ t('componentTransferTaskManager.filters.all') }}</el-radio-button>
        <el-radio-button label="running">{{ t('componentTransferTaskManager.filters.running') }}</el-radio-button>
        <el-radio-button label="completed">{{ t('componentTransferTaskManager.filters.completed') }}</el-radio-button>
        <el-radio-button label="failed">{{ t('componentTransferTaskManager.filters.failed') }}</el-radio-button>
        <el-radio-button label="cancelled">{{ t('componentTransferTaskManager.filters.cancelled') }}</el-radio-button>
      </el-radio-group>
    </div>

    <div class="task-list">
      <div v-if="filteredTasks.length === 0" class="empty-state">
        <el-icon class="empty-icon"><Document /></el-icon>
        <p>{{ filterStatus === 'all' ? t('componentTransferTaskManager.empty') : t('componentTransferTaskManager.emptyWithStatus', { status: getStatusText(filterStatus) }) }}</p>
      </div>

      <div
        v-for="task in filteredTasks"
        :key="task.taskId"
        class="task-item"
        :class="task.status"
      >
        <div class="task-header">
          <div class="task-info">
            <h4 class="task-title">
              {{ task.sourceHostName }} → {{ task.targetHostName }}
            </h4>
            <div class="task-meta">
              <el-tag :type="getStatusType(task.status)" size="small">
                {{ getStatusText(task.status) }}
              </el-tag>
              <span class="task-method">{{ task.method.toUpperCase() }}</span>
              <span class="task-time">{{ formatDateTime(task.createTime) }}</span>
            </div>
          </div>

          <div class="task-actions">
            <el-button
              v-if="task.status === 'running'"
              size="small"
              type="danger"
              @click="$emit('cancel-task', task.taskId)"
            >
              {{ t('common.cancel') }}
            </el-button>
            <el-button
              v-if="task.status === 'failed'"
              size="small"
              type="primary"
              @click="$emit('retry-task', task.taskId)"
            >
              {{ t('fileTransfer.sftp.retry') }}
            </el-button>
            <el-button
              v-if="task.status !== 'running'"
              size="small"
              type="danger"
              plain
              @click="deleteTask(task.taskId)"
            >
              {{ t('fileTransfer.sftp.delete') }}
            </el-button>
            <el-button
              size="small"
              @click="toggleTaskDetails(task.taskId)"
            >
              {{ expandedTasks.has(task.taskId) ? t('componentTransferTaskManager.collapse') : t('componentTransferTaskManager.details') }}
            </el-button>
          </div>
        </div>

        <!-- 进度信息 -->
        <div v-if="task.status === 'running'" class="task-progress">
          <div class="progress-info">
            <span v-if="task.isVerifying">
              <el-icon class="verifying-icon"><Loading /></el-icon>
              {{ t('componentTransferTaskManager.verifying') }}
            </span>
            <template v-else>
              <span>{{ t('componentTransferTaskManager.overallProgress') }}: {{ task.progress || 0 }}%</span>
              <span v-if="task.fileProgress">{{ t('componentTransferTaskManager.fileProgress') }}: {{ task.completedFiles || 0 }}/{{ task.totalFiles || 1 }}</span>
              <span v-if="task.speed">{{ t('componentTransferTaskManager.speed') }}: {{ formatSpeed(task.speed) }}</span>
            </template>
          </div>
          <el-progress
            :percentage="task.progress || 0"
            :stroke-width="9"
            :status="task.isVerifying ? 'warning' : ''"
            striped
          />

          <!-- 当前文件信息（多文件传输时） -->
          <div v-if="!task.isVerifying" class="current-file-info">
            <div class="current-file-name">
              <el-icon><Document /></el-icon>
              <span>{{ getFileName(task.currentFile) || '...' }}</span>
            </div>
          </div>
        </div>

        <!-- 错误信息 -->
        <div v-if="task.status === 'failed' && task.errorMessage" class="task-error">
          <el-alert
            :title="task.errorMessage"
            type="error"
            show-icon
            :closable="false"
          />
        </div>

        <!-- 详细信息 -->
        <el-collapse-transition>
          <div v-if="expandedTasks.has(task.taskId)" class="task-details">
            <div class="details-grid">
              <div class="detail-item">
                <label>{{ t('componentTransferTaskManager.taskId') }}</label>
                <span>{{ task.taskId }}</span>
              </div>
              <div class="detail-item">
                <label>{{ t('componentTransferTaskManager.transferMethod') }}</label>
                <span>{{ task.method.toUpperCase() }}</span>
              </div>
              <div class="detail-item">
                <label>{{ t('componentTransferTaskManager.sourcePath') }}</label>
                <div class="path-list">
                  <div v-for="(path, index) in task.sourcePaths" :key="index" class="path-item">
                    <el-icon>
                      <Folder v-if="path.type === 'd'" />
                      <Document v-else />
                    </el-icon>
                    <span>{{ path.path }}</span>
                    <span class="file-size">({{ formatSize(path.size) }})</span>
                  </div>
                </div>
              </div>
              <div class="detail-item">
                <label>{{ t('componentTransferTaskManager.targetPath') }}</label>
                <span>{{ task.targetPath }}</span>
              </div>
              <div class="detail-item">
                <label>{{ t('componentTransferTaskManager.totalSize') }}</label>
                <span>{{ formatSize(task.totalSize) }}</span>
              </div>
              <div class="detail-item">
                <label>{{ t('componentTransferTaskManager.createdAt') }}</label>
                <span>{{ formatDateTime(task.createTime) }}</span>
              </div>
              <div v-if="task.updateTime !== task.createTime" class="detail-item">
                <label>{{ t('componentTransferTaskManager.updatedAt') }}</label>
                <span>{{ formatDateTime(task.updateTime) }}</span>
              </div>
            </div>

            <!-- 传输选项 -->
            <div v-if="task.options && Object.keys(task.options).length > 0" class="transfer-options">
              <h5>{{ t('fileTransfer.transferOptionsTitle') }}:</h5>
              <div class="options-list">
                <el-tag
                  v-for="(value, key) in task.options"
                  :key="key"
                  size="small"
                  :type="value ? 'success' : 'info'"
                >
                  {{ getOptionName(key) }}: {{ value ? t('terminal.yes') : t('terminal.no') }}
                </el-tag>
              </div>
            </div>
          </div>
        </el-collapse-transition>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { Document, Folder, Loading } from '@element-plus/icons-vue'
import { ElMessageBox } from 'element-plus'

const props = defineProps({
  tasks: {
    type: Array,
    default: () => []
  }
})

const emit = defineEmits(['cancel-task', 'retry-task', 'delete-task', 'refresh',])

const { t, locale } = useI18n()

const filterStatus = ref('all')
const expandedTasks = ref(new Set())

// 计算属性
const filteredTasks = computed(() => {
  if (filterStatus.value === 'all') {
    return props.tasks
  }
  return props.tasks.filter(task => task.status === filterStatus.value)
})

const runningTasksCount = computed(() => {
  return props.tasks.filter(task => task.status === 'running').length
})

const completedTasksCount = computed(() => {
  return props.tasks.filter(task => task.status === 'completed').length
})

const failedTasksCount = computed(() => {
  return props.tasks.filter(task => task.status === 'failed').length
})

// 方法
const toggleTaskDetails = (taskId) => {
  if (expandedTasks.value.has(taskId)) {
    expandedTasks.value.delete(taskId)
  } else {
    expandedTasks.value.add(taskId)
  }
}

const deleteTask = async (taskId) => {
  const task = props.tasks.find(t => t.taskId === taskId)
  if (!task) return

  try {
    await ElMessageBox.confirm(
      t('componentTransferTaskManager.deleteConfirm', { source: task.sourceHostName, target: task.targetHostName }),
      t('componentTransferTaskManager.deleteTask'),
      {
        confirmButtonText: t('fileTransfer.sftp.delete'),
        cancelButtonText: t('common.cancel'),
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      }
    )

    emit('delete-task', taskId)
  } catch {
    // 用户取消删除
  }
}

const getStatusType = (status) => {
  const statusMap = {
    running: 'primary',
    completed: 'success',
    failed: 'danger',
    cancelled: 'info'
  }
  return statusMap[status] || 'info'
}

const getStatusText = (status) => {
  const statusMap = {
    running: t('componentTransferTaskManager.filters.running'),
    completed: t('componentTransferTaskManager.filters.completed'),
    failed: t('componentTransferTaskManager.filters.failed'),
    cancelled: t('componentTransferTaskManager.filters.cancelled')
  }
  return statusMap[status] || status
}

const getOptionName = (key) => {
  const optionMap = {
    delete: t('fileTransfer.deleteExtraFiles'),
    partial: t('fileTransfer.resumeTransfer'),
    compress: t('fileTransfer.enableCompression')
  }
  return optionMap[key] || key
}

const formatDateTime = (timestamp) => {
  if (!timestamp) return ''
  const date = new Date(timestamp)
  return date.toLocaleString(locale.value === 'en' ? 'en-US' : 'zh-CN')
}

const formatSize = (bytes) => {
  if (!bytes || bytes === 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB',]
  let size = bytes
  let unitIndex = 0

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024
    unitIndex++
  }

  return `${ size.toFixed(1) } ${ units[unitIndex] }`
}

const formatSpeed = (bytesPerSec) => {
  if (!bytesPerSec || bytesPerSec === 0) return '0 B/s'
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s',]
  let size = bytesPerSec
  let unitIndex = 0

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024
    unitIndex++
  }

  return `${ size.toFixed(1) } ${ units[unitIndex] }`
}

const getFileName = (filePath) => {
  if (!filePath) return ''
  return filePath.split('/').pop() || filePath
}

</script>

<style lang="scss" scoped>
.transfer-task-manager {
  .current-transfer {
    margin-bottom: 20px;
    padding: 16px;
    background-color: var(--el-color-primary-light-9);
    border: 1px solid var(--el-color-primary-light-7);
    border-radius: 8px;

    .transfer-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;

      h4 {
        margin: 0;
        font-size: 16px;
        font-weight: 500;
        color: var(--el-text-color-primary);
      }
    }

    .transfer-progress {
      .overall-progress {
        margin-bottom: 16px;

        .progress-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 8px;
          font-size: 14px;

          .verifying-status {
            display: flex;
            align-items: center;
            gap: 4px;
            color: var(--el-color-warning);
            font-weight: 500;

            .el-icon {
              animation: rotate 1s linear infinite;
            }
          }
        }
      }

      .files-progress {
        .files-header {
          font-size: 12px;
          color: var(--el-text-color-secondary);
          margin-bottom: 8px;
        }

        .current-file {
          margin-bottom: 12px;
          padding: 8px;
          background-color: var(--el-bg-color);
          border-radius: 4px;

          .file-info {
            display: flex;
            align-items: center;
            gap: 6px;
            margin-bottom: 4px;
            font-size: 12px;

            .file-name {
              flex: 1;
              color: var(--el-text-color-primary);
              font-weight: 500;
            }

            .file-progress {
              color: var(--el-color-primary);
              font-weight: 500;
            }
          }
        }

        .completed-files {
          .completed-file {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 4px 0;
            font-size: 11px;

            .el-icon {
              color: var(--el-color-success);
            }

            .file-name {
              flex: 1;
              color: var(--el-text-color-secondary);
            }

            .file-size {
              color: var(--el-text-color-placeholder);
            }
          }
        }
      }

      .transfer-details {
        padding-top: 8px;
        border-top: 1px solid var(--el-border-color-lighter);
        font-size: 12px;
        color: var(--el-text-color-secondary);
        text-align: center;
      }
    }

    @keyframes rotate {
      from {
        transform: rotate(0deg);
      }
      to {
        transform: rotate(360deg);
      }
    }
  }

  .task-stats {
    display: flex;
    align-items: center;
    gap: 16px;
    margin-bottom: 16px;
    padding: 12px 16px;
    background-color: var(--el-bg-color-page);
    border-radius: 6px;
    font-size: 14px;

    .stat-item {
      color: var(--el-text-color-secondary);

      strong {
        color: var(--el-text-color-primary);
        margin: 0 2px;
      }
    }
  }

  .task-filter {
    margin-bottom: 16px;
    text-align: center;
  }

  .task-list {
    max-height: 60vh;
    overflow-y: auto;

    .empty-state {
      text-align: center;
      padding: 40px 20px;
      color: var(--el-text-color-secondary);

      .empty-icon {
        font-size: 48px;
        color: var(--el-color-info-light-5);
        margin-bottom: 12px;
      }
    }

    .task-item {
      border: 1px solid var(--el-border-color);
      border-radius: 6px;
      margin-bottom: 12px;
      background-color: var(--el-bg-color);

      &.running {
        border-color: var(--el-color-primary-light-7);
        background-color: var(--el-color-primary-light-9);
      }

      &.completed {
        border-color: var(--el-color-success-light-7);
        background-color: var(--el-color-success-light-9);
      }

      &.failed {
        border-color: var(--el-color-danger-light-7);
        background-color: var(--el-color-danger-light-9);
      }

      .task-header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        padding: 16px;

        .task-info {
          flex: 1;
          min-width: 0;

          .task-title {
            margin: 0 0 8px 0;
            font-size: 16px;
            font-weight: 500;
            color: var(--el-text-color-primary);
          }

          .task-meta {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 12px;
            color: var(--el-text-color-secondary);

            .task-method {
              padding: 2px 6px;
              background-color: var(--el-color-info-light-8);
              border-radius: 4px;
            }
          }
        }

        .task-actions {
          display: flex;
          gap: 8px;
          flex-shrink: 0;
        }
      }

      .task-progress {
        padding: 0 16px 16px;

        .progress-info {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 8px;
          font-size: 12px;
          color: var(--el-text-color-secondary);

          .verifying-icon {
            animation: rotate 1s linear infinite;
            margin-right: 4px;
          }
        }

        .current-file-info {
          margin-top: 8px;
          padding: 6px 8px;
          background-color: var(--el-bg-color);
          border-radius: 4px;

          .current-file-name {
            display: flex;
            align-items: center;
            gap: 4px;
            font-size: 11px;
            color: var(--el-text-color-secondary);

            .el-icon {
              color: var(--el-color-primary);
            }
          }
        }
      }

      @keyframes rotate {
        from {
          transform: rotate(0deg);
        }
        to {
          transform: rotate(360deg);
        }
      }

      .task-error {
        padding: 0 16px 16px;
      }

      .task-details {
        padding: 0 16px 16px;
        border-top: 1px solid var(--el-border-color-light);

        .details-grid {
          display: grid;
          gap: 12px;
          margin: 16px 0;

          .detail-item {
            display: flex;
            align-items: flex-start;
            gap: 8px;

            label {
              min-width: 80px;
              font-weight: 500;
              color: var(--el-text-color-regular);
            }

            span {
              flex: 1;
              word-break: break-all;
            }

            .path-list {
              flex: 1;

              .path-item {
                display: flex;
                align-items: center;
                gap: 4px;
                margin-bottom: 4px;
                font-size: 12px;

                .file-size {
                  color: var(--el-text-color-secondary);
                }
              }
            }
          }
        }

        .transfer-options {
          h5 {
            margin: 0 0 8px 0;
            font-size: 14px;
            color: var(--el-text-color-primary);
          }

          .options-list {
            display: flex;
            flex-wrap: wrap;
            gap: 6px;
          }
        }
      }
    }
  }
}
</style>