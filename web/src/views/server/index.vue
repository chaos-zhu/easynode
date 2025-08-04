<template>
  <div class="server_group_container">
    <div class="server_group_header">
      <el-button type="primary" class="add_host_btn" @click="hostFormVisible = true">添加实例</el-button>

      <el-dropdown trigger="click">
        <el-button type="primary" class="group_action_btn">
          批量操作<el-icon class="el-icon--right"><arrow-down /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item @click="handleBatchSSH">连接终端</el-dropdown-item>
            <el-dropdown-item @click="handleBatchModify">批量修改</el-dropdown-item>
            <el-dropdown-item @click="handleBatchRemove">批量删除</el-dropdown-item>
            <el-dropdown-item @click="handleSelectAll">反选所有</el-dropdown-item>
            <el-dropdown-item @click="importVisible = true">导入实例</el-dropdown-item>
            <el-dropdown-item @click="handleBatchExport">导出实例</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
      <el-button type="primary" @click="groupDialogVisible = true">分组管理</el-button>
      <el-button
        type="primary"
        class="table_header_setting_btn"
        @click="columnSettingsVisible = true"
      >
        表头设置
      </el-button>
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
              {{ `${groupName}`+`${hosts.length ? `(${hosts.length})` : ''}` }}
            </div>
          </template>
          <HostTable
            ref="hostTableRefs"
            :hosts="hosts"
            :column-settings="rawColumnSettings"
            @update-host="handleUpdateHost"
            @update-list="handleUpdateList"
          />
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
    <GroupDialog v-model:show="groupDialogVisible" />

    <!-- 表头设置弹窗 -->
    <el-dialog
      v-model="columnSettingsVisible"
      title="表头设置"
      width="400px"
      append-to-body
    >
      <div class="column-settings">
        <div v-for="(item, key) in columnConfig" :key="key" class="column-item">
          <el-checkbox
            v-model="columnSettings[key]"
            :disabled="item.disabled"
          >
            {{ item.label }}
          </el-checkbox>
        </div>
      </div>
      <template #footer>
        <div class="dialog-footer">
          <el-button @click="resetColumnSettings">重置默认</el-button>
          <el-button type="primary" @click="saveColumnSettings">确定</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { h, ref, getCurrentInstance, computed, watch } from 'vue'
// import HostCard from './components/host-card.vue'
import HostTable from './components/host-table.vue'
import HostForm from './components/host-form.vue'
import ImportHost from './components/import-host.vue'
import GroupDialog from './components/group.vue'
import { ArrowDown } from '@element-plus/icons-vue'
import { exportFile } from '@/utils'

const { proxy: { $api, $store, $router, $message, $messageBox, $tools } } = getCurrentInstance()

const updateHostData = ref(null)
const hostFormVisible = ref(false)
const importVisible = ref(false)
const selectHosts = ref([])
const isBatchModify = ref(false)
const hostTableRefs = ref([])
const activeGroup = ref([])
const groupDialogVisible = ref(false)

// 列设置相关
const columnSettingsVisible = ref(false)

// 列配置定义
const columnConfig = {
  selection: { label: '选择', disabled: false },
  index: { label: '序号', disabled: false },
  name: { label: '名称', disabled: false },
  username: { label: '用户名', disabled: false },
  host: { label: 'IP', disabled: false },
  port: { label: '端口', disabled: false },
  authType: { label: '认证类型', disabled: false },
  proxyType: { label: '代理类型', disabled: false },
  expired: { label: '到期时间', disabled: false },
  consoleUrl: { label: '控制台URL', disabled: false },
  tag: { label: 'Tag', disabled: false }
}

// 默认列设置
const defaultColumnSettings = {
  selection: true,
  index: true,
  name: true,
  username: true,
  host: true,
  port: true,
  authType: true,
  proxyType: false,
  expired: false,
  consoleUrl: false,
  tag: false
}

// 从localStorage获取列设置
const getColumnSettings = () => {
  const saved = localStorage.getItem('host_table_column_settings')
  return saved ? { ...defaultColumnSettings, ...JSON.parse(saved) } : { ...defaultColumnSettings }
}

// 列设置状态
const columnSettings = ref(getColumnSettings())
const rawColumnSettings = ref({ ...columnSettings.value })

// 保存列设置到localStorage
const saveColumnSettings = () => {
  localStorage.setItem('host_table_column_settings', JSON.stringify(columnSettings.value))
  rawColumnSettings.value = { ...columnSettings.value }
  columnSettingsVisible.value = false
}

// 重置列设置
const resetColumnSettings = () => {
  columnSettings.value = { ...defaultColumnSettings }
}

const handleUpdateList = async () => {
  try {
    await $store.getHostList()
  } catch (err) {
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
  }
}

// 收集选中的实例
const collectSelectHost = () => {
  let allSelectHosts = []
  hostTableRefs.value.map(item => {
    if (item) allSelectHosts = allSelectHosts.concat(item.getSelectHosts())
  })
  selectHosts.value = allSelectHosts
}

const handleBatchSSH = () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  let ids = selectHosts.value.filter(item => item.isConfig).map(item => item.id)
  if (!ids.length) return $message.warning('所选实例未配置ssh连接信息')
  if (ids.length < selectHosts.value.length) $message.warning('部分实例未配置ssh连接信息,已忽略')
  $router.push({ path: '/terminal', query: { hostIds: ids.join(',') } })
}

const handleBatchModify = async () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  isBatchModify.value = true
  hostFormVisible.value = true
}

const handleSelectAll = () => {
  hostTableRefs.value.forEach(item => item.selectAll())
}

const handleBatchRemove = async () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  let ids = selectHosts.value.map(item => item.id)
  let names = selectHosts.value.map(item => item.name)

  $messageBox.confirm(() => h('p', { style: 'line-height: 18px;' }, `确认删除\n${ names.join(', ') }吗?`), 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    let { data } = await $api.removeHost({ ids })
    $message({ message: data, type: 'success', center: true })
    selectHosts.value = []
    await handleUpdateList()
    hostTableRefs.value.forEach(item => item.clearSelection())
  })
}

const handleUpdateHost = (defaultData) => {
  hostFormVisible.value = true
  updateHostData.value = defaultData
}

const handleBatchExport = () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  let exportData = JSON.parse(JSON.stringify(selectHosts.value))
  exportData = exportData.map(item => {
    delete item.monitorData
    return item
  })
  const fileName = `easynode-${ $tools.formatTimestamp(Date.now(), 'time', '.') }.json`
  exportFile(exportData, fileName, 'application/json')
  hostTableRefs.value.forEach(item => item.clearSelection())
}

const hostList = computed(() => $store.hostList)

const groupHostList = computed(() => {
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

const isNoHost = computed(() => Object.keys(groupHostList.value).length === 0)

const hostFormClosed = () => {
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
    gap: 12px;
    flex-wrap: nowrap;
    overflow-x: auto;
    white-space: nowrap;
    -webkit-overflow-scrolling: touch;
    justify-content: flex-end;

    @media screen and (max-width: 768px) {
      justify-content: flex-start;
    }

    &::-webkit-scrollbar {
      display: none;
    }

    .add_host_btn,
    .group_action_btn,
    .el-button {
      flex-shrink: 0;
      min-width: fit-content;
    }
    .table_header_setting_btn {
      margin-left: 0px;
    }

    > :last-child {
      margin-right: 0;
    }
  }

  .server_group_collapse {
    :deep(.el-card__body) {
      padding: 0;
    }
    :deep(.el-collapse-item__header) {
      padding: 0 35px;
    }
    .group_title {
      // margin: 0 15px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
    }

    .or {
      color: var(--el-text-color-secondary);
      font-size: var(--el-font-size-base);
      margin: 0 25px;
    }
  }
}

.column-settings {
  .column-item {
    margin-bottom: 12px;

    &:last-child {
      margin-bottom: 0;
    }
  }
}

.dialog-footer {
  display: flex;
  justify-content: space-between;
}
</style>
