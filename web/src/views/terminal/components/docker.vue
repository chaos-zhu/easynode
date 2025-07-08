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
      />
      <el-table-column
        prop="name"
        label="名称"
        show-overflow-tooltip
      />
      <el-table-column
        prop="image"
        label="镜像"
        show-overflow-tooltip
      />
      <el-table-column
        prop="ip"
        label="IP 地址"
        show-overflow-tooltip
      />
      <el-table-column
        prop="ports"
        label="端口"
        show-overflow-tooltip
      >
        <template #default="{ row }">
          <div v-if="Array.isArray(row.ports)">
            <el-tooltip placement="left">
              <template #content>
                <div v-for="port in row.ports" :key="port">
                  {{ port }}
                </div>
              </template>
              <div>
                <div v-for="port in row.ports.slice(0, 1)" :key="port">
                  {{ port }}
                  <span v-if="row.ports.length > 1">...</span>
                </div>
              </div>
            </el-tooltip>
          </div>
          <div v-else>
            {{ row.ports || '--' }}
          </div>
        </template>
      </el-table-column>
      <el-table-column label="资源使用率" width="120">
        <template #default="{ row }">
          <div class="resource_usage">
            <el-tooltip placement="left">
              <template #content>
                <div>
                  <div>CPU 使用: {{ row.cpuUsage }}%</div>
                  <div>内存使用: {{ row.memoryUsed }}</div>
                  <div>内存限额: {{ row.memoryLimit }}</div>
                </div>
              </template>
              <div class="resource_item">
                <div>CPU: {{ row.cpuUsage }}%</div>
                <div>内存: {{ row.memoryUsage }}%</div>
              </div>
            </el-tooltip>
          </div>
        </template>
      </el-table-column>
      <el-table-column label="状态" align="center">
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
      <el-table-column prop="uptime" label="运行时长" />
      <el-table-column label="操作" align="center" width="230">
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
            <el-tooltip content="启动" placement="top" :disabled="row.status === 'running'">
              <el-button
                type="success"
                :icon="VideoPlay"
                circle
                size="small"
                :disabled="row.status === 'running'"
                @click="handleStart(row)"
              />
            </el-tooltip>
            <el-tooltip content="重启" placement="top" :disabled="row.status !== 'running'">
              <el-button
                type="primary"
                :icon="RefreshRight"
                circle
                size="small"
                :disabled="row.status !== 'running'"
                @click="handleRestart(row)"
              />
            </el-tooltip>
            <el-tooltip content="停止" placement="top" :disabled="row.status !== 'running'">
              <el-button
                type="warning"
                :icon="VideoPause"
                circle
                size="small"
                :disabled="row.status !== 'running'"
                @click="handleStop(row)"
              />
            </el-tooltip>
            <el-tooltip content="删除" placement="top">
              <el-button
                type="danger"
                :icon="Delete"
                circle
                size="small"
                @click="handleDelete(row)"
              />
            </el-tooltip>
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
      v-model:show="showLogsDialog"
      :original-code="dockerLogs"
      :disabled="true"
      :filename="containerName"
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
import socketIo from 'socket.io-client'
import { EventBus } from '@/utils'

const { io } = socketIo
const { proxy: { $store, $serviceURI, $message, $messageBox } } = getCurrentInstance()

const props = defineProps({
  hostId: {
    type: String,
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
const showLogsDialog = ref(false)
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
const token = computed(() => $store.token)
const hostId = computed(() => props.hostId)
const containerName = computed(() => `${ currentContainer.value?.name }.log(自动刷新)` || '')
const isPlusActive = computed(() => $store.isPlusActive)

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
      'uptime': '49 minutes',
      'cpuUsage': '0.17',
      'memoryUsage': '22.33',
      'memoryLimit': '1.796GiB',
      'memoryUsed': '410.6MiB',
      'ip': '171.18.0.2'
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
  socket.value = io($serviceURI, {
    path: '/docker',
    forceNew: false,
    reconnection: false,
    reconnectionAttempts: 0
  })
  socket.value.on('connect', () => {
    console.log('/docker socket已连接：', hostId.value)
    loading.value = true
    socket.value.emit('ws_docker', { hostId: hostId.value, token: token.value })
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
  if (!isPlusActive.value) return $message.warning('此功能仅限PLUS版使用')
  if (!socket.value || !socket.value.connected) return connectDocker()
  loading.value = isLoading
  setTimeout(() => {
    socket.value.emit('docker_get_containers_data')
  }, delay)
}

const handleStart = async (row) => {
  $message.success('已发送启动指令')
  EventBus.$emit('exec_external_command', `docker start ${ row.id }`)
  refreshDockerContainers(false, 3000)
}

const handleStop = async (row) => {
  $message.success('已发送停止指令')
  EventBus.$emit('exec_external_command', `docker stop ${ row.id }`)
  refreshDockerContainers(false, 3000)
}

const handleRestart = async (row) => {
  $message.success('已发送重启指令')
  EventBus.$emit('exec_external_command', `docker restart ${ row.id }`)
  refreshDockerContainers(false, 3000)
}

const handleDelete = (row) => {
  $messageBox.confirm(`确认删除容器 ${ row.name }？`, '警告', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    $message.success('已发送删除指令')
    EventBus.$emit('exec_external_command', `docker rm -f ${ row.id }`)
    refreshDockerContainers(false, 3000)
  }).catch(() => {})
}

const handleLogs = (row) => {
  if (!socket.value || !socket.value.connected) {
    $message.error('连接已断开,正在刷新')
    refreshDockerContainers(true, 0)
    return
  }
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
})

onUnmounted(() => {
  if (socket.value) {
    socket.value.removeAllListeners()
    socket.value.close()
    socket.value = null
  }
})
</script>

<style lang="scss" scoped>
.docker_container {
  overflow: auto;
  height: 100%;
  display: flex;
  gap: 10px;
  padding: 10px;
  min-width: 0;
  position: relative;

  .resource_usage {
    .resource_item {
      gap: 3px;
    }
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

  :deep(.el-table tr), :deep(.el-table th.el-table__cell) {
    background-color: transparent;
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
