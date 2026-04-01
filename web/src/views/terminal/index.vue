<template>
  <div class="terminal_container">
    <div v-if="showLinkTips" class="terminal_link_tips">
      <div class="link_tables_wrapper">
        <div class="table_section">
          <h2 class="quick_link_text">{{ t('terminal.recentConnections') }}</h2>
          <el-table :data="displayHostList" :show-header="false">
            <template #empty>
              <span class="link" @click="handleToServer">{{ t('terminal.goConnect') }}</span>
            </template>
            <el-table-column prop="name" label="name" />
            <el-table-column width="220">
              <template #default="{ row }">
                <span @click="handleCopy(row.host)">
                  {{
                    row.username ? `ssh ${row.username}@` : '' }}{{ row.host }}{{ row.port ? ` -p ${row.port}` : ''
                  }}
                </span>
              </template>
            </el-table-column>
            <el-table-column prop="lastTime" label="lastTime" />
            <el-table-column fixed="right" width="80px">
              <template #default="{ row }">
                <div class="actios_btns">
                  <el-button
                    v-if="row.isConfig"
                    type="primary"
                    link
                    @click="linkTerminal(row)"
                  >
                    {{ t('common.connect') }}
                  </el-button>
                  <el-button
                    v-else
                    type="primary"
                    link
                    @click="handleUpdateHost(row)"
                  >
                    {{ t('terminal.configureSsh') }}
                  </el-button>
                </div>
              </template>
            </el-table-column>
          </el-table>
        </div>

        <div class="table_section">
          <h2 class="quick_link_text">
            <span>{{ t('terminal.suspendedSessions') }}</span>
            <el-icon
              class="session_setting_icon"
              :title="t('terminal.sessionSettings')"
              @click="showSessionSetting = true"
            >
              <Setting />
            </el-icon>
            <el-button
              v-if="suspendedSessions.length > 0"
              class="resume_btn"
              size="small"
              type="primary"
              @click="handleResumeAll"
            >
              {{ t('terminal.resumeAll') }}
            </el-button>
          </h2>
          <el-table v-loading="loadingSessions" :data="suspendedSessions" :show-header="false">
            <template #empty>
              <span>{{ t('terminal.noSuspendedSessions') }}</span>
            </template>
            <el-table-column prop="hostName" :label="t('common.hostName')" />
            <el-table-column :label="t('common.status')">
              <template #default="{ row }">
                <el-tag v-if="!row.connectionAlive" type="danger" size="small">{{ t('common.disconnected') }}</el-tag>
                <el-tag v-else type="success" size="small">{{ t('common.active') }}</el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="suspendTime" :label="t('terminal.suspendTime')" />
            <el-table-column fixed="right" width="80px">
              <template #default="{ row }">
                <div class="actios_btns">
                  <el-button
                    type="primary"
                    link
                    :disabled="!row.connectionAlive"
                    @click="handleResumeSession(row)"
                  >
                    {{ t('common.resume') }}
                  </el-button>
                </div>
              </template>
            </el-table-column>
          </el-table>
        </div>
      </div>
    </div>
    <div v-else>
      <TerminalWrapper
        :terminal-tabs="terminalTabs"
        @remove-tab="handleRemoveTab"
        @add-host="linkTerminal"
        @close-all-tab="handleRemoveAllTab"
      />
    </div>
    <HostForm
      v-model:show="hostFormVisible"
      :default-data="updateHostData"
      @update-list="handleUpdateList"
      @closed="updateHostData = null"
    />
    <TerminalSessionSetting v-model:show="showSessionSetting" />
  </div>
</template>

<script setup>
import { ref, computed, onActivated, getCurrentInstance, reactive, nextTick, onMounted, onUnmounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import dayjs from 'dayjs'
import { Setting } from '@element-plus/icons-vue'
import TerminalWrapper from './components/terminal-wrapper.vue'
import HostForm from '../server/components/host-form.vue'
import TerminalSessionSetting from './components/terminal-session-setting.vue'
import { randomStr } from '@utils/index.js'
import { terminalStatus } from '@/utils/enum'
import clipboard from '@/utils/clipboard'
const { CONNECTING, RESUMING } = terminalStatus

const { proxy: { $store, $message, $api } } = getCurrentInstance()
const router = useRouter()
const route = useRoute()
const { t } = useI18n()

let terminalTabs = reactive([])
let hostFormVisible = ref(false)
let updateHostData = ref(null)
let loadingSessions = ref(false)
let suspendedSessions = computed(() => $store.suspendedSessions)
let showSessionSetting = ref(false)

let showLinkTips = computed(() => !Boolean(terminalTabs.length))
let hostList = computed(() => $store.hostList)

const displayHostList = computed(() => {
  return hostList.value
    .filter(item => item.lastConnectTime)
    .map(item => ({
      ...item,
      lastTime: item.lastConnectTime ? dayjs(item.lastConnectTime).format('YYYY-MM-DD HH:mm:ss') : ''
    }))
    .sort((a, b) => {
      const aTime = a.lastConnectTime || 0
      const bTime = b.lastConnectTime || 0
      return bTime - aTime
    })
})

let refreshHostListTimer = null

function debouncedRefreshHostList() {
  if (refreshHostListTimer) {
    clearTimeout(refreshHostListTimer)
  }
  refreshHostListTimer = setTimeout(async () => {
    try {
      await $store.getHostList()
    } catch (error) {
      console.error('Failed to refresh instance list:', error)
    }
  }, 500)
}

async function updateRecentHostList(targetHost) {
  if (!targetHost) return
  try {
    await $api.updateLastConnectTime({ id: targetHost.id })
    debouncedRefreshHostList()
  } catch (error) {
    console.error('Failed to update recent connection time:', error)
  }
}

function linkTerminal(hostInfo) {
  let targetHost = hostList.value.find(item => item.id === hostInfo.id)
  const { id, host, name, isConfig } = targetHost
  terminalTabs.push({ key: randomStr(16), id, name, host, status: CONNECTING, isConfig })
  updateRecentHostList(targetHost)
}

function handleUpdateHost(row) {
  hostFormVisible.value = true
  updateHostData.value = { ...row }
}

function handleRemoveTab(index) {
  terminalTabs.splice(index, 1)
}

function handleRemoveAllTab() {
  terminalTabs.length = []
}

const handleUpdateList = async ({ host }) => {
  try {
    await $store.getHostList()
    let targetHost = hostList.value.find(item => item.host === host)
    if (targetHost) linkTerminal(targetHost)
  } catch (err) {
    $message.error(t('common.fetchServerListFailed'))
    console.error('Failed to fetch instance list:', err)
  }
}

const handleToServer = () => {
  router.push({ path: '/server' })
}

onActivated(async () => {
  await nextTick()
  const { hostIds } = route.query
  if (!hostIds) return
  let targetHosts = hostList.value.filter(item => hostIds.includes(item.id)).map(item => {
    const { id, name, host, isConfig } = item
    return { key: randomStr(16), id, name, host, status: CONNECTING, isConfig }
  })
  if (!targetHosts || !targetHosts.length) return
  terminalTabs.push(...targetHosts)
  targetHosts.forEach(item => {
    const targetHost = hostList.value.find(h => h.id === item.id)
    if (targetHost) {
      updateRecentHostList(targetHost)
    }
  })
})

const handleCopy = (host) => {
  clipboard.copy(host)
}

const fetchSuspendedSessions = async () => {
  loadingSessions.value = true
  try {
    await $store.getSuspendedSessions()
  } catch (error) {
    console.error('Failed to fetch suspended sessions:', error)
    $message.error(t('terminal.noSuspendedSessions'))
  } finally {
    loadingSessions.value = false
  }
}

const handleResumeSession = (session) => {
  if (!session.connectionAlive) {
    $message.warning(t('terminal.sessionSshDisconnected'))
    return
  }

  const { hostId, sessionId } = session

  const targetHost = hostList.value.find(item => item.id === hostId)
  if (!targetHost) {
    $message.error(t('terminal.hostConfigNotFound'))
    return
  }

  const { id, name, host, isConfig } = targetHost

  terminalTabs.push({
    key: sessionId,
    id,
    name,
    host,
    status: RESUMING,
    isConfig,
    resumeSessionId: sessionId
  })
}

const handleResumeAll = () => {
  const sessionsToRestore = [...suspendedSessions.value].filter(s => s.connectionAlive)

  if (sessionsToRestore.length === 0) {
    $message.warning(t('terminal.noRestorableSessions'))
    return
  }

  sessionsToRestore.forEach(session => {
    handleResumeSession(session)
  })

  $message.success(t('terminal.restoringSessions', { count: sessionsToRestore.length }))
}

watch(showLinkTips, (newValue) => {
  if (newValue) {
    fetchSuspendedSessions()
  }
})

onMounted(() => {
  fetchSuspendedSessions()
})

onUnmounted(() => {
  if (refreshHostListTimer) {
    clearTimeout(refreshHostListTimer)
    refreshHostListTimer = null
  }
})
</script>

<style lang="scss" scoped>
.terminal_container {
  height: calc(100% - 60px - 20px);
  overflow: auto;
  .terminal_link_tips {
    width: 100%;
    max-width: 1500px;
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    padding: 20px;

    .link_tables_wrapper {
      width: 100%;
      display: flex;
      flex-wrap: wrap;
      gap: 40px;
      justify-content: center;
      align-items: flex-start;

      .table_section {
        flex: 1;
        min-width: 500px;
        max-width: 750px;
        display: flex;
        flex-direction: column;

        @media (max-width: 768px) {
          min-width: 100%;
          max-width: 100%;
        }
      }
    }

    .quick_link_text {
      align-self: stretch;
      margin: 0 10px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
      margin-bottom: 15px;
      display: flex;
      align-items: center;
      gap: 10px;

      .session_setting_icon {
        cursor: pointer;
        font-size: 16px;
        color: var(--el-text-color-secondary);
        transition: all 0.3s;

        &:hover {
          color: var(--el-color-primary);
          transform: rotate(90deg);
        }
      }

      .resume_btn {
        margin-left: auto;
      }
    }

    .actios_btns {
      display: flex;
      justify-content: flex-end;
    }
  }
  ::v-deep(.el-table__empty-text) {
    width: 100%;
  }
}
</style>
