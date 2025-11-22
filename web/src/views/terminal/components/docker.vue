<template>
  <div class="docker_container">
    <PlusLimitTip />
    <!-- 顶部批量操作工具栏 -->
    <div v-if="selectedContainers.length > 0 || batchOperating" class="batch_toolbar">
      <div class="batch_info">
        <template v-if="batchOperating">
          正在{{ batchProgress.action }}... <span class="progress">{{ batchProgress.current }}/{{ batchProgress.total }}</span>
        </template>
        <template v-else>
          已选中 <span class="count">{{ selectedContainers.length }}</span> 个容器
        </template>
      </div>
      <div class="batch_actions">
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
          批量重启
        </el-button>
        <el-button
          type="warning"
          size="small"
          :disabled="batchOperating"
          @click="handleBatchStop"
        >
          批量停止
        </el-button>
        <el-button
          type="danger"
          size="small"
          :disabled="batchOperating"
          @click="handleBatchDelete"
        >
          批量删除
        </el-button>
      </div>
    </div>
    <el-table
      ref="tableRef"
      v-loading="loading"
      class="docker_table"
      :data="dockerContainers"
      row-key="id"
      size="small"
      center
      @selection-change="handleSelectionChange"
    >
      <el-table-column
        type="selection"
        width="55"
        :selectable="() => isPlusActive"
      />
      <el-table-column
        prop="id"
        label="ID"
        show-overflow-tooltip
        width="108"
      />
      <el-table-column
        prop="name"
        label="名称"
        show-overflow-tooltip
      />
      <el-table-column
        prop="image"
        label="镜像"
        class-name="wrap-cell"
      >
        <template #default="{ row }">
          <div class="wrap_content">
            {{ row.image }}
          </div>
        </template>
      </el-table-column>
      <el-table-column
        prop="ports"
        label="端口"
        width="160"
        class-name="wrap-cell"
      >
        <template #default="{ row }">
          <div v-if="Array.isArray(row.ports) && row.ports.length > 0" class="ports_wrapper">
            <template v-for="port in row.ports" :key="port">
              <el-tooltip
                v-if="!isPortMapped(port)"
                content="此端口未映射到宿主机"
                placement="left"
              >
                <div class="port_text">
                  {{ port }}
                </div>
              </el-tooltip>
              <div
                v-else
                class="port_link"
                @click="handlePortClick(port)"
              >
                {{ port }}
              </div>
            </template>
          </div>
          <div v-else>
            {{ row.ports || '--' }}
          </div>
        </template>
      </el-table-column>
      <el-table-column label="状态" align="center" width="100">
        <template #default="{ row }">
          <el-tag
            :type="getStatusType(row.status)"
            size="small"
            effect="light"
            style="width: 60px;"
          >
            {{ row.status }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column
        prop="createdAt"
        label="创建时间"
        width="160"
      />
      <el-table-column prop="uptime" label="运行时长" width="142" />
      <el-table-column
        label="操作"
        align="center"
        width="230"
        fixed="right"
      >
        <template #header>
          <div class="header_buttons">
            <div v-if="dockerServerErr" style="margin-right: 6px;">
              <el-tag type="danger" effect="light" size="small">Docker服务连接失败</el-tag>
            </div>
            <el-button
              type="primary"
              :loading="loading"
              size="small"
              @click="() => refreshDockerContainers(true)"
            >
              刷新
            </el-button>
          </div>
        </template>
        <template #default="{ row }">
          <div class="action_buttons">
            <el-button
              type="success"
              :icon="VideoPlay"
              circle
              size="small"
              :disabled="row.status === 'running'"
              title="启动"
              @click="handleStart(row)"
            />
            <el-button
              type="primary"
              :icon="RefreshRight"
              circle
              size="small"
              :disabled="row.status !== 'running'"
              title="重启"
              @click="handleRestart(row)"
            />
            <el-button
              type="warning"
              :icon="VideoPause"
              circle
              size="small"
              :disabled="row.status !== 'running'"
              title="停止"
              @click="handleStop(row)"
            />
            <el-button
              type="danger"
              :icon="Delete"
              circle
              size="small"
              title="删除"
              @click="handleDelete(row)"
            />
            <el-dropdown trigger="click">
              <el-button
                type="info"
                class="more_button"
                :icon="MoreFilled"
                circle
                size="small"
              />
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item @click="handleLogs(row)"> 查看日志 </el-dropdown-item>
                  <el-dropdown-item @click="handleTerminal(row)"> 进入容器 </el-dropdown-item>
                  <el-dropdown-item @click="handlePullImage(row)"> 拉取新镜像 </el-dropdown-item>
                  <el-dropdown-item @click="handleMakeImage(row)"> 制作成镜像 </el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
          </div>
        </template>
      </el-table-column>
    </el-table>
    <CodeEdit
      :key="logDialogKey"
      v-model:show="showLogsDialog"
      :original-code="dockerLogs"
      :disabled="true"
      :filename="containerName"
      :scroll-to-bottom="true"
      @closed="() => showLogsDialog = false"
    />
    <el-dialog
      v-model="makeImageDialog"
      title="制作镜像"
      top="250px"
      width="450px"
    >
      <el-form
        ref="makeImageFormRef"
        :model="makeImageForm"
        :rules="makeImageRules"
        label-width="120px"
      >
        <el-form-item label="镜像名称" prop="name">
          <el-input v-model="makeImageForm.name" />
        </el-form-item>
        <el-form-item label="标签" prop="tag">
          <el-input v-model="makeImageForm.tag" />
        </el-form-item>
        <el-form-item label="作者" prop="author">
          <el-input v-model="makeImageForm.author" />
        </el-form-item>
        <el-form-item label="提交说明" prop="message">
          <el-input v-model="makeImageForm.message" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="makeImageDialog = false">取消</el-button>
        <el-button type="primary" @click="handleMakeImageConfirm">确定</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed, watch, getCurrentInstance } from 'vue'
import { VideoPlay, VideoPause, RefreshRight, Delete, MoreFilled } from '@element-plus/icons-vue'
import CodeEdit from '@/components/code-edit/index.vue'
import PlusLimitTip from '@/components/common/PlusLimitTip.vue'
import { EventBus, generateSocketInstance } from '@/utils'
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
const makeImageDialog = ref(false)
const makeImageFormRef = ref(null)
const tableRef = ref(null)
const selectedContainers = ref([])
const batchOperating = ref(false)
const batchProgress = ref({ current: 0, total: 0, action: '' }) // 批量操作进度
const makeImageForm = ref({
  name: '',
  tag: 'latest',
  author: '',
  message: ''
})
const makeImageRules = ref({
  name: [
    { required: true, message: '请输入镜像名称', trigger: 'blur' },
  ],
  tag: [
    { required: false, message: '请输入标签', trigger: 'blur' },
  ],
  author: [
    { required: false, message: '请输入作者', trigger: 'blur' },
  ],
  message: [
    { required: false, message: '请输入提交说明', trigger: 'blur' },
  ]
})
const hostId = computed(() => props.hostId)
const containerName = computed(() => `${ currentContainer.value?.name }.log(自动刷新)` || '')
const isPlusActive = computed(() => $store.isPlusActive)

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
      dockerContainers.value = data.map(item => ({
        ...item,
        createdAt: dayjs(item.createdAt).format('YYYY-MM-DD HH:mm:ss')
        // uptime: dayjs(item.uptime).format('HH:mm:ss')
      }))
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
    return
  }
  if (!socket.value || !socket.value.connected) return connectDocker()
  loading.value = isLoading
  setTimeout(() => {
    socket.value.emit('docker_get_containers_data')
  }, delay)
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

const handleTerminal = (row) => {
  $message.success('已发送进入容器指令')
  EventBus.$emit('exec_external_command', `docker exec -it ${ row.id } /bin/sh`)
}

const handlePullImage = (row) => {
  $message.success('已发送拉取镜像指令')
  EventBus.$emit('exec_external_command', `docker pull ${ row.image }`)
}

const handleMakeImage = (row) => {
  currentContainer.value = row
  makeImageDialog.value = true
}

const handleMakeImageConfirm = () => {
  makeImageFormRef.value.validate((valid) => {
    if (!valid) return
    $message.success('已发送制作镜像指令')
    const { name, tag, author, message } = makeImageForm.value
    // docker commit -a "作者名" -m "提交说明" 容器ID my-new-image:v1.0
    EventBus.$emit('exec_external_command', `docker commit -a "${ author }" -m "${ message }" ${ currentContainer.value.id } ${ name }:${ tag }`)
    makeImageDialog.value = false
  })
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

// 处理选择变化
const handleSelectionChange = (selection) => {
  selectedContainers.value = selection
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
  tableRef.value?.clearSelection()
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

  .batch_toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 6px 16px;
    animation: slideDown 0.3s ease-out;
    transition: all 0.3s ease;

    .batch_info {
      color: #fff;
      font-size: 14px;
      font-weight: 500;

      .count {
        font-size: 18px;
        font-weight: bold;
        margin: 0 4px;
      }

      .progress {
        font-size: 16px;
        font-weight: bold;
        margin-left: 8px;
        padding: 2px 10px;
        background: rgba(255, 255, 255, 0.2);
        border-radius: 12px;
        display: inline-block;
      }
    }

    .batch_actions {
      display: flex;
    }
  }

  @keyframes slideDown {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .docker_table {
    min-height: 50vh;
    max-height: 72vh;
    overflow: auto;
  }

  :deep(.wrap-cell) {
    .cell {
      white-space: normal !important;
      word-break: break-all;
      line-height: 1.5;
    }
  }

  .wrap_content {
    word-break: break-all;
    white-space: normal;
    line-height: 1.5;
  }

  .ports_wrapper {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .port_link {
    color: #409eff;
    cursor: pointer;
    transition: all 0.2s;
    word-break: break-all;
    white-space: normal;
    line-height: 1.5;

    &:hover {
      color: #66b1ff;
      text-decoration: underline;
    }
  }

  .port_text {
    color: #606266;
    word-break: break-all;
    white-space: normal;
    line-height: 1.5;
    cursor: help;
  }

  .header_buttons {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    align-items: center;
    gap: 8px;
  }

  .action_buttons {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    .more_button {
      margin-left: 12px;
    }
  }

  :deep(.el-tag) {
    margin: 0 auto;
    display: flex;
    justify-content: center;
    align-items: center;
    min-width: 60px;
  }
}
</style>
