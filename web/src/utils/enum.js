// 终端连接状态
export const terminalStatus = {
  CONNECTING: 'connecting',
  CONNECT_FAIL: 'connect_fail',
  CONNECT_SUCCESS: 'connect_success'
}
export const terminalStatusList = [
  { value: terminalStatus.CONNECTING, label: '连接中', color: '#FFA500' },
  { value: terminalStatus.CONNECT_FAIL, label: '连接失败', color: '#DC3545' },
  { value: terminalStatus.CONNECT_SUCCESS, label: '已连接', color: '#28A745' },
]
export const virtualKeyType = {
  LONG_PRESS: 'long-press',
  SINGLE_PRESS: 'single-press'
}
