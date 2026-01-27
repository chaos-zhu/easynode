// 终端连接状态
export const terminalStatus = {
  CONNECT_READY: 'connect_ready',
  CONNECTING: 'connecting',
  CONNECT_FAIL: 'connect_fail',
  CONNECT_SUCCESS: 'connect_success',
  SUSPENDED: 'suspended', // 新增：已挂起
  RESUMING: 'resuming' // 新增：恢复中
}

export const terminalStatusList = [
  { value: terminalStatus.CONNECT_READY, label: '待连接', color: 'gray' },
  { value: terminalStatus.CONNECTING, label: '连接中', color: '#FFA500' },
  { value: terminalStatus.CONNECT_FAIL, label: '连接失败', color: '#DC3545' },
  { value: terminalStatus.CONNECT_SUCCESS, label: '已连接', color: '#28A745' },
  { value: terminalStatus.SUSPENDED, label: '已挂起', color: '#909399' }, // 新增
  { value: terminalStatus.RESUMING, label: '恢复中', color: '#409EFF' }, // 新增
]

// RDP连接状态
export const rdpStatus = {
  IDLE: 'idle',
  CONNECTING: 'connecting',
  WAITING: 'waiting',
  CONNECTED: 'connected',
  DISCONNECTING: 'disconnecting',
  DISCONNECTED: 'disconnected',
  TIMEOUT: 'timeout',
  ERROR: 'error'
}

export const rdpStatusList = [
  { value: rdpStatus.IDLE, label: '准备连接', color: '#909399' },
  { value: rdpStatus.CONNECTING, label: '正在连接...', color: '#E6A23C' },
  { value: rdpStatus.WAITING, label: '等待响应...', color: '#409EFF' },
  { value: rdpStatus.CONNECTED, label: '已连接', color: '#67C23A' },
  { value: rdpStatus.DISCONNECTING, label: '正在断开...', color: '#E6A23C' },
  { value: rdpStatus.DISCONNECTED, label: '已断开', color: '#909399' },
  { value: rdpStatus.TIMEOUT, label: '连接超时', color: '#F56C6C' },
  { value: rdpStatus.ERROR, label: '连接错误', color: '#F56C6C' },
]

export const virtualKeyType = {
  LONG_PRESS: 'long-press',
  SINGLE_PRESS: 'single-press'
}
