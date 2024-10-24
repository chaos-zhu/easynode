<template>
  <div class="info_container" :style="{ width: visible ? `250px` : 0 }">
    <!-- <el-divider class="first-divider" content-position="center">地理位置</el-divider> -->
    <el-descriptions
      class="margin-top"
      :column="1"
      size="small"
      border
    >
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            IP
          </div>
        </template>
        <span style="margin-right: 10px;">{{ host }}</span>
        <template v-if="pingMs">
          <el-tooltip effect="dark" content="该值为EasyNode服务端主机到目标主机的ping值" placement="bottom">
            <span class="host-ping" :style="{backgroundColor: handlePingColor(pingMs)}">{{ pingMs }}ms</span>
          </el-tooltip>
        </template>
        <el-tag size="small" style="cursor: pointer;margin-left: 10px;" @click="handleCopy">复制</el-tag>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            位置
          </div>
        </template>
        <div size="small">{{ ipInfo.country || '--' }} {{ ipInfo.regionName }}</div>
      </el-descriptions-item>
      <!-- <el-descriptions-item v-if="pingMs">
        <template #label>
          <div class="item-title">
            延迟
          </div>
        </template>
        <span style="margin-right: 10px;" class="host-ping">{{ pingMs }}</span>
      </el-descriptions-item> -->
    </el-descriptions>

    <!-- <el-divider content-position="center">实时监控</el-divider> -->
    <br>

    <el-descriptions
      class="margin-top"
      :column="1"
      size="small"
      border
    >
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            CPU
          </div>
        </template>
        <el-progress
          :text-inside="true"
          :stroke-width="18"
          :percentage="cpuUsage"
          :color="handleUsedColor(cpuUsage)"
        />
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            内存
          </div>
        </template>
        <el-progress
          :text-inside="true"
          :stroke-width="18"
          :percentage="usedMemPercentage"
          :color="handleUsedColor(usedMemPercentage)"
        />
        <div class="position-right">
          {{ $tools.toFixed(memInfo.usedMemMb / 1024) }}/{{ $tools.toFixed(memInfo.totalMemMb / 1024) }}G
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            交换
          </div>
        </template>
        <el-progress
          :text-inside="true"
          :stroke-width="18"
          :percentage="swapPercentage"
          :color="handleUsedColor(swapPercentage)"
        />
        <div class="position-right">
          {{ $tools.toFixed(swapInfo.swapUsed / 1024) }}/{{ $tools.toFixed(swapInfo.swapTotal / 1024) }}G
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item-title">
            硬盘
          </div>
        </template>
        <el-progress
          :text-inside="true"
          :stroke-width="18"
          :percentage="usedPercentage"
          :color="handleUsedColor(usedPercentage)"
        />
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

    <!-- <el-divider content-position="center">系统信息</el-divider> -->
    <br>

    <el-descriptions
      class="margin-top"
      :column="1"
      size="small"
      border
    >
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
  </div>
</template>
<script setup>
import { ref, onBeforeUnmount, computed, getCurrentInstance } from 'vue'

const { proxy: { $message, $tools } } = getCurrentInstance()

const props = defineProps({
  hostInfo: {
    required: true,
    type: Object
  },
  visible: {
    required: true,
    type: Boolean
  },
  pingData: {
    required: true,
    type: Object
  }
})

const socket = ref(null)
const pingTimer = ref(null)

const hostData = computed(() => props.hostInfo.monitorData || {})
const host = computed(() => props.hostInfo.host)
const ipInfo = computed(() => hostData.value?.ipInfo || {})
// const isError = computed(() => !Boolean(hostData.value?.osInfo))
const cpuInfo = computed(() => hostData.value?.cpuInfo || {})
const memInfo = computed(() => hostData.value?.memInfo || {})
const swapInfo = computed(() => hostData.value?.swapInfo || {})
const osInfo = computed(() => hostData.value?.osInfo || {})
const driveInfo = computed(() => hostData.value?.driveInfo || {})
const netstatInfo = computed(() => {
  let { total: netTotal, ...netCards } = hostData.value?.netstatInfo || {}
  return { netTotal, netCards: netCards || {} }
})
// const openedCount = computed(() => hostData.value?.openedCount || 0)
const cpuUsage = computed(() => Number(cpuInfo.value?.cpuUsage) || 0)
const usedMemPercentage = computed(() => Number(memInfo.value?.usedMemPercentage) || 0)
const swapPercentage = computed(() => {
  let swapPercentage = swapInfo.value?.swapPercentage
  let isNaN = swapPercentage === 'NaN' || Number.isNaN(swapInfo.value?.swapPercentage)
  return isNaN ? 0 : Number(swapPercentage || 0)
})
const usedPercentage = computed(() => Number(driveInfo.value?.usedPercentage) || 0)
const output = computed(() => {
  let outputMb = Number(netstatInfo.value.netTotal?.outputMb) || 0
  if (outputMb >= 1) return `${ outputMb.toFixed(2) } MB/s`
  return `${ (outputMb * 1024).toFixed(1) } KB/s`
})
const input = computed(() => {
  let inputMb = Number(netstatInfo.value.netTotal?.inputMb) || 0
  if (inputMb >= 1) return `${ inputMb.toFixed(2) } MB/s`
  return `${ (inputMb * 1024).toFixed(1) } KB/s`
})

const pingMs = computed(() => {
  let curPingData = props.pingData[host.value] || {}
  if (!curPingData?.success) return false
  return Number(curPingData?.time).toFixed(0)
})

const handleCopy = async () => {
  await navigator.clipboard.writeText(host.value)
  $message.success({ message: 'success', center: true })
}

const handleUsedColor = (num) => {
  if (num < 60) return '#13ce66'
  if (num < 80) return '#e6a23c'
  if (num <= 100) return '#ff4949'
}

const handlePingColor = (num) => {
  if (num < 100) return 'rgba(19, 206, 102, 0.5)' // #13ce66
  if (num < 250) return 'rgba(230, 162, 60, 0.5)' // #e6a23c
  return 'rgba(255, 73, 73, 0.5)' // #ff4949
}

onBeforeUnmount(() => {
  socket.value && socket.value.close()
  pingTimer.value && clearInterval(pingTimer.value)
})
</script>

<style lang="scss" scoped>
.info_container {
  // border-top: 1px solid var(--el-border-color);
  flex-shrink: 0;
  // overflow: scroll;
  transition: all 0.15s;

  // header {
  //   display: flex;
  //   justify-content: space-between;
  //   align-items: center;
  //   height: 30px;
  //   margin: 10px;
  //   position: relative;

  //   img {
  //     cursor: pointer;
  //     height: 80%;
  //   }
  // }

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
    font-size: 10px;
    padding: 0 5px;
    border-radius: 2px;
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
        color: #434343;
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