const { getSSHList, addSSH, updateSSH, removeSSH, getCommand, decryptPrivateKey } = require('../controller/ssh')
const { getHostList, addHost, updateHost, batchUpdateHost, removeHost, importHost } = require('../controller/host')
const { login, getpublicKey, updatePwd, getEasynodeVersion, getMFA2Status, getMFA2Code, enableMFA2, disableMFA2, getPlusInfo, getPlusDiscount, getPlusConf, updatePlusKey } = require('../controller/user')
const { getNotifyConfig, updateNotifyConfig, getNotifyList, updateNotifyList } = require('../controller/notify')
const { getGroupList, addGroupList, updateGroupList, removeGroup } = require('../controller/group')
const { getScriptList, getLocalScriptList, addScript, updateScriptList, removeScript, batchRemoveScript, importScript } = require('../controller/scripts')
const { getScriptGroupList, addScriptGroup, removeScriptGroup, updateScriptGroup } = require('../controller/script-group')
const { getOnekeyRecord, removeOnekeyRecord } = require('../controller/onekey')
const { getLog, saveIpWhiteList, removeSomeLoginRecords } = require('../controller/log')
const { getAIConfig, saveAIConfig, getAIModels, getChatHistory, saveChatHistory, removeChatHistory } = require('../controller/chat')
const { getProxyList, addProxy, updateProxy, removeProxy } = require('../controller/proxy')

const ssh = [
  {
    method: 'get',
    path: '/get-ssh-list',
    controller: getSSHList
  },
  {
    method: 'post',
    path: '/add-ssh',
    controller: addSSH
  },
  {
    method: 'post',
    path: '/update-ssh',
    controller: updateSSH
  },
  {
    method: 'delete',
    path: '/remove-ssh/:id',
    controller: removeSSH
  },
  {
    method: 'get',
    path: '/command',
    controller: getCommand
  },
  {
    method: 'post',
    path: '/decrypt-private-key',
    controller: decryptPrivateKey
  }
]
const host = [
  {
    method: 'get',
    path: '/host-list',
    controller: getHostList
  },
  {
    method: 'post',
    path: '/host-save',
    controller: addHost
  },
  {
    method: 'put',
    path: '/host-save',
    controller: updateHost
  },
  {
    method: 'put',
    path: '/batch-update-host',
    controller: batchUpdateHost
  },
  {
    method: 'post',
    path: '/host-remove',
    controller: removeHost
  },
  {
    method: 'post',
    path: '/import-host',
    controller: importHost
  }
]
const user = [
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
    path: '/version',
    controller: getEasynodeVersion
  },
  {
    method: 'get',
    path: '/mfa2-status',
    controller: getMFA2Status
  },
  {
    method: 'post',
    path: '/mfa2-code',
    controller: getMFA2Code
  },
  {
    method: 'post',
    path: '/mfa2-enable',
    controller: enableMFA2
  },
  {
    method: 'post',
    path: '/mfa2-disable',
    controller: disableMFA2
  },
  {
    method: 'get',
    path: '/plus-info',
    controller: getPlusInfo
  },
  {
    method: 'get',
    path: '/plus-discount',
    controller: getPlusDiscount
  },
  {
    method: 'get',
    path: '/plus-conf',
    controller: getPlusConf
  },
  {
    method: 'post',
    path: '/plus-conf',
    controller: updatePlusKey
  }
]
const notify = [
  {
    method: 'get',
    path: '/notify-config',
    controller: getNotifyConfig
  },
  {
    method: 'put',
    path: '/notify-config',
    controller: updateNotifyConfig
  },
  {
    method: 'get',
    path: '/notify',
    controller: getNotifyList
  },
  {
    method: 'put',
    path: '/notify',
    controller: updateNotifyList
  }
]

const group = [
  {
    method: 'get',
    path: '/group',
    controller: getGroupList
  },
  {
    method: 'post',
    path: '/group',
    controller: addGroupList
  },
  {
    method: 'delete',
    path: '/group/:id',
    controller: removeGroup
  },
  {
    method: 'put',
    path: '/group/:id',
    controller: updateGroupList
  }
]

const scripts = [
  {
    method: 'get',
    path: '/script',
    controller: getScriptList
  },
  {
    method: 'get',
    path: '/local-script',
    controller: getLocalScriptList
  },
  {
    method: 'post',
    path: '/script',
    controller: addScript
  },
  {
    method: 'delete',
    path: '/script/:id',
    controller: removeScript
  },
  {
    method: 'post',
    path: '/batch-remove-script',
    controller: batchRemoveScript
  },
  {
    method: 'put',
    path: '/script/:id',
    controller: updateScriptList
  },
  {
    method: 'post',
    path: '/import-script',
    controller: importScript
  }
]

const scriptGroup = [
  {
    method: 'get',
    path: '/script-group',
    controller: getScriptGroupList
  },
  {
    method: 'post',
    path: '/script-group',
    controller: addScriptGroup
  },
  {
    method: 'delete',
    path: '/script-group/:id',
    controller: removeScriptGroup
  },
  {
    method: 'put',
    path: '/script-group/:id',
    controller: updateScriptGroup
  }
]

const onekey = [
  {
    method: 'get',
    path: '/onekey',
    controller: getOnekeyRecord
  },
  {
    method: 'post',
    path: '/onekey',
    controller: removeOnekeyRecord
  }
]

const log = [
  {
    method: 'get',
    path: '/log',
    controller: getLog
  },
  {
    method: 'post',
    path: '/ip-white-list',
    controller: saveIpWhiteList
  },
  {
    method: 'delete',
    path: '/remove-some-login-records',
    controller: removeSomeLoginRecords
  }
]

const aiConfig = [
  {
    method: 'get',
    path: '/ai-config',
    controller: getAIConfig
  },
  {
    method: 'post',
    path: '/ai-config',
    controller: saveAIConfig
  },
  {
    method: 'post',
    path: '/ai-models',
    controller: getAIModels
  },
  {
    method: 'get',
    path: '/chat-history',
    controller: getChatHistory
  },
  {
    method: 'post',
    path: '/chat-history',
    controller: saveChatHistory
  },
  {
    method: 'delete',
    path: '/chat-history/:id',
    controller: removeChatHistory
  }
]

const proxy = [
  {
    method: 'get',
    path: '/proxy',
    controller: getProxyList
  },
  {
    method: 'post',
    path: '/proxy',
    controller: addProxy
  },
  {
    method: 'put',
    path: '/proxy/:id',
    controller: updateProxy
  },
  {
    method: 'delete',
    path: '/proxy/:id',
    controller: removeProxy
  }
]

module.exports = [].concat(
  ssh,
  host,
  user,
  notify,
  group,
  scripts,
  scriptGroup,
  onekey,
  log,
  aiConfig,
  proxy
)
