import axios from '@/utils/axios'

const MCP_DISCOVERY_REQUEST_TIMEOUT = 605 * 1000

export default {
  getOsInfo (params = {}) {
    return axios({ url: '/monitor', method: 'get', params })
  },
  getIpInfo (params = {}) {
    return axios({ url: '/ip-info', method: 'get', params })
  },
  getSSHList(params = {}) {
    return axios({ url: '/get-ssh-list', method: 'get', params })
  },
  addSSH(data) {
    return axios({ url: '/add-ssh', method: 'post', data })
  },
  updateSSH(data) {
    return axios({ url: '/update-ssh', method: 'post', data })
  },
  removeSSH(id) {
    return axios({ url: `/remove-ssh/${ id }`, method: 'delete' })
  },
  getRdpToken(config = {}) {
    return axios({ url: '/get-rdp-token', method: 'get', params: config })
  },
  getPlusInfo() {
    return axios({ url: '/plus-info', method: 'get' })
  },
  getPlusDiscount() {
    return axios({ url: '/plus-discount', method: 'get' })
  },
  getPlusDevices() {
    return axios({ url: '/plus-devices', method: 'get' })
  },
  releasePlusDevice(data) {
    return axios({ url: '/plus-release', method: 'post', data })
  },
  getCommand(hostId) {
    return axios({ url: '/command', method: 'get', params: { hostId } })
  },
  decryptPrivateKey(data) {
    return axios({ url: '/decrypt-private-key', method: 'post', data })
  },
  getHostCatalog() {
    return axios({ url: '/host-catalog', method: 'get' })
  },
  updateHostOrder(data) {
    return axios({ url: '/host-order', method: 'put', data, skipErrorMessage: true })
  },
  addHost(data) {
    return axios({ url: '/host-save', method: 'post', data })
  },
  updateHost(data) {
    return axios({ url: '/host-save', method: 'put', data })
  },
  batchUpdateHost(data) {
    return axios({ url: '/batch-update-host', method: 'put', data })
  },
  removeHost(data) {
    return axios({ url: '/host-remove', method: 'post', data })
  },
  importHost(data) {
    return axios({ url: '/import-host', method: 'post', data })
  },
  updateLastConnectTime(data) {
    return axios({ url: '/host-last-connect', method: 'post', data })
  },
  getPubPem() {
    return axios({ url: '/get-pub-pem', method: 'get' })
  },
  login(data) {
    return axios({ url: '/login', method: 'post', data })
  },
  getLoginRecord() {
    return axios({ url: '/log', method: 'get' })
  },
  getIpAccessRules() {
    return axios({ url: '/ip-access-rules', method: 'get' })
  },
  saveIpAccessRules(data) {
    return axios({ url: '/ip-access-rules', method: 'post', data })
  },
  updatePwd(data) {
    return axios({ url: '/pwd', method: 'put', data })
  },
  getMFA2QR() {
    return axios({ url: '/mfa2-code', method: 'post' })
  },
  getMFA2Status() {
    return axios({ url: '/mfa2-status', method: 'get' })
  },
  enableMFA2(data) {
    return axios({ url: '/mfa2-enable', method: 'post', data })
  },
  disableMFA2(data) {
    return axios({ url: '/mfa2-disable', method: 'post', data })
  },
  getNotifyConfig() {
    return axios({ url: '/notify-config', method: 'get' })
  },
  updateNotifyConfig(data) {
    return axios({ url: '/notify-config', method: 'put', data })
  },
  getNotifyList() {
    return axios({ url: '/notify', method: 'get' })
  },
  updateNotifyList(data) {
    return axios({ url: '/notify', method: 'put', data })
  },
  addGroup(data) {
    return axios({ url: '/group', method: 'post', data })
  },
  updateGroup(id, data) {
    return axios({ url: `/group/${ id }`, method: 'put', data })
  },
  deleteGroup(id) {
    return axios({ url: `/group/${ id }`, method: 'delete' })
  },
  getScriptCatalog() {
    return axios({ url: '/script-catalog', method: 'get' })
  },
  updateScriptOrder(data) {
    return axios({ url: '/script-order', method: 'put', data, skipErrorMessage: true })
  },
  importScript(data) {
    return axios({ url: '/import-script', method: 'post', data })
  },
  getLocalScriptList() {
    return axios({ url: '/local-script', method: 'get' })
  },
  addScript(data) {
    return axios({ url: '/script', method: 'post', data })
  },
  updateScript(id, data) {
    return axios({ url: `/script/${ id }`, method: 'put', data })
  },
  deleteScript(id) {
    return axios({ url: `/script/${ id }`, method: 'delete' })
  },
  batchRemoveScript(data) {
    return axios({ url: '/batch-remove-script', method: 'post', data })
  },
  addScriptGroup(data) {
    return axios({ url: '/script-group', method: 'post', data })
  },
  updateScriptGroup(id, data) {
    return axios({ url: `/script-group/${ id }`, method: 'put', data })
  },
  deleteScriptGroup(id) {
    return axios({ url: `/script-group/${ id }`, method: 'delete' })
  },
  getOnekeyRecord() {
    return axios({ url: '/onekey', method: 'get' })
  },
  deleteOnekeyRecord(ids) {
    return axios({ url: '/onekey', method: 'post', data: { ids } })
  },
  getEasynodeVersion() {
    return axios({ url: '/version', method: 'get' })
  },
  getPlusConf() {
    return axios({ url: '/plus-conf', method: 'get' })
  },
  updatePlusKey(data) {
    return axios({ url: '/plus-conf', method: 'post', data })
  },
  getAIConfig() {
    return axios({ url: '/ai-config', method: 'get' })
  },
  saveAIConfig(data) {
    return axios({ url: '/ai-config', method: 'post', data })
  },
  updateAIPreferences(data) {
    return axios({ url: '/ai-config/preferences', method: 'patch', data })
  },
  getAIModels(data) {
    return axios({ url: '/ai-models', method: 'post', data, skipErrorMessage: true })
  },
  getAgentSessions(params) {
    return axios({ url: '/agent-sessions', method: 'get', params })
  },
  getAgentSessionDetail(id) {
    return axios({ url: `/agent-sessions/${ id }`, method: 'get' })
  },
  updateAgentSession(id, data) {
    return axios({ url: `/agent-sessions/${ id }`, method: 'put', data })
  },
  forkAgentSession(id, { turnIndex, messageIndex }) {
    return axios({ url: `/agent-sessions/${ id }/fork`, method: 'post', data: { turnIndex, messageIndex } })
  },
  editAgentSessionMessage(id, { turnIndex, content }) {
    return axios({
      url: `/agent-sessions/${ id }/messages/${ turnIndex }`,
      method: 'put',
      data: { content }
    })
  },
  removeAgentSession(id) {
    return axios({ url: `/agent-sessions/${ id }`, method: 'delete' })
  },
  clearAgentSessions(params) {
    return axios({ url: '/agent-sessions', method: 'delete', params })
  },
  getAgentMcpServers() {
    return axios({ url: '/agent/mcp-servers', method: 'get' })
  },
  addAgentMcpServer(data) {
    return axios({ url: '/agent/mcp-servers', method: 'post', data, timeout: MCP_DISCOVERY_REQUEST_TIMEOUT })
  },
  testAgentMcpConnection(data) {
    return axios({
      url: '/agent/mcp-servers/test-connection',
      method: 'post',
      data,
      timeout: MCP_DISCOVERY_REQUEST_TIMEOUT,
      skipErrorMessage: true
    })
  },
  updateAgentMcpServer(id, data) {
    return axios({ url: `/agent/mcp-servers/${ id }`, method: 'put', data, timeout: MCP_DISCOVERY_REQUEST_TIMEOUT })
  },
  deleteAgentMcpServer(id) {
    return axios({ url: `/agent/mcp-servers/${ id }`, method: 'delete' })
  },
  discoverAgentMcpServer(id) {
    return axios({
      url: `/agent/mcp-servers/${ id }/discover`,
      method: 'post',
      timeout: MCP_DISCOVERY_REQUEST_TIMEOUT,
      skipErrorMessage: true
    })
  },
  revokeAllSessions() {
    return axios({ url: '/revoke-all-sessions', method: 'delete' })
  },
  revokeLoginSid(id) {
    return axios({ url: `/revoke-login/${ id }`, method: 'delete' })
  },
  getProxyList() {
    return axios({ url: '/proxy', method: 'get' })
  },
  addProxy(data) {
    return axios({ url: '/proxy', method: 'post', data })
  },
  updateProxy(id, data) {
    return axios({ url: `/proxy/${ id }`, method: 'put', data })
  },
  removeProxy(id) {
    return axios({ url: `/proxy/${ id }`, method: 'delete' })
  },
  // 终端设置
  getTerminalSettings(params = {}) {
    return axios({ url: '/terminal-settings', method: 'get', params })
  },
  saveTerminalSettings(data) {
    return axios({ url: '/terminal-settings', method: 'put', data })
  },
  uploadTerminalBackground(file) {
    const data = new FormData()
    data.append('file', file)
    return axios({ url: '/terminal-settings/background', method: 'post', data })
  },
  getTerminalBackground(assetId) {
    return axios({ url: `/terminal-settings/background/${ assetId }`, method: 'get', responseType: 'blob' })
  },
  // 服务器列表配置相关API
  getServerListConfig(params = {}) {
    return axios({ url: '/server-list-config', method: 'get', params })
  },
  saveServerListConfig(data) {
    return axios({ url: '/server-list-config', method: 'post', data })
  },
  // 获取挂起的会话列表
  getSuspendedSessions() {
    return axios({ url: '/suspended-sessions', method: 'get' })
  },
  getScheduledTasks(params = {}) {
    return axios({ url: '/scheduled-tasks', method: 'get', params })
  },
  getScheduledTask(id) {
    return axios({ url: `/scheduled-tasks/${ id }`, method: 'get' })
  },
  addScheduledTask(data) {
    return axios({ url: '/scheduled-tasks', method: 'post', data })
  },
  updateScheduledTask(id, data) {
    return axios({ url: `/scheduled-tasks/${ id }`, method: 'put', data })
  },
  removeScheduledTask(id) {
    return axios({ url: `/scheduled-tasks/${ id }`, method: 'delete' })
  },
  runScheduledTask(id) {
    return axios({ url: `/scheduled-tasks/${ id }/run`, method: 'post' })
  },
  getScheduledTaskRuns(params = {}) {
    return axios({ url: '/scheduled-task-runs', method: 'get', params })
  },
  clearScheduledTaskRuns() {
    return axios({ url: '/scheduled-task-runs', method: 'delete' })
  },
  getScheduledTaskRun(id) {
    return axios({ url: `/scheduled-task-runs/${ id }`, method: 'get' })
  },
  stopScheduledTaskRun(id) {
    return axios({ url: `/scheduled-task-runs/${ id }/stop`, method: 'post' })
  },
  // 终端会话设置相关API
  getTerminalSessionConfig() {
    return axios({ url: '/terminal-session-config', method: 'get' })
  },
  updateTerminalSessionConfig(data) {
    return axios({ url: '/terminal-session-config', method: 'post', data })
  }
}
