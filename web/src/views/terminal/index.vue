<template>
  <div class="terminal_container">
    <div v-if="showLinkTips" class="terminal_link_tips">
      <div class="link_tables_wrapper">
        <div class="table_section">
          <h2 class="quick_link_text">最近连接</h2>
          <el-table :data="displayHostList" :show-header="false">
            <template #empty>
              <span class="link" @click="handleToServer">去连接</span>
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
                    连接
                  </el-button>
                  <el-button
                    v-else
                    type="primary"
                    link
                    @click="handleUpdateHost(row)"
                  >
                    配置ssh
                  </el-button>
                </div>
              </template>
            </el-table-column>
          </el-table>
        </div>

        <div class="table_section">
          <h2 class="quick_link_text">
            <span>挂起会话</span>
            <el-icon
              class="session_setting_icon"
              title="会话设置"
              @click="showSessionSetting = true"
            >
              <Setting />
            </el-icon>
          </h2>
          <el-table v-loading="loadingSessions" :data="suspendedSessions" :show-header="false">
            <template #empty>
              <span>无挂起终端会话</span>
            </template>
            <el-table-column prop="hostName" label="主机名" />
            <el-table-column label="状态">
              <template #default="{ row }">
                <el-tag v-if="!row.connectionAlive" type="danger" size="small">断开</el-tag>
                <el-tag v-else type="success" size="small">活跃</el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="suspendTime" label="挂起时间" />
            <el-table-column fixed="right" width="80px">
              <template #default="{ row }">
                <div class="actios_btns">
                  <el-button
                    type="primary"
                    link
                    :disabled="!row.connectionAlive"
                    @click="handleResumeSession(row)"
                  >
                    恢复
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

let terminalTabs = reactive([])
let hostFormVisible = ref(false)
let updateHostData = ref(null)
let loadingSessions = ref(false)
let suspendedSessions = computed(() => $store.suspendedSessions)
let showSessionSetting = ref(false)

let showLinkTips = computed(() => !Boolean(terminalTabs.length))
let hostList = computed(() => $store.hostList)

// 显示最近连接的主机列表（从后端获取后在前端排序）
const displayHostList = computed(() => {
  return hostList.value
    .filter(item => item.lastConnectTime) // 只显示有连接记录的
    .map(item => ({
      ...item,
      lastTime: item.lastConnectTime ? dayjs(item.lastConnectTime).format('YYYY-MM-DD HH:mm:ss') : ''
    }))
    .sort((a, b) => {
      // 按最近连接时间降序排列
      const aTime = a.lastConnectTime || 0
      const bTime = b.lastConnectTime || 0
      return bTime - aTime
    })
})

// 防抖定时器
let refreshHostListTimer = null

// 防抖刷新hostList（避免批量连接时多次调用）
function debouncedRefreshHostList() {
  if (refreshHostListTimer) {
    clearTimeout(refreshHostListTimer)
  }
  refreshHostListTimer = setTimeout(async () => {
    try {
      await $store.getHostList()
    } catch (error) {
      console.error('刷新实例列表失败:', error)
    }
  }, 500) // 500ms防抖
}

// 更新最近连接时间（调用后端API）
async function updateRecentHostList(targetHost) {
  if (!targetHost) return
  try {
    await $api.updateLastConnectTime({ id: targetHost.id })
    // 防抖刷新本地store中的hostList
    debouncedRefreshHostList()
  } catch (error) {
    console.error('更新最近连接时间失败:', error)
  }
}

function linkTerminal(hostInfo) {
  let targetHost = hostList.value.find(item => item.id === hostInfo.id)
  const { id, host, name, isConfig } = targetHost
  terminalTabs.push({ key: randomStr(16), id, name, host, status: CONNECTING, isConfig })
  // 异步更新最近连接时间
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
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
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
  // 为每个主机更新最近连接时间
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

// 获取挂起的会话列表
const fetchSuspendedSessions = async () => {
  loadingSessions.value = true
  try {
    await $store.getSuspendedSessions()
  } catch (error) {
    console.error('获取挂起会话列表失败:', error)
    $message.error('获取挂起会话列表失败')
  } finally {
    loadingSessions.value = false
  }
}

// 恢复挂起的会话
const handleResumeSession = (session) => {
  if (!session.connectionAlive) {
    $message.warning('该会话的SSH连接已断开，无法恢复')
    return
  }

  const { hostId, sessionId } = session

  // 查找对应的主机配置
  const targetHost = hostList.value.find(item => item.id === hostId)
  if (!targetHost) {
    $message.error('未找到对应的主机配置')
    return
  }

  const { id, name, host, isConfig } = targetHost

  // 创建恢复会话的tab
  terminalTabs.push({
    key: sessionId, // 使用sessionId作为key
    id,
    name,
    host,
    status: RESUMING,
    isConfig,
    resumeSessionId: sessionId // 标记为恢复会话
  })
}

// 监听showLinkTips变化，当返回到初始界面时重新获取挂起会话列表
watch(showLinkTips, (newValue) => {
  if (newValue) {
    // 当showLinkTips变为true时（即关闭所有终端返回到初始界面时），重新获取挂起会话列表
    fetchSuspendedSessions()
  }
})

onMounted(() => {
  // 组件挂载时获取挂起的会话列表
  fetchSuspendedSessions()
})

onUnmounted(() => {
  // 清理防抖定时器
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
      align-self: self-start;
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
