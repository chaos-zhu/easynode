import { computed, onScopeDispose, ref, shallowRef, watch } from 'vue'
import { generateSocketInstance } from '@/utils'

const STATUS_PROBE_INTERVAL = 3000
const STATUS_PROBE_TIMEOUT = 2500
const STATUS_RELEASE_DELAY = 300
const LOCAL_LATENCY_SAMPLE_SIZE = 5
const MANUAL_RECONNECT_COOLDOWN = 3000
const MANUAL_RECONNECT_TIMEOUT = 15000
const statusEntries = new Map()

export function createEmptyServerStatus() {
  return {
    connect: false,
    cpuInfo: {},
    memInfo: {},
    swapInfo: {},
    drivesInfo: [],
    netstatInfo: {},
    osInfo: {},
    latency: {
      serviceToInstanceMs: null,
      serviceToInstanceAvailable: false,
      measuredAt: null
    }
  }
}

export function medianLatency(samples = []) {
  const values = samples
    .map(Number)
    .filter(value => Number.isFinite(value) && value >= 0)
    .sort((a, b) => a - b)
  if (!values.length) return null
  const middle = Math.floor(values.length / 2)
  const median = values.length % 2
    ? values[middle]
    : (values[middle - 1] + values[middle]) / 2
  return Number(median.toFixed(1))
}

export function formatTransferRate(valueMb) {
  const value = Number(valueMb)
  if (!Number.isFinite(value) || value < 0) return '--'
  if (value >= 1) return `${ value.toFixed(2) } MB/s`
  return `${ (value * 1024).toFixed(1) } KB/s`
}

export function getMetricLevel(value, warningAt = 60, dangerAt = 80) {
  if (value === null || value === undefined || value === '') return 'muted'
  const number = Number(value)
  if (!Number.isFinite(number)) return 'muted'
  if (number >= dangerAt) return 'danger'
  if (number >= warningAt) return 'warning'
  return 'success'
}

function createStatusEntry(hostId) {
  const serverData = shallowRef(createEmptyServerStatus())
  const connectionState = ref('connecting')
  const isReconnecting = ref(false)
  const localToServiceMs = ref(null)
  const localToServiceAvailable = ref(false)
  const localLatencyHistory = []
  let socket = null
  let probeTimer = null
  let releaseTimer = null
  let reconnectTimer = null
  let reconnectOnConnect = false
  let lastReconnectAt = 0
  let consumers = 0

  const clearProbeTimer = () => {
    if (!probeTimer) return
    clearInterval(probeTimer)
    probeTimer = null
  }

  const runLatencyProbe = () => {
    if (!socket?.connected) return
    const probeId = globalThis.crypto?.randomUUID?.() || `${ Date.now() }-${ Math.random() }`
    const start = globalThis.performance?.now?.() ?? Date.now()
    socket.timeout(STATUS_PROBE_TIMEOUT).emit('latency_probe', { probeId }, (error, response = {}) => {
      if (error || response.probeId !== probeId) {
        localToServiceAvailable.value = false
        localToServiceMs.value = null
        return
      }
      const end = globalThis.performance?.now?.() ?? Date.now()
      localLatencyHistory.push(Math.max(0, end - start))
      if (localLatencyHistory.length > LOCAL_LATENCY_SAMPLE_SIZE) localLatencyHistory.shift()
      localToServiceMs.value = medianLatency(localLatencyHistory)
      localToServiceAvailable.value = localToServiceMs.value !== null
    })
  }

  const startLatencyProbe = () => {
    clearProbeTimer()
    runLatencyProbe()
    probeTimer = setInterval(runLatencyProbe, STATUS_PROBE_INTERVAL)
  }

  const clearReconnectTimer = () => {
    if (!reconnectTimer) return
    clearTimeout(reconnectTimer)
    reconnectTimer = null
  }

  const markDataUnavailable = () => {
    serverData.value = {
      ...serverData.value,
      connect: false
    }
    localToServiceAvailable.value = false
    localToServiceMs.value = null
  }

  const beginReconnect = () => {
    clearReconnectTimer()
    clearProbeTimer()
    serverData.value = createEmptyServerStatus()
    localLatencyHistory.length = 0
    localToServiceAvailable.value = false
    localToServiceMs.value = null
    connectionState.value = 'connecting'
    isReconnecting.value = true
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      isReconnecting.value = false
      connectionState.value = 'error'
    }, MANUAL_RECONNECT_TIMEOUT)
  }

  const finishReconnect = () => {
    const shouldRestartProbe = isReconnecting.value && socket?.connected
    clearReconnectTimer()
    isReconnecting.value = false
    reconnectOnConnect = false
    if (shouldRestartProbe) startLatencyProbe()
  }

  const subscribe = () => {
    if (socket?.connected) socket.emit('ws_server_status', { hostId })
  }

  const requestMonitorRestart = () => {
    if (!socket?.connected) return
    socket.timeout(5000).emit('server_status_reconnect', { hostId }, (error, response = {}) => {
      if (!error && response.success) return
      if (!error && response.code === 'RECONNECT_COOLDOWN') {
        subscribe()
        return
      }
      finishReconnect()
      connectionState.value = 'error'
    })
  }

  const connect = () => {
    if (socket) return
    connectionState.value = 'connecting'
    socket = generateSocketInstance('/server-status', {
      forceNew: false,
      reconnection: true,
      reconnectionAttempts: 10,
      reconnectionDelay: 3000
    })

    socket.on('connect', () => {
      connectionState.value = 'connecting'
      if (reconnectOnConnect) {
        reconnectOnConnect = false
        requestMonitorRestart()
      } else {
        subscribe()
      }
      startLatencyProbe()
    })

    socket.on('server_status_reconnect_required', () => {
      beginReconnect()
    })

    socket.on('server_status_data', (data = {}) => {
      serverData.value = {
        ...createEmptyServerStatus(),
        ...data,
        latency: {
          ...createEmptyServerStatus().latency,
          ...data.latency
        }
      }
      connectionState.value = data.error ? 'error' : (data.connect ? 'connected' : 'connecting')
      if (data.error || data.connect) finishReconnect()
    })

    socket.on('server_status_error', () => {
      finishReconnect()
      connectionState.value = 'error'
    })

    socket.on('disconnect', (reason) => {
      clearProbeTimer()
      markDataUnavailable()
      if (reason !== 'io client disconnect') connectionState.value = 'connecting'
    })

    socket.on('connect_error', () => {
      connectionState.value = 'error'
      clearProbeTimer()
    })
  }

  const disconnect = () => {
    clearProbeTimer()
    clearReconnectTimer()
    socket?.disconnect()
    socket = null
    reconnectOnConnect = false
    isReconnecting.value = false
    localLatencyHistory.length = 0
    localToServiceAvailable.value = false
    localToServiceMs.value = null
    connectionState.value = 'idle'
  }

  const reconnect = () => {
    const now = Date.now()
    if (isReconnecting.value || now - lastReconnectAt < MANUAL_RECONNECT_COOLDOWN) return false
    lastReconnectAt = now
    beginReconnect()

    if (socket?.connected) {
      requestMonitorRestart()
    } else {
      reconnectOnConnect = true
      if (!socket) connect()
      else socket.connect()
    }
    return true
  }

  return {
    hostId,
    serverData,
    connectionState,
    isReconnecting,
    localToServiceMs,
    localToServiceAvailable,
    acquire() {
      consumers += 1
      if (releaseTimer) {
        clearTimeout(releaseTimer)
        releaseTimer = null
      }
      connect()
    },
    release() {
      consumers = Math.max(0, consumers - 1)
      if (consumers > 0 || releaseTimer) return
      releaseTimer = setTimeout(() => {
        releaseTimer = null
        if (consumers > 0) return
        disconnect()
        statusEntries.delete(hostId)
      }, STATUS_RELEASE_DELAY)
    },
    reconnect
  }
}

function acquireStatusEntry(hostId) {
  let entry = statusEntries.get(hostId)
  if (!entry) {
    entry = createStatusEntry(hostId)
    statusEntries.set(hostId, entry)
  }
  entry.acquire()
  return entry
}

export function useServerStatus(hostIdSource, enabledSource = true) {
  const activeEntry = shallowRef(null)
  const resolveSource = source => typeof source === 'function' ? source() : source?.value ?? source

  const releaseActiveEntry = () => {
    activeEntry.value?.release()
    activeEntry.value = null
  }

  watch(
    () => [resolveSource(hostIdSource), Boolean(resolveSource(enabledSource)),],
    ([hostId, enabled,]) => {
      if (activeEntry.value?.hostId === hostId && enabled) return
      releaseActiveEntry()
      if (enabled && hostId) activeEntry.value = acquireStatusEntry(hostId)
    },
    { immediate: true }
  )

  onScopeDispose(releaseActiveEntry)

  const serverData = computed(() => activeEntry.value?.serverData.value || createEmptyServerStatus())
  const connectionState = computed(() => activeEntry.value?.connectionState.value || 'idle')
  const isReconnecting = computed(() => activeEntry.value?.isReconnecting.value === true)
  const localToServiceMs = computed(() => activeEntry.value?.localToServiceMs.value ?? null)
  const localToServiceAvailable = computed(() => activeEntry.value?.localToServiceAvailable.value === true)
  const serviceToInstanceMs = computed(() => {
    if (connectionState.value !== 'connected') return null
    const value = Number(serverData.value.latency?.serviceToInstanceMs)
    return serverData.value.latency?.serviceToInstanceAvailable && Number.isFinite(value) ? value : null
  })
  const estimatedTotalMs = computed(() => {
    if (!localToServiceAvailable.value || serviceToInstanceMs.value === null) return null
    return Number((localToServiceMs.value + serviceToInstanceMs.value).toFixed(0))
  })

  return {
    serverData,
    connectionState,
    isReconnecting,
    localToServiceMs,
    localToServiceAvailable,
    serviceToInstanceMs,
    estimatedTotalMs,
    reconnect: () => activeEntry.value?.reconnect() || false
  }
}
