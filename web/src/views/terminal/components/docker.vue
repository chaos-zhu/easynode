<template>
  <div class="docker_container">
    <PlusLimitTip />

    <!-- 顶部工具栏：全选、刷新与批量操作提示 -->
    <div class="top_toolbar">
      <div class="left_tools">
        <el-checkbox
          v-if="isPlusActive"
          v-model="checkAll"
          :indeterminate="isIndeterminate"
          class="select_all_checkbox"
          @change="handleSelectAll"
        >
          全选
        </el-checkbox>
        <div v-if="selectedContainers.length > 0 || batchOperating" class="batch_info_tag">
          <template v-if="batchOperating">
            正在{{ batchProgress.action }}... <span class="progress">{{ batchProgress.current }}/{{ batchProgress.total }}</span>
          </template>
          <template v-else>
            已选中 <span class="count">{{ selectedContainers.length }}</span> 个
          </template>
        </div>
      </div>

      <div class="right_tools">
        <!-- 批量操作按钮组 -->
        <transition name="fade">
          <div v-if="selectedContainers.length > 0" class="batch_actions">
            <el-button-group>
              <el-button
                type="success"
                size="small"
                :disabled="batchOperating"
                @click="handleBatchStart"
              >
                批量启动
              </el-button>
              <el-button
                type="primary"
                size="small"
                :disabled="batchOperating"
                @click="handleBatchRestart"
              >
                重启
              </el-button>
              <el-button
                type="warning"
                size="small"
                :disabled="batchOperating"
                @click="handleBatchStop"
              >
                停止
              </el-button>
              <el-button
                type="danger"
                size="small"
                :disabled="batchOperating"
                @click="handleBatchDelete"
              >
                删除
              </el-button>
            </el-button-group>
          </div>
        </transition>

        <div v-if="dockerServerErr" style="margin-right: 10px;">
          <el-tag type="danger" effect="light" size="small">Docker服务连接失败</el-tag>
        </div>
        <el-button
          type="primary"
          :loading="loading"
          size="small"
          :icon="RefreshRight"
          @click="() => reconnectDocker(true)"
        >
          刷新
        </el-button>
      </div>
    </div>

    <!-- 卡片列表区域 -->
    <div v-loading="loading" class="card_container_wrapper">
      <el-empty v-if="dockerContainers.length === 0 && !loading" description="暂无容器" />

      <el-row :gutter="12">
        <el-col
          v-for="row in dockerContainers"
          :key="row.id"
          :xs="24"
          :sm="12"
          :md="12"
          :lg="8"
          :xl="6"
          class="mb-3"
        >
          <el-card
            class="container_card"
            :class="{ 'is-selected': isSelected(row) }"
            shadow="hover"
          >
            <!-- 背景图标（新增） -->
            <div class="card_bg_icon">
              <img
                :src="getAppIcon(row.image)"
                loading="lazy"
                @error="handleIconError"
              >
            </div>

            <!-- 卡片头部：选择框 + 名称 + 状态 -->
            <div class="card_header">
              <div class="header_left">
                <el-checkbox
                  v-if="isPlusActive"
                  :model-value="isSelected(row)"
                  @change="() => toggleSelection(row)"
                />
                <span class="container_name" :title="row.name">{{ row.name }}</span>
              </div>
              <el-tag
                :type="getStatusType(row.status)"
                size="small"
                effect="dark"
                class="status_tag"
              >
                {{ row.status }}
              </el-tag>
            </div>

            <!-- 卡片内容：信息展示 -->
            <div class="card_content">
              <div class="info_row">
                <span class="label">ID:</span>
                <span class="value text-truncate" :title="row.id">{{ row.id.substring(0, 12) }}</span>
              </div>

              <div class="info_row">
                <span class="label">镜像:</span>
                <span class="value text-truncate" :title="row.image">{{ row.image }}</span>
              </div>

              <div class="info_row">
                <span class="label">时长:</span>
                <span class="value">{{ row.uptime }}</span>
              </div>

              <div class="info_row ports_row">
                <span class="label">端口:</span>
                <div class="ports_wrapper">
                  <template v-if="Array.isArray(row.ports) && row.ports.length > 0">
                    <template v-for="port in row.ports" :key="port">
                      <el-tooltip
                        v-if="!isPortMapped(port)"
                        content="此端口未映射到宿主机"
                        placement="top"
                      >
                        <el-tag size="small" type="info" class="port_tag">{{ port || '--' }}</el-tag>
                      </el-tooltip>
                      <el-tag
                        v-else
                        size="small"
                        class="port_tag link"
                        effect="plain"
                        @click="handlePortClick(port)"
                      >
                        {{ port || '--' }}
                      </el-tag>
                    </template>
                  </template>
                  <span v-else class="text-gray">--</span>
                </div>
              </div>
            </div>

            <!-- 卡片底部：操作按钮 -->
            <div class="card_actions">
              <el-tooltip content="启动" placement="top" :hide-after="0">
                <el-button
                  type="success"
                  :icon="VideoPlay"
                  circle
                  plain
                  size="small"
                  :disabled="row.status === 'running'"
                  @click="handleStart(row)"
                />
              </el-tooltip>

              <el-tooltip content="重启" placement="top" :hide-after="0">
                <el-button
                  type="primary"
                  :icon="RefreshRight"
                  circle
                  plain
                  size="small"
                  :disabled="row.status !== 'running'"
                  @click="handleRestart(row)"
                />
              </el-tooltip>

              <el-tooltip content="停止" placement="top" :hide-after="0">
                <el-button
                  type="warning"
                  :icon="VideoPause"
                  circle
                  plain
                  size="small"
                  :disabled="row.status !== 'running'"
                  @click="handleStop(row)"
                />
              </el-tooltip>

              <el-tooltip content="删除" placement="top" :hide-after="0">
                <el-button
                  type="danger"
                  :icon="Delete"
                  circle
                  plain
                  size="small"
                  @click="handleDelete(row)"
                />
              </el-tooltip>

              <el-tooltip content="日志" placement="top" :hide-after="0">
                <el-button
                  type="info"
                  :icon="Document"
                  circle
                  plain
                  size="small"
                  @click="handleLogs(row)"
                />
              </el-tooltip>
            </div>
          </el-card>
        </el-col>
      </el-row>
    </div>

    <!-- 弹窗组件保持不变 -->
    <CodeEdit
      :key="logDialogKey"
      v-model:show="showLogsDialog"
      :original-code="dockerLogs"
      :disabled="true"
      :filename="containerName"
      :scroll-to-bottom="true"
      @closed="() => showLogsDialog = false"
    />
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed, watch, getCurrentInstance } from 'vue'
import { VideoPlay, VideoPause, RefreshRight, Delete, Document } from '@element-plus/icons-vue'
import CodeEdit from '@/components/code-edit/index.vue'
import PlusLimitTip from '@/components/common/PlusLimitTip.vue'
import { generateSocketInstance } from '@/utils'
import dayjs from 'dayjs'

const { proxy: { $store, $message, $messageBox } } = getCurrentInstance()

const props = defineProps({
  hostId: {
    type: String,
    required: true
  },
  host: {
    type: String,
    required: true
  },
  visible: {
    type: Boolean,
    required: true
  }
})

const socket = ref(null)
const loading = ref(false)
const dockerContainers = ref([])
const dockerServerErr = ref(false)
const dockerLogs = ref('')
const currentContainer = ref(null)
const logInterval = ref(null)
const refreshInterval = ref(null)
const showLogsDialog = ref(false)
const logDialogKey = ref(0)
// const tableRef = ref(null) // 移除 tableRef
const selectedContainers = ref([])
const batchOperating = ref(false)
const batchProgress = ref({ current: 0, total: 0, action: '' }) // 批量操作进度
const hostId = computed(() => props.hostId)
const containerName = computed(() => `${ currentContainer.value?.name }.log(自动刷新)` || '')
const isPlusActive = computed(() => $store.isPlusActive)

// 全选相关计算属性
const checkAll = computed({
  get() {
    return dockerContainers.value.length > 0 && selectedContainers.value.length === dockerContainers.value.length
  },
  set(val) {
    handleSelectAll(val)
  }
})

const isIndeterminate = computed(() => {
  return selectedContainers.value.length > 0 && selectedContainers.value.length < dockerContainers.value.length
})

watch(() => props.visible, (newVal) => {
  if (newVal) {
    refreshDockerContainers(false, 0)
    if (!refreshInterval.value) {
      refreshInterval.value = setInterval(() => {
        if (socket.value && socket.value.connected && isPlusActive.value && !loading.value && selectedContainers.value.length === 0) {
          socket.value.emit('docker_get_containers_data')
        }
      }, 3500)
    }
  } else {
    // 组件变为不可见时，暂停定时器
    if (refreshInterval.value) {
      clearInterval(refreshInterval.value)
      refreshInterval.value = null
    }
  }
})

watch(() => showLogsDialog.value, (newVal) => {
  if (!newVal) {
    dockerLogs.value = ''
    clearInterval(logInterval.value)
    return
  }
  logInterval.value = setInterval(() => {
    intervalLogs()
  }, 3000)
})

watch(() => isPlusActive.value, (newVal) => {
  if (!newVal) {
    dockerContainers.value = [{
      'id': 'c36daaaa5cbaa3',
      'name': 'easynode',
      'image': 'chaoszhu/easynode:latest',
      'status': 'running',
      'ports': [
        '0.0.0.0:8082->8082/tcp',
      ],
      'createdAt': new Date().toLocaleString(),
      'uptime': '49 minutes'
    },]
  }
}, {
  immediate: true
})

// 根据状态返回对应的类型
const getStatusType = (status) => {
  switch (status) {
    case 'running':
      return 'success'
    case 'exited':
      return 'danger'
    case 'paused':
      return 'warning'
    default:
      return 'info'
  }
}

const connectDocker = () => {
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  socket.value = generateSocketInstance('/docker')
  socket.value.on('connect', () => {
    console.log('/docker socket已连接：', hostId.value)
    loading.value = true
    socket.value.emit('ws_docker', { hostId: hostId.value })
    socket.value.on('docker_containers_data', (data) => {
      // console.log('docker_containers_data:', data)
      dockerServerErr.value = false
      loading.value = false
      if (!Array.isArray(data)) return

      // 更新数据的同时，尝试保留选中状态 (如果容器ID依然存在)
      const currentSelectedIds = new Set(selectedContainers.value.map(c => c.id))

      const newData = data.map(item => ({
        ...item,
        createdAt: dayjs(item.createdAt).format('YYYY-MM-DD HH:mm:ss')
      }))

      dockerContainers.value = newData

      // 过滤掉已经不存在的选中项
      if (selectedContainers.value.length > 0) {
        selectedContainers.value = newData.filter(item => currentSelectedIds.has(item.id))
      }
    })
    socket.value.on('docker_containers_logs', (data) => {
      // console.log('docker_containers_logs:', data)
      dockerLogs.value = data
      showLogsDialog.value = true
    })
    socket.value.on('docker_operation_result', (result) => {
      if (batchOperating.value) return

      if (result.success) {
        $message.success(result.message)
        refreshDockerContainers(true, 0)
      } else {
        $message.error(result.message)
        loading.value = false
      }
    })
    socket.value.on('docker_connect_fail', () => {
      console.error('docker_connect_fail')
      dockerServerErr.value = true
      loading.value = false
    })
    socket.value.on('docker_not_plus', () => {
      console.warn('docker_not_plus')
      loading.value = false
    })
  })

  socket.value.on('disconnect', (reason) => {
    console.warn('docker websocket 连接断开:', reason)
    loading.value = false
    socket.value = null
  })
}

const refreshDockerContainers = (isLoading = true, delay = 0) => {
  // 如果有选中的容器，暂停刷新
  if (selectedContainers.value.length > 0) {
    console.log('检测到有选中的容器，跳过本次刷新')
    loading.value = false
    return
  }
  if (!socket.value || !socket.value.connected) return connectDocker()
  loading.value = isLoading
  setTimeout(() => {
    socket.value.emit('docker_get_containers_data')
  }, delay)
}

const reconnectDocker = () => {
  if (socket.value) {
    socket.value.removeAllListeners()
    socket.value.close()
    socket.value = null
  }
  selectedContainers.value = [] // 清空选中状态，重新连接后文件列表会变化
  connectDocker()
}

const handleStart = async (row) => {
  if (!socket.value || !socket.value.connected) {
    $message.error('连接已断开，正在刷新')
    refreshDockerContainers(true, 0)
    return
  }
  loading.value = true
  socket.value.emit('docker_start_container', { containerId: row.id })
}

const handleStop = async (row) => {
  if (!socket.value || !socket.value.connected) {
    $message.error('连接已断开，正在刷新')
    refreshDockerContainers(true, 0)
    return
  }
  loading.value = true
  socket.value.emit('docker_stop_container', { containerId: row.id })
}

const handleRestart = async (row) => {
  if (!socket.value || !socket.value.connected) {
    $message.error('连接已断开，正在刷新')
    refreshDockerContainers(true, 0)
    return
  }
  loading.value = true
  socket.value.emit('docker_restart_container', { containerId: row.id })
}

const handleDelete = (row) => {
  $messageBox.confirm(`确认删除容器 ${ row.name }？`, '警告', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    if (!socket.value || !socket.value.connected) {
      $message.error('连接已断开，正在刷新')
      refreshDockerContainers(true, 0)
      return
    }
    loading.value = true
    socket.value.emit('docker_delete_container', { containerId: row.id })
  }).catch(() => {})
}

const isPortMapped = (portStr) => {
  // 判断端口是否映射到宿主机（包含 -> 符号）
  return portStr.includes('->')
}

const handlePortClick = (portStr) => {
  // 解析端口映射字符串，例如: "0.0.0.0:8082->8082/tcp" 或 "[::]:8082->8082/tcp"
  // 提取外部端口号（冒号后、箭头前的数字）
  const match = portStr.match(/:(\d+)->/)
  if (match && match[1]) {
    const port = match[1]
    const url = `http://${ props.host }:${ port }`
    window.open(url, '_blank')
  } else {
    $message.warning('无法解析端口信息')
  }
}

const handleLogs = (row) => {
  if (!socket.value || !socket.value.connected) {
    $message.error('连接已断开,正在刷新')
    refreshDockerContainers(true, 0)
    return
  }

  // 更新 key 强制重新创建 CodeEdit 组件，确保每次都会滚动到底部
  logDialogKey.value++
  currentContainer.value = row
  socket.value.emit('docker_get_containers_logs', { containerId: row.id, tail: 2000 })
}

const intervalLogs = () => {
  if (!socket.value || !socket.value.connected) {
    $message.error('连接已断开,正在刷新')
    clearInterval(logInterval.value)
    refreshDockerContainers(true, 0)
    return
  }
  socket.value.emit('docker_get_containers_logs', { containerId: currentContainer.value.id, tail: 2000 })
}

// ------ 新增的卡片选择逻辑 ------

// 判断单个容器是否被选中
const isSelected = (row) => {
  return selectedContainers.value.some(item => item.id === row.id)
}

// 切换选中状态
const toggleSelection = (row) => {
  const index = selectedContainers.value.findIndex(item => item.id === row.id)
  if (index > -1) {
    selectedContainers.value.splice(index, 1)
  } else {
    selectedContainers.value.push(row)
  }
}

// 全选/取消全选
const handleSelectAll = (val) => {
  if (val) {
    selectedContainers.value = [...dockerContainers.value,]
  } else {
    selectedContainers.value = []
  }
}

// 批量操作 - 串行执行
const executeBatchOperation = async (operation, containers, actionName) => {
  if (!socket.value || !socket.value.connected) {
    $message.error('连接已断开，正在刷新')
    refreshDockerContainers(true, 0)
    return
  }

  if (batchOperating.value) {
    $message.warning('批量操作正在进行中，请稍候')
    return
  }

  batchOperating.value = true
  loading.value = true

  // 初始化进度
  batchProgress.value = {
    current: 0,
    total: containers.length,
    action: actionName
  }

  let successCount = 0
  let failCount = 0
  const failedContainers = [] // 记录失败的容器

  for (let i = 0; i < containers.length; i++) {
    const container = containers[i]
    // 更新进度
    batchProgress.value.current = i + 1

    try {
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('操作超时(30s)'))
        }, 30 * 1000)

        const handleResult = (result) => {
          clearTimeout(timeout)
          socket.value.off('docker_operation_result', handleResult)
          if (result.success) {
            successCount++
            resolve()
          } else {
            failCount++
            reject(new Error(result.message))
          }
        }

        socket.value.on('docker_operation_result', handleResult)
        socket.value.emit(operation, { containerId: container.id })
      })
    } catch (error) {
      console.error(`${ actionName }容器 ${ container.name } 失败:`, error)
      failCount++
      failedContainers.push(container.name)
    }

    // 每个操作之间添加短暂延迟
    if (i < containers.length - 1) {
      await new Promise(resolve => setTimeout(resolve, 500))
    }
  }

  batchOperating.value = false
  loading.value = false

  // 重置进度
  batchProgress.value = { current: 0, total: 0, action: '' }

  // 清空选择
  selectedContainers.value = []

  // 显示结果
  if (failCount === 0) {
    $message.success(`批量${ actionName }完成：全部成功（${ successCount }/${ containers.length }）`)
  } else {
    const failedNames = failedContainers.slice(0, 3).join('、')
    const moreText = failedContainers.length > 3 ? ` 等${ failedContainers.length }个` : ''
    $message.warning(`批量${ actionName }完成：成功 ${ successCount } 个，失败 ${ failCount } 个（${ failedNames }${ moreText }）`)
  }

  // 刷新列表
  refreshDockerContainers(true, 0)
}

// 批量启动
const handleBatchStart = () => {
  const canStart = selectedContainers.value.filter(c => c.status !== 'running')
  if (canStart.length === 0) {
    $message.warning('没有可启动的容器（已选容器都在运行中）')
    return
  }
  $messageBox.confirm(`确认批量启动 ${ canStart.length } 个容器？`, '确认', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'info'
  }).then(() => {
    executeBatchOperation('docker_start_container', canStart, '启动')
  }).catch(() => {})
}

// 批量重启
const handleBatchRestart = () => {
  const canRestart = selectedContainers.value.filter(c => c.status === 'running')
  if (canRestart.length === 0) {
    $message.warning('没有可重启的容器（已选容器都未运行）')
    return
  }
  $messageBox.confirm(`确认批量重启 ${ canRestart.length } 个容器？`, '确认', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(() => {
    executeBatchOperation('docker_restart_container', canRestart, '重启')
  }).catch(() => {})
}

// 批量停止
const handleBatchStop = () => {
  const canStop = selectedContainers.value.filter(c => c.status === 'running')
  if (canStop.length === 0) {
    $message.warning('没有可停止的容器（已选容器都未运行）')
    return
  }
  $messageBox.confirm(`确认批量停止 ${ canStop.length } 个容器？`, '警告', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(() => {
    executeBatchOperation('docker_stop_container', canStop, '停止')
  }).catch(() => {})
}

// 批量删除
const handleBatchDelete = () => {
  $messageBox.confirm(
    `确认批量删除 ${ selectedContainers.value.length } 个容器？此操作不可恢复！`,
    '危险操作',
    {
      confirmButtonText: '确定删除',
      cancelButtonText: '取消',
      type: 'error'
    }
  ).then(() => {
    executeBatchOperation('docker_delete_container', selectedContainers.value, '删除')
  }).catch(() => {})
}
// ------ 图标处理逻辑 ------
const ICON_BASE_URL = 'https://easynode-apps-icon.221022.xyz/images/'
const FALLBACK_ICON = `${ ICON_BASE_URL }docker.png`

const getAppIcon = (imageName) => {
  if (!imageName) return FALLBACK_ICON
  try {
    // 1. 获取最后一个斜杠后的部分 (处理 registry/namespace，如 chaoszhu/easynode -> easynode)
    const nameWithTag = imageName.split('/').pop()
    // 2. 去除 tag (处理 :latest 等)
    const name = nameWithTag.split(':')[0]
    return `${ ICON_BASE_URL }${ name }.png`
  } catch (e) {
    return FALLBACK_ICON
  }
}

const handleIconError = (e) => {
  // 防止死循环：如果已经是默认图就不再替换
  if (e.target.src !== FALLBACK_ICON) {
    e.target.src = FALLBACK_ICON
  }
}

onMounted(() => {
  connectDocker()
})

onUnmounted(() => {
  // 清除刷新定时器
  if (refreshInterval.value) {
    clearInterval(refreshInterval.value)
    refreshInterval.value = null
  }
  // 清除日志定时器
  if (logInterval.value) {
    clearInterval(logInterval.value)
    logInterval.value = null
  }
  // 关闭socket连接
  if (socket.value) {
    socket.value.removeAllListeners()
    socket.value.close()
    socket.value = null
  }
})
</script>

<style lang="scss" scoped>
.docker_container {
  padding: 10px;
  position: relative;
  min-height: 400px;
}

/* 顶部工具栏样式 */
.top_toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
  padding: 0 4px;
  flex-wrap: wrap;
  gap: 10px;

  .left_tools {
    display: flex;
    align-items: center;
    gap: 16px;

    .select_all_checkbox {
      margin-right: 0;
    }

    .batch_info_tag {
      font-size: 14px;
      color: var(--el-text-color-regular);
      background: var(--el-fill-color-light);
      padding: 4px 10px;
      border-radius: 4px;
      display: flex;
      align-items: center;

      .count {
        color: var(--el-color-primary);
        font-weight: bold;
        margin: 0 4px;
      }

      .progress {
        color: var(--el-color-success);
        font-weight: bold;
        margin-left: 5px;
      }
    }
  }

  .right_tools {
    display: flex;
    align-items: center;
    gap: 10px;

    .batch_actions {
      display: inline-flex;
    }
  }
}

/* 卡片容器样式 */
.card_container_wrapper {
  min-height: 200px;
  max-height: 70vh;
  overflow-y: auto;
  overflow-x: hidden;
}

.mb-3 {
  margin-bottom: 12px; // 减少卡片下间距
}

.container_card {
  position: relative;
  height: 100%;
  display: flex;
  flex-direction: column;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  border: 1px solid var(--el-border-color-light);
  background-color: var(--el-bg-color-overlay);

  // 选中状态样式优化：仅高亮边框，移除背景色干扰
  &.is-selected {
    box-shadow: 0 0 0 1px var(--el-color-primary) inset; // 使用内阴影增强边框感，但不改变背景
  }

  // 背景水印图标样式
  .card_bg_icon {
    position: absolute;
    right: 12px;
    // top: 55px; // 避开头部
    top: 50%;
    transform: translateY(-50%) rotate(-15deg);
    transition: all 3s;
    width: 80px;
    height: 80px;
    opacity: 0.15; // 低透明度作为水印
    z-index: 0;
    pointer-events: none; // 点击穿透，不影响下方交互

    img {
      width: 100%;
      height: 100%;
      object-fit: contain;
    }
  }

  :deep(.el-card__body) {
    flex: 1;
    display: flex;
    flex-direction: column;
    padding: 12px; // 保持紧凑
  }

  /* 头部区域 */
  .card_header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--el-border-color-lighter);

    .header_left {
      display: flex;
      align-items: center;
      gap: 6px;
      overflow: hidden;

      .container_name {
        font-weight: 600; // 加粗
        font-size: 15px;
        // 使用主要文字颜色变量，确保在暗色模式下也是亮色（如白色/浅灰）
        color: var(--el-text-color-primary);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
    }
  }

  /* 内容区域 */
  .card_content {
    flex: 1;
    font-size: 13px;
    color: var(--el-text-color-regular);
    margin-bottom: 12px;

    .info_row {
      display: flex;
      margin-bottom: 6px;
      line-height: 1.4;

      .label {
        width: 45px;
        flex-shrink: 0;
        color: var(--el-text-color-secondary); // 使用次级文字颜色
      }

      .value {
        flex: 1;
        word-break: break-all;
        color: var(--el-text-color-regular);
      }

      .text-truncate {
         white-space: nowrap;
         overflow: hidden;
         text-overflow: ellipsis;
         display: block;
      }
    }

    .ports_row {
      align-items: flex-start;

      .ports_wrapper {
        display: flex;
        flex-wrap: wrap;
        gap: 4px;
      }

      .port_tag {
        cursor: default;
        font-size: 12px;
        padding: 0 4px;
        height: 20px;
        line-height: 18px;

        &.link {
          cursor: pointer;
          &:hover {
             opacity: 0.8;
          }
        }
      }

      .text-gray {
        color: var(--el-text-color-placeholder);
      }
    }
  }

  /* 底部操作区 - 使用 Grid 布局绝对均分 */
  .card_actions {
    display: grid;
    grid-template-columns: repeat(5, 1fr); // 5等分
    justify-items: center; // 每个格子内容居中
    align-items: center;
    padding-top: 10px;
    border-top: 1px dashed var(--el-border-color-lighter);

    // 下拉菜单触发器居中
    .dropdown_trigger_wrapper {
      display: flex;
      justify-content: center;
      width: 100%;
    }

    :deep(.el-button) {
      margin: 0;
    }
    // 按钮样式微调
    :deep(.el-button.is-circle) {
      width: 28px;
      height: 28px;
      padding: 5px;
    }
  }
}

/* 动画效果 */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>