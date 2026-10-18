<template>
  <div class="server_group_container">
    <div class="server_group_header" :class="{ 'is-ordering': orderMode }">
      <template v-if="orderMode">
        <div class="order_mode_status">
          <span class="order_mode_icon"><el-icon><Rank /></el-icon></span>
          <div>
            <div class="order_mode_title">正在调整顺序</div>
            <div class="order_mode_hint">
              {{ displayMode === 'group' ? '拖动任意实例行，调整组内顺序' : '拖动任意实例行，调整全部实例的顺序' }}
            </div>
          </div>
        </div>
        <div class="toolbar_actions">
          <el-button @click="cancelOrder">取消</el-button>
          <el-button type="primary" :loading="orderSaving" @click="saveOrder">保存顺序</el-button>
        </div>
      </template>
      <template v-else>
        <el-input
          v-if="hostList.length > 2"
          v-model="searchKeyword"
          placeholder="搜索名称、用户名、主机或标签"
          class="search_input"
          clearable
          spellcheck="false"
          @keyup.esc="clearSearch"
        >
          <template #prefix>
            <el-icon><Search /></el-icon>
          </template>
        </el-input>
        <div v-else class="host_overview">
          共 <strong>{{ hostList.length }}</strong> 台实例
        </div>
        <div class="toolbar_actions">
          <el-button
            type="primary"
            :icon="Plus"
            class="primary_action_btn"
            @click="hostFormVisible = true"
          >
            添加实例
          </el-button>
          <el-dropdown trigger="click">
            <el-button
              class="more_actions_btn"
              :icon="MoreFilled"
              aria-label="更多操作"
              title="更多操作"
            />
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item :icon="FolderOpened" @click="groupDialogVisible = true">
                  分组管理
                </el-dropdown-item>
                <el-dropdown-item :icon="Setting" @click="listSettingsVisible = true">
                  列表设置
                </el-dropdown-item>
                <el-dropdown-item :icon="Rank" @click="startOrder">
                  调整顺序
                </el-dropdown-item>
                <el-dropdown-item :icon="Upload" divided @click="importVisible = true">
                  导入实例
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </template>
    </div>

    <Transition name="batch-toolbar">
      <div v-if="selectHosts.length && !orderMode" class="batch_toolbar">
        <div class="batch_summary">
          <span class="batch_check"><el-icon><CircleCheckFilled /></el-icon></span>
          <span>已选择 <strong>{{ selectHosts.length }}</strong> 台实例</span>
        </div>
        <div class="batch_actions">
          <el-button
            text
            type="primary"
            :icon="Connection"
            @click="handleBatchConnect"
          >
            批量连接
          </el-button>
          <el-button text :icon="EditPen" @click="handleBatchModify">批量修改</el-button>
          <el-button text :icon="Download" @click="handleBatchExport">导出</el-button>
          <el-button
            text
            type="danger"
            :icon="Delete"
            @click="handleBatchRemove"
          >
            删除
          </el-button>
          <span class="batch_divider" />
          <el-button text @click="handleSelectAll">反选</el-button>
          <el-button text :icon="Close" @click="clearAllSelection">取消选择</el-button>
        </div>
      </div>
    </Transition>
    <div class="server_group_collapse">
      <div v-if="isNoHost">
        <el-empty description="暂无实例">
          <el-button type="primary" :icon="Plus" @click="hostFormVisible = true">添加实例配置</el-button>
          <span class="or">或</span>
          <el-button :icon="Upload" @click="importVisible = true">批量导入实例</el-button>
        </el-empty>
      </div>
      <div v-else-if="isNoSearchResult" class="search_empty">
        <el-empty :image-size="80" description="未找到匹配的实例">
          <el-button @click="clearSearch">清除搜索</el-button>
        </el-empty>
      </div>
      <!-- 分组展示模式 -->
      <el-collapse v-else-if="displayMode === 'group'" v-model="activeGroup">
        <el-collapse-item v-for="group in groupHostList" :key="group.id" :name="group.id">
          <template #title>
            <div class="group_title">
              <span>{{ group.name }}</span>
              <span class="group_count">{{ group.hosts.length }}</span>
            </div>
          </template>
          <HostTable
            ref="hostTableRefs"
            :hosts="group.hosts"
            :column-settings="columnSettings"
            :order-mode="orderMode"
            @reorder="event => reorderGroup(group.id, event)"
            @select-change="handleSelectionChange"
            @update-host="handleUpdateHost"
            @update-list="handleUpdateList"
          />
        </el-collapse-item>
      </el-collapse>

      <!-- 列表展示模式 -->
      <div v-else class="list_mode_container">
        <HostTable
          ref="hostTableRefs"
          :hosts="flatHostList"
          :column-settings="columnSettings"
          :order-mode="orderMode"
          @reorder="reorderFlat"
          @select-change="handleSelectionChange"
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
import { h, ref, getCurrentInstance, computed, watch, onMounted, onUnmounted, nextTick } from 'vue'
// import HostCard from './components/host-card.vue'
import HostTable from './components/host-table.vue'
import HostForm from './components/host-form.vue'
import ImportHost from './components/import-host.vue'
import GroupDialog from './components/group.vue'
import ListSettings from './components/list-settings.vue'
import {
  ArrowUp,
  CircleCheckFilled,
  Close,
  Connection,
  Delete,
  Download,
  EditPen,
  FolderOpened,
  MoreFilled,
  Plus,
  Rank,
  Search,
  Setting,
  Upload
} from '@element-plus/icons-vue'
import { exportFile } from '@/utils'
import { moveArrayItem } from '@/composables/useListOrder'
import { matchesHostSearch } from '@/utils/host-sort'

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
  name: { label: '名称', disabled: false },
  username: { label: '用户名', disabled: false },
  host: { label: '主机', disabled: false },
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
    await $store.getHostCatalog()
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

const handleSelectionChange = () => nextTick(collectSelectHost)

const clearAllSelection = () => {
  getHostTableRefs().forEach(item => item?.clearSelection?.())
  selectHosts.value = []
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
    await handleUpdateList()
    clearAllSelection()
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
    delete item.index
    return item
  })
  const fileName = `easynode-${ $tools.formatTimestamp(Date.now(), 'time', '.') }.json`
  exportFile(exportData, fileName, 'application/json')
  clearAllSelection()
}

const hostList = computed(() => $store.hostList)

const searchKeyword = ref('')
const normalizedSearchKeyword = computed(() => searchKeyword.value.trim())

const filteredHostList = computed(() => {
  if (!normalizedSearchKeyword.value) return hostList.value
  return hostList.value.filter(host => matchesHostSearch(host, normalizedSearchKeyword.value))
})

const clearSearch = () => {
  searchKeyword.value = ''
}

const groupHostList = computed(() => {
  const hostById = new Map(filteredHostList.value.map(host => [host.id, host,]))
  const groupById = new Map($store.groupList.map(group => [group.id, group,]))
  const sections = orderMode.value ? orderDraft.value.sections : $store.hostOrder.sections
  return sections.map(section => ({
    id: section.groupId,
    name: groupById.get(section.groupId)?.name || '默认分组',
    hosts: section.itemIds.map(id => hostById.get(id)).filter(Boolean)
  })).filter(group => group.hosts.length)
})

const flatHostList = computed(() => {
  if (!orderMode.value) return filteredHostList.value
  const hostById = new Map(hostList.value.map(host => [host.id, host,]))
  return orderDraft.value.flatItemIds.map(id => hostById.get(id)).filter(Boolean)
})

const orderMode = ref(false)
const orderDraft = ref(null)
const orderSaving = ref(false)

const startOrder = () => {
  clearAllSelection()
  searchKeyword.value = ''
  orderDraft.value = JSON.parse(JSON.stringify($store.hostOrder))
  orderMode.value = true
}

const cancelOrder = () => {
  orderMode.value = false
  orderDraft.value = null
}

const reorderFlat = ({ oldIndex, newIndex }) => moveArrayItem(orderDraft.value.flatItemIds, oldIndex, newIndex)

const reorderGroup = (groupId, event) => {
  const section = orderDraft.value.sections.find(item => item.groupId === groupId)
  if (section) moveArrayItem(section.itemIds, event.oldIndex, event.newIndex)
}

const saveOrder = async () => {
  const changes = displayMode.value === 'group'
    ? orderDraft.value.sections.map(section => ({
      scope: 'groupItems',
      groupId: section.groupId,
      orderedIds: section.itemIds
    }))
    : [{ scope: 'flat', orderedIds: orderDraft.value.flatItemIds },]
  try {
    orderSaving.value = true
    await $api.updateHostOrder({ revision: orderDraft.value.revision, changes })
    await $store.getHostCatalog()
    cancelOrder()
    $message.success('顺序已保存')
  } catch (error) {
    if (error.response?.status === 409) {
      cancelOrder()
      await $store.getHostCatalog()
      $message.warning('顺序已被其他客户端修改，请重新调整')
      return
    }
    $message.error('保存顺序失败')
  } finally {
    orderSaving.value = false
  }
}

watch(groupHostList, () => {
  activeGroup.value = groupHostList.value.map(({ id }) => id)
}, {
  immediate: true,
  deep: false
})

const isNoHost = computed(() => hostList.value.length === 0)
const isNoSearchResult = computed(() => (
  Boolean(normalizedSearchKeyword.value) && filteredHostList.value.length === 0
))

const hostFormClosed = () => {
  updateHostData.value = null
  isBatchModify.value = false
  clearAllSelection()
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
  display: flex;
  flex-direction: column;
  min-width: 0;

  .server_group_header {
    min-height: 64px;
    padding: 12px 16px;
    display: flex;
    align-items: center;
    gap: 16px;
    flex: 0 0 auto;
    border-bottom: 1px solid var(--el-border-color-lighter);

    @media screen and (max-width: 768px) {
      min-height: auto;
      padding: 10px 12px;
      flex-wrap: wrap;
      gap: 10px;
    }

    .search_input {
      width: clamp(260px, 32vw, 380px);

      :deep(.el-input__wrapper) {
        min-height: 36px;
        background: var(--el-fill-color-light);
        border-radius: 8px;
        box-shadow: 0 0 0 1px transparent inset;
        transition: background-color .18s ease, box-shadow .18s ease;
      }

      :deep(.el-input__wrapper:hover) {
        box-shadow: 0 0 0 1px var(--el-border-color) inset;
      }

      :deep(.el-input__wrapper.is-focus) {
        background: var(--el-bg-color);
        box-shadow: 0 0 0 1px var(--el-color-primary) inset;
      }

      @media screen and (max-width: 768px) {
        width: 100%;
        order: 2;
      }
    }

    .host_overview {
      color: var(--el-text-color-secondary);
      font-size: 13px;

      @media screen and (max-width: 768px) {
        display: none;
      }

      strong {
        color: var(--el-text-color-primary);
        font-size: 15px;
        font-weight: 600;
      }
    }

    .toolbar_actions {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-left: auto;
      white-space: nowrap;

      :deep(.el-button + .el-button) {
        margin-left: 0;
      }

      :deep(.el-button) {
        height: 36px;
        border-radius: 8px;
      }

      .primary_action_btn {
        padding: 0 15px;
      }
    }

    .more_actions_btn {
      width: 36px;
      height: 36px;
      padding: 0;
      color: var(--el-text-color-secondary);
      border-radius: 8px;

      &:hover,
      &:focus-visible {
        color: var(--el-text-color-primary);
        background: var(--el-fill-color);
        border-color: var(--el-border-color);
      }
    }

    &.is-ordering {
      background: var(--el-color-primary-light-9);
      border-bottom-color: var(--el-color-primary-light-7);
    }
  }

  .order_mode_status {
    display: flex;
    align-items: center;
    gap: 11px;
    min-width: 0;

    .order_mode_icon {
      width: 36px;
      height: 36px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex: 0 0 auto;
      color: var(--el-color-primary);
      font-size: 18px;
      background: var(--el-color-primary-light-8);
      border-radius: 9px;
    }

    .order_mode_title {
      color: var(--el-text-color-primary);
      font-size: 14px;
      font-weight: 600;
      line-height: 20px;
    }

    .order_mode_hint {
      color: var(--el-text-color-secondary);
      font-size: 12px;
      line-height: 18px;

      @media screen and (max-width: 640px) {
        display: none;
      }
    }
  }

  .batch_toolbar {
    min-height: 48px;
    margin: 12px 16px 0;
    padding: 6px 8px 6px 12px;
    display: flex;
    align-items: center;
    gap: 16px;
    flex: 0 0 auto;
    color: var(--el-text-color-regular);
    background: var(--el-color-primary-light-9);
    border: 1px solid var(--el-color-primary-light-7);
    border-radius: 9px;

    @media screen and (max-width: 880px) {
      align-items: flex-start;
      flex-direction: column;
      gap: 2px;
    }

    .batch_summary {
      display: flex;
      align-items: center;
      gap: 8px;
      flex: 0 0 auto;
      font-size: 13px;

      .batch_check {
        display: inline-flex;
        color: var(--el-color-primary);
        font-size: 17px;
      }
    }

    .batch_actions {
      display: flex;
      align-items: center;
      gap: 2px;
      margin-left: auto;
      overflow-x: auto;

      @media screen and (max-width: 880px) {
        width: 100%;
        margin-left: -8px;
      }

      :deep(.el-button + .el-button) {
        margin-left: 0;
      }

      :deep(.el-button) {
        height: 32px;
        padding: 0 10px;
        border-radius: 6px;
      }
    }

    .batch_divider {
      width: 1px;
      height: 20px;
      margin: 0 4px;
      flex: 0 0 auto;
      background: var(--el-border-color);
    }
  }

  .server_group_collapse {
    position: relative;
    min-height: 0;
    flex: 1 1 auto;
    overflow-y: auto;
    padding-top: 12px;

    :deep(.el-card__body) {
      padding: 0;
    }

    :deep(.el-collapse) {
      border-top: 0;
    }

    :deep(.el-collapse-item__header) {
      height: 48px;
      padding: 0 24px;
      color: var(--el-text-color-primary);
      border-bottom-color: var(--el-border-color-lighter);
    }

    :deep(.el-collapse-item__wrap) {
      border-bottom-color: var(--el-border-color-lighter);
    }

    :deep(.el-collapse-item__content) {
      padding-bottom: 0;
    }

    .group_title {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
    }

    .group_count {
      min-width: 24px;
      padding: 1px 7px;
      color: var(--el-text-color-secondary);
      font-size: 12px;
      font-weight: 500;
      line-height: 18px;
      text-align: center;
      background: var(--el-fill-color);
      border-radius: 10px;
    }

    .or {
      color: var(--el-text-color-secondary);
      font-size: var(--el-font-size-base);
      margin: 0 25px;
    }

    .search_empty {
      padding-top: 8vh;
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
