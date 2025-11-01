<template>
  <div class="docker_container">
    <PlusLimitTip />
    <el-table
      v-loading="loading"
      :data="dockerContainers"
      row-key="id"
      size="small"
      center
    >
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
          <div class="wrap-content">
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
          <div v-if="Array.isArray(row.ports) && row.ports.length > 0" class="ports-wrapper">
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
        if (socket.value && socket.value.connected && isPlusActive.value && !loading.value) {
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
      dockerContainers.value = data
    })
    socket.value.on('docker_containers_logs', (data) => {
      // console.log('docker_containers_logs:', data)
      dockerLogs.value = data
      showLogsDialog.value = true
    })
    socket.value.on('docker_operation_result', (result) => {
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

onMounted(() => {
  connectDocker()
  // 如果组件初始可见，启动定时器，每3秒静默刷新容器列表
  if (props.visible) {
    refreshInterval.value = setInterval(() => {
      if (socket.value && socket.value.connected && isPlusActive.value && !loading.value) {
        socket.value.emit('docker_get_containers_data')
      }
    }, 3000)
  }
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
  display: flex;
  gap: 10px;
  padding: 10px;
  position: relative;

  :deep(.wrap-cell) {
    .cell {
      white-space: normal !important;
      word-break: break-all;
      line-height: 1.5;
    }
  }

  .wrap-content {
    word-break: break-all;
    white-space: normal;
    line-height: 1.5;
  }

  .ports-wrapper {
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
    flex-wrap: nowrap;
    justify-content: flex-end;
    align-items: center;
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
