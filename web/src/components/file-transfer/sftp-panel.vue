<template>
  <div class="sftp_panel_container">
    <div class="panel_header">
      <div class="server_info">
        <PlusSupportTip>
          <server-selector
            v-model="selectedServerId"
            @change="onServerChange"
          />
        </PlusSupportTip>
      </div>
      <div class="connection_status">
        <el-tag
          v-if="connectionStatus === 'connected'"
          type="success"
          size="small"
          disable-transitions
        >
          已连接
        </el-tag>
        <el-tag
          v-else-if="connectionStatus === 'connecting'"
          type="warning"
          size="small"
          disable-transitions
        >
          连接中
        </el-tag>
        <el-tag
          v-else-if="connectionStatus === 'failed'"
          type="danger"
          size="small"
          disable-transitions
        >
          连接断开
        </el-tag>
        <el-tag
          v-else
          type="info"
          size="small"
          disable-transitions
        >
          未连接
        </el-tag>
      </div>
    </div>

    <!-- SFTP内容区域 -->
    <div class="panel_content">
      <template v-if="selectedServerId">
        <!-- SFTP组件总是渲染，但可能被遮罩层覆盖 -->
        <div class="sftp_wrapper" :class="{ 'is-loading': connectionStatus !== 'connected' }">
          <sftp-v2
            ref="sftpRef"
            :key="selectedServerId"
            :host-id="selectedServerId"
            :show-cd-command="false"
            @exec-script="$emit('exec-script', $event)"
          />
        </div>
      </template>
      <template v-else>
        <div class="empty_state">
          <el-icon class="empty_icon"><Monitor /></el-icon>
          <p>请选择一台服务器</p>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, computed, getCurrentInstance } from 'vue'
import { Monitor } from '@element-plus/icons-vue'
import ServerSelector from '@/components/server-selector.vue'
import SftpV2 from '@/views/terminal/components/sftp-v2.vue'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'

const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  panelSide: {
    type: String,
    required: true // 'left' | 'right'
  }
})

const emit = defineEmits(['server-change', 'exec-script', 'files-select',])

const selectedServerId = ref('')
const connectionStatus = ref('disconnected') // disconnected, connecting, connected, failed
const sftpRef = ref(null)
const isDark = computed(() => $store.isDark)

const onServerChange = (server) => {
  if (server) {
    connectionStatus.value = 'connecting'
    emit('server-change', {
      side: props.panelSide,
      server
    })
  } else {
    connectionStatus.value = 'disconnected'
    emit('server-change', {
      side: props.panelSide,
      server: null
    })
  }
}

// 获取当前路径
const getCurrentPath = () => {
  const currentPath = sftpRef.value?.currentPath
  return (typeof currentPath === 'function' ? currentPath() : currentPath) || '/'
}

// 获取选中的文件
const getSelectedFiles = () => {
  const selectedRows = sftpRef.value?.selectedRows
  return (typeof selectedRows === 'function' ? selectedRows() : selectedRows) || []
}

// 刷新目录
const refresh = () => {
  if (sftpRef.value && typeof sftpRef.value.refresh === 'function') {
    sftpRef.value.refresh()
  }
}

// 监听服务器选择变化
watch(selectedServerId, (newServerId) => {
  if (newServerId) {
    connectionStatus.value = 'connecting'
  } else {
    connectionStatus.value = 'disconnected'
  }
})

// 监听SFTP组件的连接状态变化
watch(() => {
  const statusRef = sftpRef.value?.connectionStatus
  return typeof statusRef === 'function' ? statusRef() : statusRef
}, (newStatus) => {
  if (newStatus && newStatus !== connectionStatus.value) {
    console.log('SFTP连接状态变化:', newStatus)
    connectionStatus.value = newStatus
  }
}, { immediate: true })

// 暴露方法供父组件调用
defineExpose({
  getCurrentPath,
  getSelectedFiles,
  refresh,
  selectedServerId: computed(() => selectedServerId.value),
  connectionStatus: computed(() => connectionStatus.value)
})
</script>

<style lang="scss" scoped>
.sftp_panel_container {
  display: flex;
  flex-direction: column;
  height: 100%;
  border: 1px solid var(--el-border-color);
  border-radius: 6px;
  overflow: hidden;

  .panel_header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    background-color: var(--el-bg-color-page);
    border-bottom: 1px solid var(--el-border-color);

    .server_info {
      flex: 1;
      margin-right: 12px;
    }

    .connection_status {
      flex-shrink: 0;
    }
  }

  .panel_content {
    flex: 1;
    overflow: hidden;
    position: relative;

    .sftp_wrapper {
      position: relative;
      height: 100%;
      width: 100%;

      .connection-overlay {
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background-color: v-bind('isDark ? "rgba(0, 0, 0, 0.9)" : "rgba(255, 255, 255, 0.9)"');
        backdrop-filter: v-bind('isDark ? "blur(2px)" : "blur(2px)"');
        z-index: 1000;
        display: flex;
        justify-content: center;
        align-items: center;

        .overlay-content {
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
          color: var(--el-text-color-secondary);

          .loading-icon,
          .error-icon {
            font-size: 48px;
            margin-bottom: 16px;
          }

          .loading-icon {
            color: var(--el-color-primary);
          }

          .error-icon {
            color: var(--el-color-danger);
          }

          p {
            margin: 0 0 16px 0;
            font-size: 14px;
          }
        }
      }
    }

    .empty_state {
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      height: 100%;
      color: var(--el-text-color-secondary);

      .empty_icon {
        font-size: 48px;
        margin-bottom: 16px;
        color: var(--el-color-info);
      }

      p {
        margin: 0 0 16px 0;
        font-size: 14px;
      }
    }
  }
}
</style>