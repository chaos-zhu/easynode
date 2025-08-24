<template>
  <div class="transfer-preview">
    <div class="preview-header">
      <h3>传输预览</h3>
      <el-tag :type="getMethodType(preview.method)" size="large">
        {{ preview.method.toUpperCase() }}
      </el-tag>
    </div>

    <div class="server-info">
      <div class="server-card source">
        <div class="server-header">
          <el-icon><Upload /></el-icon>
          <span>源服务器</span>
        </div>
        <div class="server-details">
          <h4>{{ preview.sourceHost.name }}</h4>
          <p>{{ preview.sourceHost.host }}</p>
        </div>
      </div>

      <div class="transfer-arrow">
        <el-icon><ArrowRight /></el-icon>
      </div>

      <div class="server-card target">
        <div class="server-header">
          <el-icon><Download /></el-icon>
          <span>目标服务器</span>
        </div>
        <div class="server-details">
          <h4>{{ preview.targetHost.name }}</h4>
          <p>{{ preview.targetHost.host }}</p>
        </div>
      </div>
    </div>

    <div class="transfer-summary">
      <div class="summary-stats">
        <el-statistic title="文件数量" :value="preview.fileCount" suffix="个" />
        <el-statistic title="文件夹数量" :value="preview.folderCount" suffix="个" />
        <el-statistic title="总大小" :value="formatSize(preview.totalSize)" />
        <el-statistic title="预计时间" :value="preview.estimatedTime" />
      </div>
    </div>

    <div class="path-info">
      <div class="path-section">
        <h4>
          <el-icon><Folder /></el-icon>
          源文件/文件夹
        </h4>
        <div class="path-list">
          <div
            v-for="(path, index) in preview.sourcePaths"
            :key="index"
            class="path-item"
          >
            <el-icon>
              <Folder v-if="path.type === 'd'" />
              <Document v-else />
            </el-icon>
            <span class="path-name">{{ getFileName(path.path) }}</span>
            <span class="path-full">{{ path.path }}</span>
            <span class="path-size">{{ formatSize(path.size) }}</span>
          </div>
        </div>
      </div>

      <div class="path-section">
        <h4>
          <el-icon><Folder /></el-icon>
          目标路径
        </h4>
        <div class="target-path">
          <el-icon><Folder /></el-icon>
          <span>{{ preview.targetPath }}</span>
        </div>
      </div>
    </div>

    <div class="method-info">
      <h4>传输方法说明</h4>
      <div class="method-description">
        <template v-if="preview.method === 'scp'">
          <el-alert
            type="info"
            :closable="false"
            show-icon
          >
            <template #title>
              SCP (Secure Copy Protocol)
            </template>
            <p>• 基于SSH协议的安全文件传输</p>
            <p>• 适合传输小到中等大小的文件</p>
            <p>• 简单快速，但不支持增量传输</p>
            <p>• 传输过程中会保持文件权限和时间戳</p>
          </el-alert>
        </template>
        <template v-else-if="preview.method === 'rsync'">
          <el-alert
            type="success"
            :closable="false"
            show-icon
          >
            <template #title>
              Rsync (Remote Sync)
            </template>
            <p>• 高效的增量同步工具</p>
            <p>• 支持断点续传和增量更新</p>
            <p>• 适合传输大文件或进行目录同步</p>
            <p>• 内置压缩和进度显示功能</p>
          </el-alert>
        </template>
      </div>
    </div>

    <div class="warning-notice">
      <el-alert
        type="warning"
        :closable="false"
        show-icon
      >
        <template #title>注意事项</template>
        <p>• 传输过程中请确保网络连接稳定</p>
        <p>• 目标路径如果存在同名文件将会被覆盖</p>
        <p>• 传输大文件时建议使用Rsync方法</p>
        <p>• 传输过程可在任务管理器中查看进度</p>
      </el-alert>
    </div>
  </div>
</template>

<script setup>
import { Upload, Download, ArrowRight, Folder, Document } from '@element-plus/icons-vue'

const props = defineProps({
  preview: {
    type: Object,
    required: true
  }
})

const emit = defineEmits(['confirm', 'cancel',])

const getMethodType = (method) => {
  return method === 'rsync' ? 'success' : 'primary'
}

const getFileName = (fullPath) => {
  return fullPath.split('/').pop() || fullPath
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
</script>

<style lang="scss" scoped>
.transfer-preview {
  .preview-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;

    h3 {
      margin: 0;
      color: var(--el-text-color-primary);
    }
  }

  .server-info {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 24px;
    padding: 20px;
    background-color: var(--el-bg-color-page);
    border-radius: 8px;

    .server-card {
      flex: 1;
      text-align: center;

      .server-header {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        margin-bottom: 12px;
        font-size: 14px;
        color: var(--el-text-color-regular);

        .el-icon {
          font-size: 16px;
        }
      }

      .server-details {
        h4 {
          margin: 0 0 4px 0;
          font-size: 16px;
          color: var(--el-text-color-primary);
        }

        p {
          margin: 0;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }

      &.source .server-header .el-icon {
        color: var(--el-color-warning);
      }

      &.target .server-header .el-icon {
        color: var(--el-color-success);
      }
    }

    .transfer-arrow {
      margin: 0 20px;
      font-size: 24px;
      color: var(--el-color-primary);
    }
  }

  .transfer-summary {
    margin-bottom: 24px;

    .summary-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
      gap: 16px;
      padding: 16px;
      background-color: var(--el-bg-color-page);
      border-radius: 6px;
    }
  }

  .path-info {
    margin-bottom: 24px;

    .path-section {
      margin-bottom: 20px;

      h4 {
        display: flex;
        align-items: center;
        gap: 8px;
        margin: 0 0 12px 0;
        font-size: 14px;
        color: var(--el-text-color-primary);
      }

      .path-list {
        border: 1px solid var(--el-border-color);
        border-radius: 6px;
        max-height: 200px;
        overflow-y: auto;

        .path-item {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 8px 12px;
          border-bottom: 1px solid var(--el-border-color-lighter);

          &:last-child {
            border-bottom: none;
          }

          .el-icon {
            color: var(--el-color-primary);
            flex-shrink: 0;
          }

          .path-name {
            font-weight: 500;
            color: var(--el-text-color-primary);
            min-width: 100px;
          }

          .path-full {
            flex: 1;
            font-size: 12px;
            color: var(--el-text-color-secondary);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }

          .path-size {
            font-size: 12px;
            color: var(--el-text-color-secondary);
            flex-shrink: 0;
          }
        }
      }

      .target-path {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 12px;
        background-color: var(--el-bg-color-page);
        border: 1px solid var(--el-border-color);
        border-radius: 6px;
        font-family: monospace;

        .el-icon {
          color: var(--el-color-primary);
        }
      }
    }
  }

  .method-info {
    margin-bottom: 24px;

    h4 {
      margin: 0 0 12px 0;
      font-size: 14px;
      color: var(--el-text-color-primary);
    }

    .method-description {
      :deep(.el-alert__content) {
        p {
          margin: 2px 0;
          font-size: 13px;
        }
      }
    }
  }

  .warning-notice {
    :deep(.el-alert__content) {
      p {
        margin: 2px 0;
        font-size: 13px;
      }
    }
  }
}
</style>