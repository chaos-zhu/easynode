import { getSSHList, addSSH, updateSSH, removeSSH, getCommand, decryptPrivateKey, getRdpToken } from '../controller/ssh.js'
import { getSftpFavorites } from '../controller/sftp.js'
import { getHostList, addHost, updateHost, batchUpdateHost, removeHost, importHost, updateLastConnectTime } from '../controller/host.js'
import { login, getpublicKey, updatePwd, getEasynodeVersion, getMFA2Status, getMFA2Code, enableMFA2, disableMFA2, getPlusInfo, getPlusDiscount, getPlusConf, updatePlusKey, getPlusDevices, releasePlusDevice } from '../controller/user.js'
import { getNotifyConfig, updateNotifyConfig, getNotifyList, updateNotifyList } from '../controller/notify.js'
import { getGroupList, addGroupList, updateGroupList, removeGroup } from '../controller/group.js'
import { getScriptList, getLocalScriptList, addScript, updateScriptList, removeScript, batchRemoveScript, importScript } from '../controller/scripts.js'
import { getScriptGroupList, addScriptGroup, removeScriptGroup, updateScriptGroup } from '../controller/script-group.js'
import { getOnekeyRecord, removeOnekeyRecord } from '../controller/onekey.js'
import { getLog, saveIpWhiteList, removeSomeLoginRecords, revokeLoginSid } from '../controller/sessionLog.js'
import { getAIConfig, saveAIConfig, getAIModels } from '../controller/chat.js'
import { getAgentSessions, getAgentSessionDetail, updateAgentSession, forkAgentSession, removeAgentSession, clearAgentSessions, editAgentSessionMessage } from '../controller/agent-session.js'
import { getProxyList, addProxy, updateProxy, removeProxy } from '../controller/proxy.js'
import { getTerminalConfig, saveTerminalConfig } from '../controller/terminal-config.js'
import { getServerListConfig, saveServerListConfig } from '../controller/server-list-config.js'
import { getSuspendedSessions, getTerminalSessionConfig, updateTerminalSessionConfig } from '../controller/terminal.js'
import { getNativeSshConnection } from '../controller/native.js'

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
  },
  {
    method: 'get',
    path: '/get-rdp-token',
    controller: getRdpToken
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
  },
  {
    method: 'post',
    path: '/host-last-connect',
    controller: updateLastConnectTime
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
    path: '/plus-devices',
    controller: getPlusDevices
  },
  {
    method: 'post',
    path: '/plus-release',
    controller: releasePlusDevice
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
  },
  {
    method: 'delete',
    path: '/revoke-login/:id',
    controller: revokeLoginSid
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
    path: '/agent-sessions',
    controller: getAgentSessions
  },
  {
    method: 'delete',
    path: '/agent-sessions',
    controller: clearAgentSessions
  },
  {
    method: 'get',
    path: '/agent-sessions/:id',
    controller: getAgentSessionDetail
  },
  {
    method: 'put',
    path: '/agent-sessions/:id',
    controller: updateAgentSession
  },
  {
    method: 'post',
    path: '/agent-sessions/:id/fork',
    controller: forkAgentSession
  },
  {
    method: 'put',
    path: '/agent-sessions/:id/messages/:turnIndex',
    controller: editAgentSessionMessage
  },
  {
    method: 'delete',
    path: '/agent-sessions/:id',
    controller: removeAgentSession
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

const terminalConfig = [
  {
    method: 'get',
    path: '/terminal-config',
    controller: getTerminalConfig
  },
  {
    method: 'post',
    path: '/terminal-config',
    controller: saveTerminalConfig
  }
]

const serverListConfig = [
  {
    method: 'get',
    path: '/server-list-config',
    controller: getServerListConfig
  },
  {
    method: 'post',
    path: '/server-list-config',
    controller: saveServerListConfig
  }
]

const terminal = [
  {
    method: 'get',
    path: '/suspended-sessions',
    controller: getSuspendedSessions
  },
  {
    method: 'get',
    path: '/terminal-session-config',
    controller: getTerminalSessionConfig
  },
  {
    method: 'post',
    path: '/terminal-session-config',
    controller: updateTerminalSessionConfig
  }
]

const native = [
  {
    method: 'post',
    path: '/native/ssh-connection',
    controller: getNativeSshConnection
  }
]

const sftp = [
  {
    method: 'get',
    path: '/sftp/favorites/:hostId',
    controller: getSftpFavorites
  }
]

export default [].concat(
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
  proxy,
  terminalConfig,
  serverListConfig,
  terminal,
  native,
  sftp
)
