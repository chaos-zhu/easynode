const { updateSSH, removeSSH, existSSH, getCommand } = require('../controller/ssh-info')
const { getHostList, saveHost, updateHost, removeHost, updateHostSort } = require('../controller/host-info')
const { login, getpublicKey, updatePwd, getLoginRecord } = require('../controller/user')

// 路由统一管理
const routes = [
  {
    method: 'post',
    path: '/update-ssh',
    controller: updateSSH
  },
  {
    method: 'post',
    path: '/remove-ssh',
    controller: removeSSH
  },
  {
    method: 'post',
    path: '/exist-ssh',
    controller: existSSH
  },
  {
    method: 'get',
    path: '/command',
    controller: getCommand
  },
  {
    method: 'get',
    path: '/host-list',
    controller: getHostList
  },
  {
    method: 'post',
    path: '/host-save',
    controller: saveHost
  },
  {
    method: 'put',
    path: '/host-save',
    controller: updateHost
  },
  {
    method: 'post',
    path: '/host-remove',
    controller: removeHost
  },
  {
    method: 'put',
    path: '/host-sort',
    controller: updateHostSort
  },
  {
    method: 'get',
    path: '/get-pub-pem',
    controller: getpublicKey
  },
  {
    method: 'post',
    path: '/login',
    controller: login
  },
  {
    method: 'put',
    path: '/pwd',
    controller: updatePwd
  },
  {
    method: 'get',
    path: '/get-login-record',
    controller: getLoginRecord
  }
]

module.exports = routes
