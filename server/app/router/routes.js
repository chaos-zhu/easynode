import { getSSHList, addSSH, updateSSH, removeSSH, getCommand, decryptPrivateKey, getRdpToken } from '../controller/ssh.js'
import { getSftpFavorites } from '../controller/sftp.js'
import { addHost, updateHost, batchUpdateHost, removeHost, importHost, updateLastConnectTime } from '../controller/host.js'
import { login, getpublicKey, updatePwd, getEasynodeVersion, getMFA2Status, getMFA2Code, enableMFA2, disableMFA2, getPlusInfo, getPlusDiscount, getPlusConf, updatePlusKey, getPlusDevices, releasePlusDevice } from '../controller/user.js'
import { getNotifyConfig, updateNotifyConfig, getNotifyList, updateNotifyList } from '../controller/notify.js'
import { addGroupList, updateGroupList, removeGroup } from '../controller/group.js'
import { getLocalScriptList, addScript, updateScriptList, removeScript, batchRemoveScript, importScript } from '../controller/scripts.js'
import { addScriptGroup, removeScriptGroup, updateScriptGroup } from '../controller/script-group.js'
import { getHostCatalog, getScriptCatalog, putHostOrder, putScriptOrder } from '../controller/catalog.js'
import { getOnekeyRecord, removeOnekeyRecord } from '../controller/onekey.js'
import { getLog, revokeAllLoginSessions, revokeLoginSid } from '../controller/sessionLog.js'
import { getIpAccessRules, rejectLegacyIpAccessApi, saveIpAccessRules } from '../controller/ipAccess.js'
import { getAIConfig, saveAIConfig, getAIModels, updateAIPreferences } from '../controller/chat.js'
import { getAgentSessions, getAgentSessionDetail, updateAgentSession, forkAgentSession, removeAgentSession, clearAgentSessions, editAgentSessionMessage } from '../controller/agent-session.js'
import { getAgentMcpServers, addAgentMcpServer, editAgentMcpServer, removeAgentMcpServer, testAgentMcpConnection, discoverAgentMcpServer } from '../controller/agent-mcp.js'
import { getProxyList, addProxy, updateProxy, removeProxy } from '../controller/proxy.js'
import { getServerListConfig, saveServerListConfig } from '../controller/server-list-config.js'
import { getSuspendedSessions, getTerminalSessionConfig, updateTerminalSessionConfig } from '../controller/terminal.js'
import { getNativeSshConnection } from '../controller/native.js'
import {
  addScheduledTask,
  clearScheduledTaskRunsController,
  editScheduledTask,
  getScheduledTaskDetail,
  getScheduledTaskRunDetail,
  getScheduledTaskRuns,
  getScheduledTasks,
  removeScheduledTask,
  runScheduledTaskNow,
  stopScheduledTaskRunController
} from '../controller/scheduled-task.js'
import terminalSettingsRoutes from './modules/terminal-settings.js'

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
    path: '/host-catalog',
    controller: getHostCatalog
  },
  {
    method: 'put',
    path: '/host-order',
    controller: putHostOrder
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
    path: '/script-catalog',
    controller: getScriptCatalog
  },
  {
    method: 'put',
    path: '/script-order',
    controller: putScriptOrder
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
    method: 'delete',
    path: '/revoke-all-sessions',
    controller: revokeAllLoginSessions
  },
  {
    method: 'delete',
    path: '/revoke-login/:id',
    controller: revokeLoginSid
  }
]

const ipAccess = [
  {
    method: 'get',
    path: '/ip-access-rules',
    controller: getIpAccessRules
  },
  {
    method: 'post',
    path: '/ip-access-rules',
    controller: saveIpAccessRules
  },
  {
    method: 'post',
    path: '/ip-white-list',
    controller: rejectLegacyIpAccessApi
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
    method: 'patch',
    path: '/ai-config/preferences',
    controller: updateAIPreferences
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

const agentMcp = [
  {
    method: 'get',
    path: '/agent/mcp-servers',
    controller: getAgentMcpServers
  },
  {
    method: 'post',
    path: '/agent/mcp-servers',
    controller: addAgentMcpServer
  },
  {
    method: 'post',
    path: '/agent/mcp-servers/test-connection',
    controller: testAgentMcpConnection
  },
  {
    method: 'put',
    path: '/agent/mcp-servers/:id',
    controller: editAgentMcpServer
  },
  {
    method: 'delete',
    path: '/agent/mcp-servers/:id',
    controller: removeAgentMcpServer
  },
  {
    method: 'post',
    path: '/agent/mcp-servers/:id/discover',
    controller: discoverAgentMcpServer
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

const scheduledTasks = [
  { method: 'get', path: '/scheduled-tasks', controller: getScheduledTasks },
  { method: 'post', path: '/scheduled-tasks', controller: addScheduledTask },
  { method: 'get', path: '/scheduled-tasks/:id', controller: getScheduledTaskDetail },
  { method: 'put', path: '/scheduled-tasks/:id', controller: editScheduledTask },
  { method: 'delete', path: '/scheduled-tasks/:id', controller: removeScheduledTask },
  { method: 'post', path: '/scheduled-tasks/:id/run', controller: runScheduledTaskNow },
  { method: 'get', path: '/scheduled-task-runs', controller: getScheduledTaskRuns },
  { method: 'delete', path: '/scheduled-task-runs', controller: clearScheduledTaskRunsController },
  { method: 'get', path: '/scheduled-task-runs/:id', controller: getScheduledTaskRunDetail },
  { method: 'post', path: '/scheduled-task-runs/:id/stop', controller: stopScheduledTaskRunController }
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
  ipAccess,
  aiConfig,
  agentMcp,
  proxy,
  terminalSettingsRoutes,
  serverListConfig,
  terminal,
  scheduledTasks,
  native,
  sftp
)
