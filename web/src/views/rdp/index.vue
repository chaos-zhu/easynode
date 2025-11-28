<template>
  <div class="rdp_container">
    <div class="header">
      <el-dropdown trigger="click">
        <el-button type="primary">
          新建连接<el-icon class="el-icon--right"><ArrowDown /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item v-for="item in rdpHostList" :key="item.id" @click="addRDP(item)">
              {{ item.name }}
            </el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>
    <div v-if="noRDPHost" class="no_rdp_host">
      <el-empty description="无远程桌面连接" />
    </div>
    <div v-else class="rdp_host_list">
      <ul>
        <li v-for="item in rdpTabs" :key="item.id" @click="handleUpdateShow(item)">
          <el-icon><Monitor /></el-icon>
          <span class="hostname">{{ item.name }}</span>
          <span class="status" :style="{ color: getStatusColor(item.status) }">{{ getStatusLabel(item.status) }}</span>
          <el-icon class="close_icon" @click.stop="handleRemoveRdpTab(item)"><Close /></el-icon>
        </li>
      </ul>
      <div class="rdp_host_list_container">
        <Rdp
          v-for="item in rdpTabs"
          :key="item.id+item.name"
          :ref="el => rdpRefs[item.id] = el"
          :host="item"
          @close:dialog="() => item.show = false"
          @status:change="(status) => handleStatusChange(item.id, status)"
          @disconnect="() => handleRemoveRdpTab(item)"
        />
      </div>
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
import { onActivated, computed, nextTick, getCurrentInstance, reactive, ref } from 'vue'
import { useRoute } from 'vue-router'
import { Monitor, Close, ArrowDown } from '@element-plus/icons-vue'
import { rdpStatus, rdpStatusList } from '@/utils/enum'
import Rdp from './components/rdp.vue'
import HostForm from '../server/components/host-form.vue'

const route = useRoute()
const { proxy: { $store, $message } } = getCurrentInstance()

// RDP组件引用
const rdpRefs = ref({})

let rdpTabs = reactive([])
let hostFormVisible = ref(false)
let updateHostData = ref(null)

const hostList = computed(() => $store.hostList)
const noRDPHost = computed(() => !Boolean(rdpTabs.length))
const rdpHostList = computed(() => hostList.value.filter(item => item.connectType === 'rdp'))

const getStatusColor = (status) => {
  return (
    rdpStatusList.find((item) => item.value === status)?.color || 'gray'
  )
}
const getStatusLabel = (status) => {
  return (
    rdpStatusList.find((item) => item.value === status)?.label || '未知状态'
  )
}

onActivated(async () => {
  await nextTick()
  const { hostIds } = route.query
  if (!hostIds) return
  if (rdpTabs.some(item => hostIds.includes(item.id))) return $message.warning('已存在该实例的RDP连接')
  let targetHosts = hostList.value.filter(item => hostIds.includes(item.id)).map(item => {
    const { id, name, host, username } = item
    return { show: true, status: rdpStatus.IDLE, id, name, host, username }
  })
  if (!targetHosts || !targetHosts.length) return
  rdpTabs.push(...targetHosts)
})

const handleUpdateShow = (item) => {
  console.log(item.show)
  item.show = !item.show
}

const handleStatusChange = (hostId, status) => {
  const item = rdpTabs.find(tab => tab.id === hostId)
  if (item) {
    item.status = status
    console.log(`RDP状态更新: ${ item.name } -> ${ status }`)
  }
}

const handleRemoveRdpTab = (item) => {
  const index = rdpTabs.findIndex(tab => tab.id === item.id)
  if (index !== -1) {
    // 尝试断开RDP连接
    const rdpComponent = rdpRefs.value[item.id]
    if (rdpComponent && rdpComponent.disconnectRdp) {
      try {
        rdpComponent.disconnectRdp()
        console.log(`已断开RDP连接: ${ item.name }`)
      } catch (error) {
        console.warn('断开RDP连接时出错:', error)
      }
    }

    // 如果当前标签正在显示，先关闭它
    if (item.show) {
      item.show = false
    }

    // 从数组中移除该标签
    rdpTabs.splice(index, 1)

    // 清理对应的ref引用
    delete rdpRefs.value[item.id]

    console.log(`已移除RDP标签: ${ item.name }`)
  }
}

const addRDP = (item) => {
  const { id, name, host, username, isConfig } = item
  if (!isConfig) return $message.warning('请先配置RDP连接信息')
  if (rdpTabs.some(tab => tab.id === id)) return $message.warning('已存在该实例的RDP连接')
  rdpTabs.push({ show: true, status: rdpStatus.IDLE, id, name, host, username })
}

const handleUpdateList = async ({ host }) => {
  try {
    await $store.getHostList()
    let targetHost = hostList.value.find((item) => item.host === host)
    if (targetHost) addRDP(targetHost)
  } catch (err) {
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
  }
}
</script>

<style lang="scss" scoped>
.rdp_container {
  height: 100%;
  padding: 0 20px 20px 20px;
  .header {
    padding: 15px;
    display: flex;
    align-items: center;
    justify-content: end;
  }
  .no_rdp_host {
    height: 100%;
    display: flex;
    justify-content: center;
    align-items: center;
  }
  .rdp_host_list {
    height: 100%;
    ul {
      height: 100%;
      display: flex;
      gap: 16px;
      li {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 6px;
        height: 150px;
        width: 150px;
        border:1px solid var(--el-color-primary);
        cursor: pointer;
        transition: all 0.2s;
        border-radius: 4px;
        position: relative;
        padding: 8px;
        &:hover {
          background-color: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-5);
        }
        .el-icon {
          font-size: 36px;
          margin-bottom: 8px;
        }
        .hostname {
          display: inline-block;
          font-size: 14px;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .status {
          font-size: 14px;
          margin-top: 8px;
        }
        .close_icon {
          font-size: 15px;
          margin-top: 8px;
          position: absolute;
          right: 8px;
          top: 2px;
          cursor: pointer;
          &:hover {
            color: var(--el-color-danger);
          }
        }
      }
    }
  }
}
</style>
