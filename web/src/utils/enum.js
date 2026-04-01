import i18n from '@/i18n'

const t = i18n.global.t

export const terminalStatus = {
  CONNECT_READY: 'connect_ready',
  CONNECTING: 'connecting',
  CONNECT_FAIL: 'connect_fail',
  CONNECT_SUCCESS: 'connect_success',
  SUSPENDED: 'suspended', // 新增：已挂起
  RESUMING: 'resuming' // 新增：恢复中
}

export const terminalStatusList = [
  { value: terminalStatus.CONNECT_READY, label: t('enum.terminalStatus.ready'), color: 'gray' },
  { value: terminalStatus.CONNECTING, label: t('enum.terminalStatus.connecting'), color: '#FFA500' },
  { value: terminalStatus.CONNECT_FAIL, label: t('enum.terminalStatus.connectFailed'), color: '#DC3545' },
  { value: terminalStatus.CONNECT_SUCCESS, label: t('enum.terminalStatus.connected'), color: '#28A745' },
  { value: terminalStatus.SUSPENDED, label: t('enum.terminalStatus.suspended'), color: '#909399' },
  { value: terminalStatus.RESUMING, label: t('enum.terminalStatus.resuming'), color: '#409EFF' },
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
  { value: rdpStatus.IDLE, label: t('enum.rdpStatus.idle'), color: '#909399' },
  { value: rdpStatus.CONNECTING, label: t('enum.rdpStatus.connecting'), color: '#E6A23C' },
  { value: rdpStatus.WAITING, label: t('enum.rdpStatus.waiting'), color: '#409EFF' },
  { value: rdpStatus.CONNECTED, label: t('enum.rdpStatus.connected'), color: '#67C23A' },
  { value: rdpStatus.DISCONNECTING, label: t('enum.rdpStatus.disconnecting'), color: '#E6A23C' },
  { value: rdpStatus.DISCONNECTED, label: t('enum.rdpStatus.disconnected'), color: '#909399' },
  { value: rdpStatus.TIMEOUT, label: t('enum.rdpStatus.timeout'), color: '#F56C6C' },
  { value: rdpStatus.ERROR, label: t('enum.rdpStatus.error'), color: '#F56C6C' },
]

export const virtualKeyType = {
  LONG_PRESS: 'long-press',
  SINGLE_PRESS: 'single-press'
}
