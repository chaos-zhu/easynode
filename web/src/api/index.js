import axios from '@/utils/axios'

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
  // existSSH(host) {
  //   return axios({ url: '/exist-ssh', method: 'post', data: { host } })
  // },
  getCommand(host) {
    return axios({ url: '/command', method: 'get', params: { host } })
  },
  getHostList() {
    return axios({ url: '/host-list', method: 'get' })
  },
  addHost(data) {
    return axios({ url: '/host-save', method: 'post', data })
  },
  updateHost(data) {
    return axios({ url: '/host-save', method: 'put', data })
  },
  removeHost(data) {
    return axios({ url: '/host-remove', method: 'post', data })
  },
  importHost(data) {
    return axios({ url: '/import-host', method: 'post', data })
  },
  getPubPem() {
    return axios({ url: '/get-pub-pem', method: 'get' })
  },
  login(data) {
    return axios({ url: '/login', method: 'post', data })
  },
  getLoginRecord() {
    return axios({ url: '/get-login-record', method: 'get' })
  },
  updatePwd(data) {
    return axios({ url: '/pwd', method: 'put', data })
  },
  // updateHostSort(data) {
  //   return axios({ url: '/host-sort', method: 'put', data })
  // },
  getUserEmailList() {
    return axios({ url: '/user-email', method: 'get' })
  },
  getSupportEmailList() {
    return axios({ url: '/support-email', method: 'get' })
  },
  updateUserEmailList(data) {
    return axios({ url: '/user-email', method: 'post', data })
  },
  deleteUserEmail(email) {
    return axios({ url: `/user-email/${ email }`, method: 'delete' })
  },
  pushTestEmail(data) {
    return axios({ url: '/push-email', method: 'post', data })
  },
  getNotifyList() {
    return axios({ url: '/notify', method: 'get' })
  },
  updateNotifyList(data) {
    return axios({ url: '/notify', method: 'put', data })
  },
  getGroupList() {
    return axios({ url: '/group', method: 'get' })
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
  getScriptList() {
    return axios({ url: '/script', method: 'get' })
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
  getOnekeyRecord() {
    return axios({ url: '/onekey', method: 'get' })
  },
  deleteOnekeyRecord(ids) {
    return axios({ url: '/onekey', method: 'post', data: { ids } })
  },
  getEasynodeVersion() {
    return axios({ url: '/version', method: 'get' })
  }
}
