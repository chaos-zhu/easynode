<template>
  <div class="server_group_container">
    <div class="server_group_header">
      <el-input
        v-if="hostList.length > 2"
        v-model="searchKeyword"
        placeholder="搜索实例"
        class="search_input"
        clearable
      >
        <template #prefix>
          <el-icon><Search /></el-icon>
        </template>
      </el-input>
      <el-button
        type="primary"
        class="add_host_btn"
        :class="{ 'first_btn': hostList.length <= 2 }"
        @click="hostFormVisible = true"
      >
        添加实例
      </el-button>
      <el-dropdown trigger="click">
        <el-button type="primary" class="group_action_btn">
          批量操作<el-icon class="el-icon--right"><arrow-down /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item @click="handleBatchConnect">连接终端</el-dropdown-item>
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
        @click="listSettingsVisible = true"
      >
        列表设置
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
      <!-- 分组展示模式 -->
      <el-collapse v-else-if="displayMode === 'group'" v-model="activeGroup">
        <el-collapse-item v-for="(hosts, groupName) in groupHostList" :key="groupName" :name="groupName">
          <template #title>
            <div class="group_title">
              {{ `${groupName}`+`${hosts.length ? `(${hosts.length})` : ''}` }}
            </div>
          </template>
          <HostTable
            ref="hostTableRefs"
            :hosts="hosts"
            :column-settings="columnSettings"
            @update-host="handleUpdateHost"
            @update-list="handleUpdateList"
          />
        </el-collapse-item>
      </el-collapse>

      <!-- 列表展示模式 -->
      <div v-else class="list_mode_container">
        <HostTable
          ref="hostTableRefs"
          :hosts="filteredHostList"
          :column-settings="columnSettings"
          @update-host="handleUpdateHost"
          @update-list="handleUpdateList"
        />
      </div>

      <!-- 滚动到顶部按钮 -->
      <Transition name="scroll-to-top">
        <div
          v-show="showScrollToTop"
          class="scroll-to-top-btn"
          @click="scrollToTop"
        >
          <el-icon><ArrowUp /></el-icon>
        </div>
      </Transition>
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

    <!-- 列表设置弹窗 -->
    <ListSettings
      v-model:show="listSettingsVisible"
      :column-config="columnConfig"
      :column-settings="columnSettings"
      :display-mode="displayMode"
      @confirm="handleSettingsConfirm"
    />
  </div>
</template>

<script setup>
import { h, ref, getCurrentInstance, computed, watch, onMounted, onUnmounted } from 'vue'
// import HostCard from './components/host-card.vue'
import HostTable from './components/host-table.vue'
import HostForm from './components/host-form.vue'
import ImportHost from './components/import-host.vue'
import GroupDialog from './components/group.vue'
import ListSettings from './components/list-settings.vue'
import { ArrowDown, ArrowUp, Search } from '@element-plus/icons-vue'
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
const listSettingsVisible = ref(false)

// 展示模式（从store获取）
const displayMode = computed(() => $store.serverListConfig.displayMode)

// 滚动到顶部相关
const showScrollToTop = ref(false)
const scrollContainer = ref(null)

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

// 列设置状态（从store获取）
const columnSettings = computed(() => $store.serverListConfig.columnSettings)

// 处理设置确认
const handleSettingsConfirm = async (settings) => {
  try {
    // 保存到数据库
    await $store.setServerListConfig(settings)
    $message.success('设置已保存')
  } catch (error) {
    $message.error('保存设置失败')
    console.error('保存设置失败:', error)
  }
}

const handleUpdateList = async () => {
  try {
    await $store.getHostList()
  } catch (err) {
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
  }
}

// 获取所有 HostTable 组件的引用（兼容分组和列表模式）
const getHostTableRefs = () => {
  if (!hostTableRefs.value) return []
  // 列表模式下是单个组件，分组模式下是数组
  return Array.isArray(hostTableRefs.value) ? hostTableRefs.value : [hostTableRefs.value,]
}

// 收集选中的实例
const collectSelectHost = () => {
  let allSelectHosts = []
  getHostTableRefs().forEach(item => {
    if (item) allSelectHosts = allSelectHosts.concat(item.getSelectHosts())
  })
  selectHosts.value = allSelectHosts
}

const handleBatchConnect = () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  let ids = selectHosts.value.filter(item => item.isConfig).map(item => item.id)
  if (!ids.length) return $message.warning('所选实例未配置ssh连接信息')
  // $router.push({ path: '/terminal', query: { hostIds: ids.join(',') } })
  if (selectHosts.value.every(item => item.connectType === 'rdp')) {
    $router.push({ path: '/rdp', query: { hostIds: ids.join(',') } })
  } else if (selectHosts.value.every(item => !item.connectType || item.connectType === 'ssh')) {
    $router.push({ path: '/terminal', query: { hostIds: ids.join(',') } })
  } else {
    $message.warning('所选实例包含rdp和ssh连接信息,请选择同一终端类型进行批量连接')
    return
  }
  if (ids.length < selectHosts.value.length) $message.warning('部分实例未配置ssh连接信息,已忽略')
}

const handleBatchModify = async () => {
  collectSelectHost()
  if (!selectHosts.value.length) return $message.warning('请选择要批量操作的实例')
  isBatchModify.value = true
  hostFormVisible.value = true
}

const handleSelectAll = () => {
  getHostTableRefs().forEach(item => {
    if (item && item.toggleSelection) {
      item.toggleSelection()
    }
  })
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
    getHostTableRefs().forEach(item => item.clearSelection())
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
  getHostTableRefs().forEach(item => item.clearSelection())
}

const hostList = computed(() => $store.hostList)

const searchKeyword = ref('')

const filteredHostList = computed(() => {
  if (!searchKeyword.value) return hostList.value

  const keyword = searchKeyword.value.toLowerCase()
  return hostList.value.filter(item => {
    // 搜索实例名称
    if (item.name && item.name.toLowerCase().includes(keyword)) return true
    // 搜索用户名
    if (item.username && item.username.toLowerCase().includes(keyword)) return true
    // 搜索IP
    if (item.host && item.host.toLowerCase().includes(keyword)) return true
    // 搜索标签
    if (item.tag && Array.isArray(item.tag)) {
      return item.tag.some(tag => tag.toLowerCase().includes(keyword))
    }
    return false
  })
})

const groupHostList = computed(() => {
  let res = {}
  let groupList = $store.groupList
  groupList.forEach(group => {
    res[group.name] = []
  })
  filteredHostList.value.forEach(item => {
    const group = groupList.find(group => group.id === item.group)
    if (group?.name) {
      res[group.name].push(item)
    } else {
      if (!res['默认分组']) res['默认分组'] = []
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
  getHostTableRefs().forEach(item => item.clearSelection())
}

// 滚动监听处理
const handleScroll = () => {
  if (scrollContainer.value) {
    const scrollTop = scrollContainer.value.scrollTop
    showScrollToTop.value = scrollTop > 100
  }
}

// 滚动到顶部
const scrollToTop = () => {
  if (scrollContainer.value) {
    scrollContainer.value.scrollTo({
      top: 0,
      behavior: 'smooth'
    })
  }
}

// 组件挂载时添加滚动监听
onMounted(() => {
  const container = document.querySelector('.server_group_collapse')
  if (container) {
    scrollContainer.value = container
    container.addEventListener('scroll', handleScroll)
  }
})

// 组件卸载时移除滚动监听
onUnmounted(() => {
  if (scrollContainer.value) {
    scrollContainer.value.removeEventListener('scroll', handleScroll)
  }
})

</script>

<style lang="scss" scoped>
.server_group_container {
  height: 100%;
  .server_group_header {
    padding: 10px;
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: nowrap;
    overflow-x: auto;
    white-space: nowrap;
    -webkit-overflow-scrolling: touch;

    @media screen and (max-width: 768px) {
      justify-content: flex-start;
    }

    &::-webkit-scrollbar {
      display: none;
    }

    .search_input {
      width: 300px;
      margin-right: auto;
      flex-shrink: 0;

      @media screen and (max-width: 768px) {
        width: 200px;
      }
    }

    .add_host_btn,
    .group_action_btn,
    .el-button {
      flex-shrink: 0;
      min-width: fit-content;
    }

    .first_btn {
      margin-left: auto;
    }
    .table_header_setting_btn {
      margin-left: 0px;
    }

    > :last-child {
      margin-right: 0;
    }
  }

  .server_group_collapse {
    position: relative;
    height: calc(100% - 55px);
    overflow-y: auto;
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

    .list-mode-container {
      padding: 10px;
    }

    .scroll-to-top-btn {
      position: fixed;
      right: 15px;
      bottom: 10px;
      width: 40px;
      height: 40px;
      background: var(--el-color-primary);
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      box-shadow: 0 2px 12px 0 rgba(0, 0, 0, 0.1);
      z-index: 1000;
      transition: all 0.3s ease;

      &:hover {
        background: var(--el-color-primary-light-3);
        transform: translateY(-2px);
        box-shadow: 0 4px 16px 0 rgba(0, 0, 0, 0.15);
      }

      .el-icon {
        color: white;
        font-size: 18px;
      }
    }
  }
}

// 滚动到顶部按钮的过渡动画
.scroll-to-top-enter-active,
.scroll-to-top-leave-active {
  transition: all 0.3s ease;
}

.scroll-to-top-enter-from,
.scroll-to-top-leave-to {
  opacity: 0;
  transform: translateY(20px) scale(0.8);
}
</style>
