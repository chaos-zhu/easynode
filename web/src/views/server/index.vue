<template>
  <div class="server_group_container">
    <div class="server_group_header">
      <!-- <el-button v-show="selectHosts.length" type="primary" @click="hostFormVisible = true">批量操作</el-button> -->
      <el-button type="primary" class="add_host_btn" @click="hostFormVisible = true">添加实例</el-button>
      <!-- <el-button type="primary" @click="handleHiddenIP">
        {{ hiddenIp ? '显示IP' : '隐藏IP' }}
      </el-button> -->
      <!-- <el-button type="primary" @click="importVisible = true">导入实例</el-button> -->
      <el-dropdown trigger="click">
        <el-button type="primary" class="group_action_btn">
          导入导出<el-icon class="el-icon--right"><arrow-down /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item @click="importVisible = true">导入实例</el-dropdown-item>
            <el-dropdown-item @click="handleBatchExport">导出实例</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
      <el-dropdown trigger="click">
        <el-button type="primary" class="group_action_btn">
          批量操作<el-icon class="el-icon--right"><arrow-down /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item @click="handleBatchSSH">连接终端</el-dropdown-item>
            <el-dropdown-item @click="handleBatchModify">批量修改</el-dropdown-item>
            <el-dropdown-item @click="handleBatchRemove">批量删除</el-dropdown-item>
            <el-dropdown-item @click="handleBatchOnekey">安装客户端</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>
    <div class="server_group_collapse">
      <div v-if="isNoHost">
        <el-empty description="暂无实例">
          <el-button type="primary" @click="hostFormVisible = true">添加实例配置</el-button>
          <span class="or">或</span>
          <el-button type="primary" @click="importVisible = true">批量导入实例</el-button>
        </el-empty>
      </div>
      <el-collapse v-else v-model="activeGroup">
        <el-collapse-item v-for="(hosts, groupName) in groupHostList" :key="groupName" :name="groupName">
          <template #title>
            <div class="group_title">
              {{ groupName }}
            </div>
          </template>
          <div class="host_card_container">
            <!-- <HostCard
              v-for="(item, index) in hosts"
              :key="index"
              :host-info="item"
              :hidden-ip="hiddenIp"
              @update-host="handleUpdateHost"
              @update-list="handleUpdateList"
            /> -->
            <HostTable
              ref="hostTableRefs"
              :hosts="hosts"
              @update-host="handleUpdateHost"
              @update-list="handleUpdateList"
            />
          </div>
        </el-collapse-item>
      </el-collapse>
    </div>
    <HostForm
      v-model:show="hostFormVisible"
      :default-data="updateHostData"
      :is-batch-modify="isBatchModify"
      :batch-hosts="selectHosts"
      @update-list="handleUpdateList"
      @closed="hostFormClosed"
    />
    <ImportHost
      v-model:show="importVisible"
      @update-list="handleUpdateList"
    />
  </div>
</template>

<script setup>
import { h, ref, getCurrentInstance, computed, watch } from 'vue'
// import HostCard from './components/host-card.vue'
import HostTable from './components/host-table.vue'
import HostForm from './components/host-form.vue'
import ImportHost from './components/import-host.vue'
import { ArrowDown } from '@element-plus/icons-vue'
import { exportFile } from '@/utils'

const { proxy: { $api, $store, $router, $message, $messageBox, $tools } } = getCurrentInstance()

let updateHostData = ref(null)
let hostFormVisible = ref(false)
let importVisible = ref(false)
let selectHosts = ref([])
let isBatchModify = ref(false)
const hostTableRefs = ref([])

let hiddenIp = ref(Number(localStorage.getItem('hiddenIp') || 0))
let activeGroup = ref([])

let handleUpdateList = async () => {
  try {
    await $store.getHostList()
  } catch (err) {
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
  }
}

// 收集选中的实例
let collectSelectHost = () => {
  let allSelectHosts = []
  hostTableRefs.value.map(item => {
    if (item) allSelectHosts = allSelectHosts.concat(item.getSelectHosts())
  })
  selectHosts.value = allSelectHosts
}

let handleBatchSSH = () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  let ips = selectHosts.value.filter(item => item.isConfig).map(item => item.host)
  if (!ips.length) return $message.warning('所选实例未配置ssh连接信息')
  if (ips.length < selectHosts.value.length) $message.warning('部分实例未配置ssh连接信息,已忽略')
  $router.push({ path: '/terminal', query: { host: ips.join(',') } })
}

let handleBatchModify = async () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  isBatchModify.value = true
  hostFormVisible.value = true
}

let handleBatchRemove = async () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  let ips = selectHosts.value.map(item => item.host)
  let names = selectHosts.value.map(item => item.name)

  $messageBox.confirm(() => h('p', { style: 'line-height: 18px;' }, `确认删除\n${ names.join(', ') }吗?`), 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    let { data } = await $api.removeHost({ host: ips })
    $message({ message: data, type: 'success', center: true })
    selectHosts.value = []
    await handleUpdateList()
    hostTableRefs.value.forEach(item => item.clearSelection())
  })
}

let handleUpdateHost = (defaultData) => {
  hostFormVisible.value = true
  updateHostData.value = defaultData
}

let handleBatchOnekey = async () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  let ips = selectHosts.value.map(item => item.host).join(',')
  $router.push({ path: '/onekey', query: { host: ips, execClientInstallScript: 'true' } })
}

let handleBatchExport = () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  console.log(selectHosts.value)
  let exportData = JSON.parse(JSON.stringify(selectHosts.value))
  exportData = exportData.map(item => {
    delete item.monitorData
    return item
  })
  const fileName = `easynode-${ $tools.formatTimestamp(Date.now(), 'time', '.') }.json`
  exportFile(exportData, fileName, 'application/json')
  hostTableRefs.value.forEach(item => item.clearSelection())
}

let handleHiddenIP = () => {
  hiddenIp.value = hiddenIp.value ? 0 : 1
  localStorage.setItem('hiddenIp', String(hiddenIp.value))
}

let hostList = computed(() => $store.hostList)

let groupHostList = computed(() => {
  let res = {}
  let groupList = $store.groupList
  groupList.forEach(group => {
    res[group.name] = []
  })
  hostList.value.forEach(item => {
    const group = groupList.find(group => group.id === item.group)
    if (group) {
      res[group.name].push(item)
    } else {
      res['默认分组'].push(item)
    }
  })
  Object.keys(res).map(groupName => {
    if (res[groupName].length === 0) delete res[groupName]
  })
  return res
})

watch(groupHostList, () => {
  activeGroup.value = [...Object.keys(groupHostList.value),]
}, {
  immediate: true,
  deep: false
})

let isNoHost = computed(() => Object.keys(groupHostList.value).length === 0)

let hostFormClosed = () => {
  updateHostData.value = null
  isBatchModify.value = false
  selectHosts.value = []
  hostTableRefs.value.forEach(item => item.clearSelection())
}

</script>

<style lang="scss" scoped>
.server_group_container {
  .server_group_header {
    padding: 15px;
    display: flex;
    align-items: center;
    justify-content: end;
    .add_host_btn {
      margin-right: 12px;
    }
    .group_action_btn {
      margin-right: 12px;
    }
  }

  .server_group_collapse {
    :deep(.el-collapse-item__header) {
      padding: 0 35px;
    }
    .group_title {
      // margin: 0 15px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
    }

    .host_card_container {
      padding-top: 15px;
    }
    .or {
      color: var(--el-text-color-secondary);
      font-size: var(--el-font-size-base);
      margin: 0 25px;
    }
  }
}
</style>
