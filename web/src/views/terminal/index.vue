<template>
  <div class="terminal_container">
    <div v-if="showLinkTips" class="terminal_link_tips">
      <h2 class="quick_link_text">最近连接</h2>
      <el-table :data="displayHostList" :show-header="false">
        <template #empty>
          <span class="link" @click="handleToServer">去连接</span>
        </template>
        <el-table-column prop="name" label="name" />
        <el-table-column>
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
      <span v-show="displayHostList.length" class="link clear_host" @click="handleClearRecentHostList">清空</span>
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
  </div>
</template>

<script setup>
import { ref, computed, onActivated, getCurrentInstance, reactive, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import dayjs from 'dayjs'
import TerminalWrapper from './components/terminal-wrapper.vue'
import HostForm from '../server/components/host-form.vue'
import { randomStr } from '@utils/index.js'
import { terminalStatus } from '@/utils/enum'
const { CONNECTING } = terminalStatus

const { proxy: { $store, $message } } = getCurrentInstance()
const router = useRouter()
const route = useRoute()

let terminalTabs = reactive([])
let hostFormVisible = ref(false)
let updateHostData = ref(null)

let showLinkTips = computed(() => !Boolean(terminalTabs.length))
let hostList = computed(() => $store.hostList)
let recentHostList = ref(JSON.parse(localStorage.getItem('recentHostList')) || [])
const displayHostList = computed(() => {
  return recentHostList.value.filter(item => hostList.value.some(host => host.id === item.id))
})

function updateRecentHostList(targetHost) {
  if (!targetHost) return
  targetHost.lastTime = dayjs().format('YYYY-MM-DD HH:mm:ss')
  if (recentHostList.value.some(item => item.id === targetHost.id)) {
    // 如果在最近列表中存在，则移动到首位
    let index = recentHostList.value.findIndex(item => item.id === targetHost.id)
    recentHostList.value.splice(index, 1)
    recentHostList.value.unshift(targetHost)
  } else {
    // 如果不在最近列表中，则添加到首位
    recentHostList.value.unshift(targetHost)
  }
  recentHostList.value = recentHostList.value.slice(0, 20)
  localStorage.setItem('recentHostList', JSON.stringify(recentHostList.value))
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
  targetHosts.forEach(item => {
    updateRecentHostList(item)
  })
})

const handleCopy = async (host) => {
  await navigator.clipboard.writeText(host)
  $message.success({ message: '复制成功', center: true })
}

const handleClearRecentHostList = () => {
  recentHostList.value = []
  localStorage.removeItem('recentHostList')
}

</script>

<style lang="scss" scoped>
.terminal_container {
  height: calc(100% - 60px - 20px);
  overflow: auto;
  .terminal_link_tips {
    width: 735px;
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    padding: 20px;

    .quick_link_text {
      align-self: self-start;
      margin: 0 10px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
      margin-bottom: 15px;
    }

    .clear_host {
      color: #409EFF;
      cursor: pointer;
      margin-top: 20px;
      font-size: 12px;
      font-weight: 400;
      line-height: 18px;
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
