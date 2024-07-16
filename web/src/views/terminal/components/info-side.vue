<template>
  <div class="info-container" :style="{ width: visible ? `250px` : 0 }">
    <header>
      <a href="/">
        <img src="@/assets/logo-easynode.png" alt="logo">
      </a>
      <!-- <div class="visible" @click="visibleSidebar">
        <svg-icon
          name="icon-xianshi"
          class="svg-icon"
        />
      </div> -->
    </header>
    <el-divider class="first-divider" content-position="center">POSITION</el-divider>
    <el-descriptions class="margin-top" :column="1" size="small" border>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            IP
          </div>
        </template>
        <span style="margin-right: 10px;">{{ host }}</span>
        <el-tag size="small" style="cursor: pointer;" @click="handleCopy">复制</el-tag>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            位置
          </div>
        </template>
        <!-- <div size="small">{{ ipInfo.country || '--' }} {{ ipInfo.regionName }} {{ ipInfo.city }}</div> -->
        <div size="small">{{ ipInfo.country || '--' }} {{ ipInfo.regionName }}</div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            延迟
          </div>
        </template>
        <span style="margin-right: 10px;" class="host-ping">{{ ping }}</span>
        <!-- <span>(http)</span> -->
      </el-descriptions-item>
    </el-descriptions>

    <el-divider content-position="center">INDICATOR</el-divider>
    <el-descriptions class="margin-top" :column="1" size="small" border>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            CPU
          </div>
        </template>
        <el-progress :text-inside="true" :stroke-width="18" :percentage="cpuUsage" :color="handleColor(cpuUsage)" />
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            内存
          </div>
        </template>
        <el-progress :text-inside="true" :stroke-width="18" :percentage="usedMemPercentage"
          :color="handleColor(usedMemPercentage)" />
        <div class="position-right">
          {{ $tools.toFixed(memInfo.usedMemMb / 1024) }}/{{ $tools.toFixed(memInfo.totalMemMb / 1024) }}G
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            硬盘
          </div>
        </template>
        <el-progress :text-inside="true" :stroke-width="18" :percentage="usedPercentage"
          :color="handleColor(usedPercentage)" />
        <div class="position-right">
          {{ driveInfo.usedGb || '--' }}/{{ driveInfo.totalGb || '--' }}G
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            网络
          </div>
        </template>
        <div class="netstat-info">
          <div class="wrap">
            <img src="@/assets/upload.png" alt="">
            <span class="upload">{{ output || 0 }}</span>
          </div>
          <div class="wrap">
            <img src="@/assets/download.png" alt="">
            <span class="download">{{ input || 0 }}</span>
          </div>
        </div>
      </el-descriptions-item>
    </el-descriptions>

    <el-divider content-position="center">INFORMATION</el-divider>
    <el-descriptions class="margin-top" :column="1" size="small" border>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            名称
          </div>
        </template>
        <div size="small">
          {{ osInfo.hostname }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            核心
          </div>
        </template>
        <div size="small">
          {{ cpuInfo.cpuCount }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            型号
          </div>
        </template>
        <div size="small">
          {{ cpuInfo.cpuModel }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            类型
          </div>
        </template>
        <div size="small">
          {{ osInfo.type }} {{ osInfo.release }} {{ osInfo.arch }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            在线
          </div>
        </template>
        <div size="small">
          {{ $tools.formatTime(osInfo.uptime) }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            本地
          </div>
        </template>
        <div size="small">
          {{ osInfo.ip }}
        </div>
      </el-descriptions-item>
    </el-descriptions>

    <el-divider content-position="center">FEATURE</el-divider>
    <el-button :type="sftpStatus ? 'primary' : 'success'" style="display: block;width: 80%;margin: 30px auto;"
      @click="handleSftp">
      {{ sftpStatus ? '关闭SFTP' : '连接SFTP' }}
    </el-button>
    <el-button :type="inputCommandStyle ? 'primary' : 'success'" style="display: block;width: 80%;margin: 30px auto;"
      @click="clickInputCommand">
      命令输入框
    </el-button>
  </div>
</template>
<script setup>
import { ref, reactive, onMounted, onBeforeUnmount, computed, getCurrentInstance } from 'vue'
import socketIo from 'socket.io-client'

const { proxy: { $router, $serviceURI, $message, $notification, $tools } } = getCurrentInstance()

const props = defineProps({
  token: {
    required: true,
    type: String
  },
  host: {
    required: true,
    type: String
  },
  visible: {
    required: true,
    type: Boolean
  },
  showInputCommand: {
    required: true,
    type: Boolean
  },
})

const emit = defineEmits(['update:inputCommandStyle', 'connect-sftp', 'click-input-command'])

const socket = ref(null)
const name = ref('')
const hostData = ref(null)
const ping = ref(0)
const pingTimer = ref(null)
const sftpStatus = ref(false)

const ipInfo = computed(() => hostData.value?.ipInfo || {})
const isError = computed(() => !Boolean(hostData.value?.osInfo))
const cpuInfo = computed(() => hostData.value?.cpuInfo || {})
const memInfo = computed(() => hostData.value?.memInfo || {})
const osInfo = computed(() => hostData.value?.osInfo || {})
const driveInfo = computed(() => hostData.value?.driveInfo || {})
const netstatInfo = computed(() => {
  let { total: netTotal, ...netCards } = hostData.value?.netstatInfo || {}
  return { netTotal, netCards: netCards || {} }
})
const openedCount = computed(() => hostData.value?.openedCount || 0)
const cpuUsage = computed(() => Number(cpuInfo.value?.cpuUsage) || 0)
const usedMemPercentage = computed(() => Number(memInfo.value?.usedMemPercentage) || 0)
const usedPercentage = computed(() => Number(driveInfo.value?.usedPercentage) || 0)
const output = computed(() => {
  let outputMb = Number(netstatInfo.value.netTotal?.outputMb) || 0
  if (outputMb >= 1) return `${outputMb.toFixed(2)} MB/s`
  return `${(outputMb * 1024).toFixed(1)} KB/s`
})
const input = computed(() => {
  let inputMb = Number(netstatInfo.value.netTotal?.inputMb) || 0
  if (inputMb >= 1) return `${inputMb.toFixed(2)} MB/s`
  return `${(inputMb * 1024).toFixed(1)} KB/s`
})
const inputCommandStyle = computed({
  get: () => props.showInputCommand,
  set: (val) => {
    emit('update:inputCommandStyle', val)
  }
})

const handleSftp = () => {
  sftpStatus.value = !sftpStatus.value
  emit('connect-sftp', sftpStatus.value)
}

const clickInputCommand = () => {
  inputCommandStyle.value = true
  emit('click-input-command')
}

const connectIO = () => {
  const { host, token } = props
  socket.value = socketIo($serviceURI, {
    path: '/host-status',
    forceNew: true,
    timeout: 5000,
    reconnectionDelay: 3000,
    reconnectionAttempts: 3
  })

  socket.value.on('connect', () => {
    console.log('/host-status socket已连接：', socket.value.id)
    socket.value.emit('init_host_data', { token, host })
    getHostPing()
    socket.value.on('host_data', (data) => {
      if (!data) return hostData.value = null
      hostData.value = data
    })
  })

  socket.value.on('connect_error', (err) => {
    console.error('host status websocket 连接错误：', err)
    $notification({
      title: '连接客户端失败(重连中...)',
      message: '请检查客户端服务是否正常',
      type: 'error'
    })
  })

  socket.value.on('disconnect', () => {
    hostData.value = null
    $notification({
      title: '客户端连接主动断开(重连中...)',
      message: '请检查客户端服务是否正常',
      type: 'error'
    })
  })
}

const handleCopy = async () => {
  await navigator.clipboard.writeText(props.host)
  $message.success({ message: 'success', center: true })
}

const handleColor = (num) => {
  if (num < 65) return '#8AE234'
  if (num < 85) return '#FFD700'
  if (num < 90) return '#FFFF33'
  if (num <= 100) return '#FF3333'
}

const getHostPing = () => {
  pingTimer.value = setInterval(() => {
    $tools.ping(`http://${props.host}:22022`)
      .then(res => {
        ping.value = res
        if (!import.meta.env.DEV) {
          console.warn('Please tick \'Preserve Log\'')
        }
      })
  }, 3000)
}

onMounted(() => {
  name.value = $router.currentRoute.value.query.name || ''
  if (!props.host || !name.value) return $message.error('参数错误')
  connectIO()
})

onBeforeUnmount(() => {
  socket.value && socket.value.close()
  pingTimer.value && clearInterval(pingTimer.value)
})
</script>


<style lang="scss" scoped>
.info-container {
  // min-width: 250px;
  // max-width: 250px;
  // flex-shrink: 0;
  // width: 250px;
  overflow: scroll;
  background-color: #fff; //#E0E2EF;
  transition: all 0.3s;

  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    height: 30px;
    margin: 10px;
    position: relative;

    img {
      cursor: pointer;
      height: 80%;
    }
  }

  // 表格中系统标识的title
  .item-title {
    user-select: none;
    white-space: nowrap;
    text-align: center;
    min-width: 30px;
    max-width: 30px;
  }

  .host-ping {
    display: inline-block;
    font-size: 13px;
    color: #009933;
    background-color: #e8fff3;
    padding: 0 5px;
  }

  // 分割线title
  :deep(.el-divider__text) {
    color: #a0cfff;
    padding: 0 8px;
    user-select: none;
  }

  // 分割线间距
  :deep(.el-divider--horizontal) {
    margin: 28px 0 10px;
  }

  .first-divider {
    margin: 15px 0 10px;
  }

  // 表格
  :deep(.el-descriptions__table) {
    tr {
      display: flex;

      .el-descriptions__label {
        min-width: 35px;
        flex-shrink: 0;
      }

      .el-descriptions__content {
        position: relative;
        flex: 1;
        display: flex;
        align-items: center;

        .el-progress {
          width: 100%;
        }

        // 进度条右边参数定位
        .position-right {
          position: absolute;
          right: 15px;
        }
      }
    }
  }

  // 进度条
  :deep(.el-progress-bar__inner) {
    display: flex;
    align-items: center;

    .el-progress-bar__innerText {
      display: flex;

      span {
        color: #000;
      }
    }
  }

  // 网络
  .netstat-info {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;

    .wrap {
      flex: 1;
      display: flex;
      align-items: center;
      // justify-content: center;
      padding: 0 5px;

      img {
        width: 15px;
        margin-right: 5px;
      }

      .upload {
        color: #CF8A20;
      }

      .download {
        color: #67c23a;
      }
    }
  }
}
</style>

<style scoped>
.el-descriptions__label {
  vertical-align: middle;
  max-width: 35px;
}
</style>