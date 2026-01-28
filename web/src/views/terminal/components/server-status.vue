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
          <div class="item_title">
            主机
          </div>
        </template>
        <span class="host-info-ip" :title="host">{{ host }}</span>
        <template v-if="pingMs">
          <el-tooltip effect="dark" content="该值为EasyNode服务端主机到目标主机的ping值" placement="bottom">
            <span class="host-ping" :style="{backgroundColor: handlePingColor(pingMs)}">{{ pingMs }}ms</span>
          </el-tooltip>
        </template>
        <el-tag size="small" style="cursor: pointer;margin-left: 10px;" @click="handleCopy">复制</el-tag>
      </el-descriptions-item>

      <el-descriptions-item>
        <template #label>
          <div class="item_title">
            在线
          </div>
        </template>
        <div size="small">
          {{ $tools.formatTime(osInfo.uptime, 'minute') }}
        </div>
      </el-descriptions-item>
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
          <div class="item_title">
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
          <div class="item_title">
            负载
          </div>
        </template>
        <el-tooltip effect="dark" content="过去1分钟、5分钟、15分钟CPU负载" placement="bottom">
          <div class="load-avg-display">
            <span
              v-for="(load, index) in loadAvgFormatted"
              :key="index"
              :class="['load-value', { 'high-load': load.isHigh }]"
            >
              {{ load.value }}{{ index < loadAvgFormatted.length - 1 ? ',' : '' }}
            </span>
          </div>
        </el-tooltip>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item_title">
            内存
          </div>
        </template>
        <el-progress
          :text-inside="true"
          :stroke-width="18"
          :percentage="usedMemPercentage"
          :color="handleUsedColor(usedMemPercentage)"
        />
        <div class="position_right">
          {{ $tools.toFixed(memInfo.usedMemMb / 1024) }}/{{ $tools.toFixed(memInfo.totalMemMb / 1024) }}G
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item_title">
            交换
          </div>
        </template>
        <el-progress
          :text-inside="true"
          :stroke-width="18"
          :percentage="swapPercentage"
          :color="handleUsedColor(swapPercentage)"
        />
        <div class="position_right">
          {{ $tools.toFixed(swapInfo.swapUsed / 1024) }}/{{ $tools.toFixed(swapInfo.swapTotal / 1024) }}G
        </div>
      </el-descriptions-item>
      <el-descriptions-item v-for="(d,idx) in drivesInfo" :key="d.filesystem + idx">
        <template #label>
          <div class="item_title">
            {{ drivesInfo.length > 1 ? `硬盘(${idx+1})` : '硬盘' }}
          </div>
        </template>
        <el-tooltip
          effect="dark"
          placement="top"
          :content="`文件系统：${d.filesystem} 挂载点：${d.mountedOn}`"
        >
          <el-progress
            :text-inside="true"
            :stroke-width="18"
            :percentage="Number(d.usedPercentage)"
            :color="handleUsedColor(Number(d.usedPercentage))"
          />
        </el-tooltip>
        <div class="position_right">
          {{ d.usedGb }}/{{ d.totalGb }}G
        </div>
      </el-descriptions-item>
    </el-descriptions>

    <el-descriptions
      class="margin-top"
      :column="1"
      size="small"
      border
    >
      <el-descriptions-item key="netstat_item">
        <template #label>
          <div class="item_title">
            网络
          </div>
        </template>
        <div class="netstat_info">
          <div class="count_wrap">
            <div class="wrap">
              <img src="@/assets/upload.png" alt="">
              <span class="upload">{{ output || 0 }}</span>
            </div>
            <div class="wrap">
              <img src="@/assets/download.png" alt="">
              <span class="download">{{ input || 0 }}</span>
            </div>
          </div>
          <div class="chart-container">
            <canvas ref="networkChart" width="200" height="80" />
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
          <div class="item_title">
            名称
          </div>
        </template>
        <div size="small">
          {{ osInfo.hostname }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item_title">
            核心
          </div>
        </template>
        <div size="small">
          {{ cpuInfo.cpuCount }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item_title">
            型号
          </div>
        </template>
        <div size="small">
          {{ cpuInfo.cpuModel }}
        </div>
      </el-descriptions-item>
      <el-descriptions-item>
        <template #label>
          <div class="item_title">
            类型
          </div>
        </template>
        <div size="small">
          {{ osInfo.type }} {{ osInfo.release }} {{ osInfo.arch }}
        </div>
      </el-descriptions-item>
    </el-descriptions>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance, watch, onBeforeUnmount, nextTick, onMounted, toRaw, shallowRef } from 'vue'
import { Chart, registerables } from 'chart.js'
import { generateSocketInstance } from '@/utils'

// 注册Chart.js所有组件
Chart.register(...registerables)

const { proxy: { $message, $tools, $store } } = getCurrentInstance()

const props = defineProps({
  hostId: {
    required: true,
    type: String
  },
  visible: {
    required: true,
    type: Boolean
  },
  pingMs: {
    required: true,
    type: [Number, String,]
  }
})

// 状态数据
const serverData = ref({
  connect: false,
  cpuInfo: {},
  memInfo: {},
  swapInfo: {},
  drivesInfo: [{
    filesystem: '',
    mountedOn: '',
    totalGb: '--',
    usedGb: '--',
    freeGb: '--',
    usedPercentage: 0,
    freePercentage: 0
  },],
  netstatInfo: {},
  osInfo: {}
})

const socket = ref(null)
const reconnectTimer = ref(null)
const reconnectAttempts = ref(0)
const maxReconnectAttempts = 10
const reconnectInterval = 3000 // 3秒重连间隔
const isConnecting = ref(false)

// 数据陈旧检测相关
const dataHistory = ref([]) // 记录最近的数据快照
const staleDataThreshold = 10 // 连续n次相同数据触发重连

// 网速图表相关
const networkChart = ref(null) // canvas元素引用
const chartInstance = shallowRef(null) // Chart.js实例，使用shallowRef避免深度响应式
const networkHistory = shallowRef({
  upload: [], // 上传速度历史数据
  download: [], // 下载速度历史数据
  timestamps: [] // 时间戳
})
const maxHistoryLength = 120 // 保存120次数据（约2分钟）

// 计算属性
const host = computed(() => {
  const hostInfo = $store.hostList.find(h => h.id === props.hostId)
  return hostInfo?.host || ''
})

const cpuInfo = computed(() => serverData.value.cpuInfo || {})
const memInfo = computed(() => serverData.value.memInfo || {})
const swapInfo = computed(() => serverData.value.swapInfo || {})
const osInfo = computed(() => serverData.value.osInfo || {})
const drivesInfo = computed(() => serverData.value.drivesInfo || [])
const netstatInfo = computed(() => {
  let { total: netTotal, ...netCards } = serverData.value.netstatInfo || {}
  return { netTotal, netCards: netCards || {} }
})

const cpuUsage = computed(() => Number(cpuInfo.value?.cpuUsage) || 0)
const cpuCount = computed(() => Number(cpuInfo.value?.cpuCount) || 1)
const loadAvg = computed(() => cpuInfo.value?.loadAvg || [0, 0, 0,])

// 格式化负载数据，包含颜色判断
const loadAvgFormatted = computed(() => {
  return loadAvg.value.map(load => {
    const loadValue = Number(load) || 0
    return {
      value: loadValue.toFixed(2),
      isHigh: loadValue >= cpuCount.value // 负载超过CPU核心数时认为是高负载
    }
  })
})

const usedMemPercentage = computed(() => Number(memInfo.value?.usedMemPercentage) || 0)
const swapPercentage = computed(() => {
  let swapPercentage = swapInfo.value?.swapPercentage
  let isNaN = swapPercentage === 'NaN' || Number.isNaN(swapInfo.value?.swapPercentage)
  return isNaN ? 0 : Number(swapPercentage || 0)
})

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

// 清理重连定时器
const clearReconnectTimer = () => {
  if (reconnectTimer.value) {
    clearTimeout(reconnectTimer.value)
    reconnectTimer.value = null
  }
}

// 清理数据历史记录
const clearDataHistory = () => {
  dataHistory.value = []
}

// 检测数据是否陈旧（综合检测：CPU、网速、在线时间、内存、负载）
const checkStaleData = (cpuUsage, uploadMb, downloadMb, uptime, memoryUsage, loadAvg) => {
  // 将负载数组转换为字符串以便比较（取1分钟负载作为主要比较值）
  const loadAvgStr = Array.isArray(loadAvg) ? loadAvg.map(l => Number(l).toFixed(2)).join(',') : ''
  const load1m = Array.isArray(loadAvg) ? Number(loadAvg[0]) || 0 : 0

  const currentData = {
    cpu: cpuUsage,
    upload: uploadMb,
    download: downloadMb,
    uptime: uptime,
    memory: memoryUsage,
    loadAvg: loadAvgStr,
    load1m: load1m
  }

  // 添加到历史
  dataHistory.value.push(currentData)

  // 保持最多 staleDataThreshold 条记录
  if (dataHistory.value.length > staleDataThreshold) {
    dataHistory.value.shift()
  }

  // 不足阈值条记录，不检测
  if (dataHistory.value.length < staleDataThreshold) {
    return false
  }

  const first = dataHistory.value[0]
  const last = dataHistory.value[dataHistory.value.length - 1]

  // 检查在线时间是否停滞（正常情况下 uptime 应该递增）
  // 如果最后一条和第一条的 uptime 完全相同，说明数据可能陈旧
  const uptimeStale = (first.uptime !== undefined && last.uptime !== undefined) &&
    (first.uptime === last.uptime)

  // 检查是否连续n次完全相同（CPU、上行、下行网速、内存、负载都相同）
  const allSame = dataHistory.value.every(d =>
    d.cpu === first.cpu &&
    d.upload === first.upload &&
    d.download === first.download &&
    d.memory === first.memory &&
    d.loadAvg === first.loadAvg
  )

  // 检查是否CPU和内存都相同，且n次数据上下行都为空/0
  const allNetworkEmpty = dataHistory.value.every(d => (!d.upload) && (!d.download))
  const cpuAllSame = dataHistory.value.every(d => d.cpu === first.cpu)
  const memoryAllSame = dataHistory.value.every(d => d.memory === first.memory)
  const loadAllSame = dataHistory.value.every(d => d.loadAvg === first.loadAvg)

  // 陈旧数据判断条件：
  // 1. 所有关键指标（CPU、网速、内存、负载）完全相同
  // 2. 或者 CPU、内存、负载都相同 且 网络流量都为空
  // 3. 或者 在线时间停滞（uptime 没有增加）且 CPU相同
  const isStale = allSame ||
    (allNetworkEmpty && cpuAllSame && memoryAllSame && loadAllSame) ||
    (uptimeStale && cpuAllSame)

  if (isStale) {
    console.warn('server-status: 陈旧数据检测详情:', {
      uptimeStale,
      allSame,
      allNetworkEmpty,
      cpuAllSame,
      memoryAllSame,
      loadAllSame,
      firstData: first,
      lastData: last
    })
  }

  return isStale
}

// 触发陈旧数据重连
const triggerStaleDataReconnect = () => {
  console.warn('server-status: 检测到连续n次相同数据，触发重连...')
  clearDataHistory() // 清除历史记录，避免重连后立即再次触发

  // 断开当前连接
  if (socket.value) {
    socket.value.disconnect()
    socket.value = null
  }

  // 延迟一小段时间后重新连接
  setTimeout(() => {
    if (props.visible && props.hostId) {
      console.log('server-status: 陈旧数据重连中...')
      connectWebSocket()
    }
  }, 1000)
}

// 启动重连
const startReconnect = () => {
  if (reconnectAttempts.value >= maxReconnectAttempts) {
    console.warn('server-status websocket 已达到最大重连次数，停止重连')
    return
  }

  clearReconnectTimer()

  reconnectTimer.value = setTimeout(() => {
    if (props.visible && props.hostId && !isConnecting.value) {
      reconnectAttempts.value++
      console.log(`server-status websocket 尝试重连 (${ reconnectAttempts.value }/${ maxReconnectAttempts })`)
      connectWebSocket()
    }
  }, reconnectInterval)
}

// WebSocket连接函数
const connectWebSocket = () => {
  if (isConnecting.value) {
    return
  }

  isConnecting.value = true

  // 如果已有连接，先断开
  if (socket.value) {
    socket.value.disconnect()
    socket.value = null
  }

  try {
    socket.value = generateSocketInstance('/server-status')

    socket.value.on('connect', () => {
      console.log('server-status websocket 已连接:', socket.value.id)
      isConnecting.value = false
      reconnectAttempts.value = 0 // 重置重连计数器
      clearReconnectTimer()

      socket.value.emit('ws_server_status', { hostId: props.hostId })
    })

    socket.value.on('server_status_data', (data) => {
      serverData.value = data

      // 更新网速图表数据
      if (data.connect && data.netstatInfo && data.netstatInfo.total) {
        const uploadMb = data.netstatInfo.total.outputMb || 0
        const downloadMb = data.netstatInfo.total.inputMb || 0
        updateNetworkHistory(uploadMb, downloadMb)

        // 检测数据是否陈旧（综合检测：CPU、网速、在线时间、内存、负载）
        const currentCpuUsage = Number(data.cpuInfo?.cpuUsage) || 0
        const currentUptime = data.osInfo?.uptime
        const currentMemoryUsage = Number(data.memInfo?.usedMemPercentage) || 0
        const currentLoadAvg = data.cpuInfo?.loadAvg || []
        if (checkStaleData(currentCpuUsage, uploadMb, downloadMb, currentUptime, currentMemoryUsage, currentLoadAvg)) {
          triggerStaleDataReconnect()
          return // 触发重连后，不再处理后续逻辑
        }
      } else if (data.connect) {
        // 连接正常但没有网络数据，也需要检测
        const currentCpuUsage = Number(data.cpuInfo?.cpuUsage) || 0
        const uploadMb = 0
        const downloadMb = 0
        const currentUptime = data.osInfo?.uptime
        const currentMemoryUsage = Number(data.memInfo?.usedMemPercentage) || 0
        const currentLoadAvg = data.cpuInfo?.loadAvg || []
        if (checkStaleData(currentCpuUsage, uploadMb, downloadMb, currentUptime, currentMemoryUsage, currentLoadAvg)) {
          triggerStaleDataReconnect()
          return
        }
      }

      // 如果服务器返回错误状态，停止重连并断开连接
      if (data.error) {
        console.warn('服务器状态监控出现关键错误:', data.errorReason)
        // 停止重连机制
        clearReconnectTimer()
        clearDataHistory() // 清除数据历史
        reconnectAttempts.value = maxReconnectAttempts // 设置为最大值，防止重连

        console.warn(`服务器状态监控已停止: ${ data.errorReason }`)
      }
    })

    socket.value.on('disconnect', (reason) => {
      console.log('server-status websocket 连接断开:', reason)
      isConnecting.value = false

      // 只有在组件仍然可见且需要连接时才重连
      if (props.visible && props.hostId && reason !== 'io client disconnect') {
        startReconnect()
      }
    })

    socket.value.on('connect_error', (error) => {
      console.error('server-status websocket 连接出错:', error.message)
      isConnecting.value = false

      // 连接错误时启动重连
      if (props.visible && props.hostId) {
        startReconnect()
      }
    })

    socket.value.on('error', (error) => {
      console.error('server-status websocket 发生错误:', error)
      isConnecting.value = false
    })

  } catch (error) {
    console.error('创建 server-status websocket 连接失败:', error)
    isConnecting.value = false
    if (props.visible && props.hostId) {
      startReconnect()
    }
  }
}

// 初始化WebSocket连接
const initWebSocket = () => {
  // 重置重连状态
  reconnectAttempts.value = 0
  clearReconnectTimer()
  clearDataHistory() // 重置数据历史
  connectWebSocket()
}

// 断开WebSocket连接
const disconnectWebSocket = () => {
  clearReconnectTimer()
  clearDataHistory() // 清除数据历史
  isConnecting.value = false

  if (socket.value) {
    socket.value.disconnect()
    socket.value = null
  }
}

// 监听hostId变化重新连接
watch(
  () => props.hostId,
  (newHostId) => {
    if (newHostId && props.visible) {
      initWebSocket()
    }
  },
  { immediate: true }
)

// 监听visible变化
watch(
  () => props.visible,
  (newVisible) => {
    if (newVisible && props.hostId) {
      initWebSocket()
    } else if (!newVisible) {
      disconnectWebSocket()
    }
  }
)

// 工具函数
const handleCopy = async () => {
  await navigator.clipboard.writeText(host.value)
  $message.success({ message: '复制成功', center: true })
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

// 初始化网速图表
const initNetworkChart = () => {
  if (!networkChart.value) return

  const ctx = networkChart.value.getContext('2d')

  chartInstance.value = new Chart(ctx, {
    type: 'line',
    data: {
      labels: [], // 时间标签
      datasets: [
        {
          label: '上传',
          data: [],
          borderColor: '#CF8A20',
          backgroundColor: 'rgba(207, 138, 32, 0.1)',
          borderWidth: 1.5,
          fill: false,
          tension: 0.2,
          pointRadius: 0,
          pointHoverRadius: 3
        },
        {
          label: '下载',
          data: [],
          borderColor: '#67c23a',
          backgroundColor: 'rgba(103, 194, 58, 0.1)',
          borderWidth: 1.5,
          fill: false,
          tension: 0.2,
          pointRadius: 0,
          pointHoverRadius: 3
        },
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      scales: {
        x: {
          display: false, // 隐藏x轴标签
          grid: {
            display: false
          }
        },
        y: {
          display: true,
          position: 'left',
          ticks: {
            font: {
              size: 10
            },
            maxTicksLimit: 3,
            callback: function(value) {
              if (value >= 1) {
                return value.toFixed(1) + 'M'
              }
              return (value * 1024).toFixed(0) + 'K'
            }
          },
          grid: {
            color: 'rgba(255, 255, 255, 0.1)'
          }
        }
      },
      plugins: {
        legend: {
          display: false // 隐藏图例
        },
        tooltip: {
          enabled: true,
          mode: 'index',
          intersect: false,
          callbacks: {
            title: function() {
              return '' // 隐藏tooltip标题（时间）
            },
            label: function(context) {
              const value = context.parsed.y
              const label = context.dataset.label
              if (value >= 1) {
                return `${ label }: ${ value.toFixed(2) } MB/s`
              }
              return `${ label }: ${ (value * 1024).toFixed(1) } KB/s`
            }
          }
        }
      },
      interaction: {
        mode: 'index',
        intersect: false
      }
    }
  })
}

// 更新网速历史数据
const updateNetworkHistory = (uploadMb, downloadMb) => {
  const now = new Date()
  const timeLabel = now.toLocaleTimeString('zh-CN', {
    hour12: false,
    minute: '2-digit',
    second: '2-digit'
  })

  // 获取原始数据并直接操作，避免响应式追踪
  const history = toRaw(networkHistory.value)

  // 添加新数据
  history.upload.push(parseFloat(uploadMb) || 0)
  history.download.push(parseFloat(downloadMb) || 0)
  history.timestamps.push(timeLabel)

  // 保持数据长度不超过maxHistoryLength
  if (history.upload.length > maxHistoryLength) {
    history.upload.shift()
    history.download.shift()
    history.timestamps.shift()
  }

  // 手动触发响应式更新
  networkHistory.value = { ...history }

  // 更新图表 - 直接使用原始数据
  if (chartInstance.value) {
    chartInstance.value.data.labels = [...history.timestamps,]
    chartInstance.value.data.datasets[0].data = [...history.upload,]
    chartInstance.value.data.datasets[1].data = [...history.download,]
    chartInstance.value.update('none') // 不使用动画以提高性能
  }
}

onMounted(() => {
  // 等待DOM渲染完成后初始化图表
  nextTick(() => {
    initNetworkChart()
  })
})

onBeforeUnmount(() => {
  // 清理图表实例
  if (chartInstance.value) {
    chartInstance.value.destroy()
    chartInstance.value = null
  }

  // 清理历史数据
  networkHistory.value = {
    upload: [],
    download: [],
    timestamps: []
  }

  // 清理WebSocket连接和重连定时器
  disconnectWebSocket()
})
</script>

<style lang="scss" scoped>
.info_container {
  transition: all 0.15s;
  height: 100%;

  // 连接状态指示器
  .connection-status {
    padding: 8px 12px;
    margin-bottom: 10px;
    background: var(--el-fill-color-extra-light);
    border-radius: 4px;
    font-size: 12px;

    .status-indicator {
      display: flex;
      align-items: center;
      gap: 6px;

      .status-dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        display: inline-block;
        transition: background-color 0.3s;
      }

      .status-text {
        font-weight: 500;
        transition: color 0.3s;
      }

      .reconnect-info {
        color: var(--el-color-warning);
        font-size: 11px;
      }

      &.connected {
        .status-dot {
          background-color: var(--el-color-success);
          box-shadow: 0 0 4px rgba(103, 194, 58, 0.6);
        }
        .status-text {
          color: var(--el-color-success);
        }
      }

      &.connecting {
        .status-dot {
          background-color: var(--el-color-warning);
          animation: pulse 1.5s infinite;
        }
        .status-text {
          color: var(--el-color-warning);
        }
      }

      &.disconnected {
        .status-dot {
          background-color: var(--el-color-danger);
        }
        .status-text {
          color: var(--el-color-danger);
        }
      }

      &.error {
        .status-dot {
          background-color: var(--el-color-danger);
          animation: none; // 停止动画
        }
        .status-text {
          color: var(--el-color-danger);
          font-weight: 600;
        }
      }
    }

    .error-info {
      display: block;
      color: var(--el-color-danger);
      font-size: 10px;
      margin-top: 2px;
      font-weight: normal;
      opacity: 0.8;
      word-break: break-all;
    }
  }

  @keyframes pulse {
    0% {
      opacity: 1;
      transform: scale(1);
    }
    50% {
      opacity: 0.7;
      transform: scale(1.1);
    }
    100% {
      opacity: 1;
      transform: scale(1);
    }
  }

  .item_title {
    user-select: none;
    white-space: nowrap;
    text-align: center;
    min-width: 34px;
    max-width: 34px;
  }

  .host-info-ip {
    word-break: break-all;
    max-width: 92px;
    display: inline-block;
    vertical-align: top;
    margin-right: 10px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .host-ping {
    display: inline-block;
    font-size: 10px;
    padding: 0 5px;
    border-radius: 2px;
  }

  .load-avg-display {
    font-size: 13px;
    font-family: 'Courier New', monospace;

    .load-value {
      color: #13ce66;
      transition: color 0.3s ease;

      &.high-load {
        color: #ff4949;
        font-weight: 600;
      }
    }
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
        .position_right {
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
        color: #242323;
      }
    }
  }

  // 网络
  .netstat_info {
    width: 100%;
    height: 100%;

    .count_wrap {
      display: flex;
      // flex-direction: column;
      justify-content: space-between;
      margin-bottom: 8px;
    }

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

    .chart-container {
      width: 100%;
      height: 80px;
      margin-top: 5px;
      position: relative;

      canvas {
        width: 100% !important;
        height: 100% !important;
        border-radius: 4px;
        background: rgba(0, 0, 0, 0.1);
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
