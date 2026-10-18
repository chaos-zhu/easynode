<template>
  <div class="host_card">
    <el-table
      ref="tableRef"
      :data="hosts"
      row-key="id"
      :default-sort="defaultSort"
      @sort-change="handleSortChange"
      @selection-change="handleSelectionChange"
    >
      <el-table-column
        v-if="orderMode"
        width="64"
        align="center"
        class-name="order-drag-column"
      >
        <template #default><el-icon class="order-drag-handle"><Rank /></el-icon></template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.selection && !orderMode"
        type="selection"
        reserve-selection
        width="52"
      />
      <el-table-column
        v-if="props.columnSettings.name"
        label="名称"
        property="name"
        min-width="200"
        :sortable="!orderMode"
        :sort-method="compareHostNames"
      >
        <template #default="scope">
          <button
            type="button"
            class="host_name"
            :disabled="orderMode"
            :title="orderMode ? undefined : '编辑实例'"
            @click.stop="handleUpdate(scope.row)"
          >
            <svg-icon :name="scope.row.connectType === 'rdp' ? 'icon-Windows' : 'icon-linux'" class="icon" />
            {{ scope.row.name }}
          </button>
        </template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.username"
        property="username"
        label="用户名"
        min-width="110"
      />
      <el-table-column
        v-if="props.columnSettings.host"
        property="host"
        label="主机"
        min-width="150"
      >
        <template #default="scope">
          <el-tooltip content="点击复制" placement="top" :show-after="500">
            <span class="copyable_value" @click="handleCopy(scope.row.host)">{{ scope.row.host }}</span>
          </el-tooltip>
        </template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.port"
        property="port"
        label="端口"
        width="80"
      />
      <el-table-column
        v-if="props.columnSettings.authType"
        property="port"
        label="认证类型"
        min-width="110"
      >
        <template #default="scope">{{ scope.row.authType === 'password' ? '密码' : '密钥' }}</template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.proxyType"
        property="port"
        show-overflow-tooltip
        label="代理类型"
        min-width="120"
      >
        <template #default="scope">{{ formatProxyType(scope.row) }}</template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.expired"
        property="expired"
        label="到期时间"
        :sortable="!orderMode"
        min-width="120"
      />
      <el-table-column
        v-if="props.columnSettings.consoleUrl"
        property="consoleUrl"
        show-overflow-tooltip
        label="控制台URL"
        min-width="180"
      >
        <template #default="scope">
          <span v-if="scope.row.consoleUrl" class="link" @click="handleToConsole(scope.row)">{{ scope.row.consoleUrl }}</span>
          <span v-else>--</span>
        </template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.tag"
        show-overflow-tooltip
        property="tag"
        label="标签"
        min-width="140"
      >
        <template #default="scope">
          <span v-if="scope.row.tag?.length">
            <el-tag
              v-for="tag in scope.row.tag"
              :key="tag"
              type="success"
              effect="plain"
              size="small"
            >
              {{ tag }}
            </el-tag>
          </span>
          <span v-else>--</span>
        </template>
      </el-table-column>
      <el-table-column
        v-if="!orderMode"
        label="操作"
        fixed="right"
        width="138px"
        align="right"
        header-align="right"
      >
        <template #default="{ row }">
          <div class="row_actions">
            <el-tooltip
              :disabled="row.isConfig"
              effect="dark"
              content="请先配置连接信息"
              placement="left"
            >
              <span>
                <el-button
                  type="primary"
                  text
                  size="small"
                  :icon="Connection"
                  class="row_connect_btn"
                  :disabled="!row.isConfig"
                  @click="handleSSH(row)"
                >
                  连接
                </el-button>
              </span>
            </el-tooltip>
            <el-dropdown trigger="click" @command="command => handleRowCommand(command, row)">
              <el-button
                class="row_more_btn"
                :icon="MoreFilled"
                text
                aria-label="实例操作"
                title="实例操作"
              />
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item command="edit" :icon="EditPen">编辑配置</el-dropdown-item>
                  <el-dropdown-item
                    command="remove"
                    :icon="Delete"
                    divided
                    class="danger_menu_item"
                  >
                    删除实例
                  </el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
          </div>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick, watch } from 'vue'
import { Connection, Delete, EditPen, MoreFilled, Rank } from '@element-plus/icons-vue'
import clipboard from '@/utils/clipboard'
import { compareHostNames } from '@/utils/host-sort'
import useListOrder from '@/composables/useListOrder'

const { proxy: { $message, $messageBox, $api, $router, $store } } = getCurrentInstance()

const props = defineProps({
  hosts: {
    required: true,
    type: Array
  },
  columnSettings: {
    type: Object,
    default: () => ({
      selection: true,
      name: true,
      username: true,
      host: true,
      port: true,
      authType: true,
      proxyType: true,
      expired: true,
      consoleUrl: true,
      tag: true
    })
  },
  orderMode: Boolean
})

const emit = defineEmits(['update-list', 'update-host', 'select-change', 'reorder',])

const tableRef = ref(null)

const hosts = computed(() => props.hosts)
const hostList = computed(() => $store.hostList)
const proxyList = computed(() => $store.proxyList)

const handleUpdate = (hostInfo) => {
  emit('update-host', hostInfo)
}

const handleToConsole = ({ consoleUrl }) => {
  if (props.orderMode) return
  if (!consoleUrl) return $message({ message: '未配置服务商控制台地址', type: 'warning', center: true })
  window.open(consoleUrl)
}

const handleSSH = async (row) => {
  let { id, connectType } = row
  $router.push({ path: connectType === 'rdp' ? '/rdp' : '/terminal', query: { hostIds: id } })
}

const handleRowCommand = (command, row) => {
  if (command === 'edit') return handleUpdate(row)
  if (command === 'remove') return handleRemoveHost(row)
}

const defaultSortLocal = localStorage.getItem('host_table_sort')
let parsedDefaultSort = { prop: null, order: null }
try {
  parsedDefaultSort = defaultSortLocal ? JSON.parse(defaultSortLocal) : parsedDefaultSort
  if (parsedDefaultSort?.prop === 'index') parsedDefaultSort = { prop: null, order: null }
} catch {
  localStorage.removeItem('host_table_sort')
}
const defaultSort = ref(parsedDefaultSort)

const handleSortChange = (sortObj) => {
  if (props.orderMode) return
  defaultSort.value = sortObj
  localStorage.setItem('host_table_sort', JSON.stringify(sortObj))
}

useListOrder({
  rootRef: tableRef,
  enabled: computed(() => props.orderMode),
  onMove: (oldIndex, newIndex) => emit('reorder', { oldIndex, newIndex })
})

watch(() => props.orderMode, enabled => {
  if (enabled) nextTick(() => tableRef.value?.clearSort())
})

const selectHosts = ref([])
const handleSelectionChange = (val) => {
  // console.log('select: ', val)
  selectHosts.value = val
  emit('select-change', val)
}

const getSelectHosts = () => {
  return selectHosts.value
}

const clearSelection = () => {
  nextTick(() => tableRef.value.clearSelection())
}

const selectAll = () => {
  nextTick(() => tableRef.value.toggleAllSelection())
}

// 反选：已选的变成不选，未选的变成已选
const toggleSelection = () => {
  nextTick(() => {
    hosts.value.forEach(row => {
      tableRef.value.toggleRowSelection(row)
    })
  })
}

defineExpose({
  getSelectHosts,
  clearSelection,
  selectAll,
  toggleSelection
})

const handleRemoveHost = async ({ id }) => {
  $messageBox.confirm('确认删除实例', 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    let { data } = await $api.removeHost({ ids: [id,] })
    $message({
      message: data,
      type: 'success',
      center: true
    })
    emit('update-list')
    clearSelection()
  })
}

const handleCopy = (host) => {
  if (props.orderMode) return
  clipboard.copy(host)
}

const formatProxyType = ({ proxyType, jumpHosts, proxyServer }) => {
  if (!proxyType) return '--'
  if (proxyType === 'jumpHosts' && jumpHosts?.length > 0) {
    const jumpHostsName = jumpHosts.map(item => {
      const hostInfo = hostList.value.find(host => host.id === item)
      return hostInfo?.name || 'Error'
    }).join('>>>')
    return `[跳板机]${ jumpHostsName }`
  }
  if (proxyType === 'proxyServer' && proxyList.value.some(item => item.id === proxyServer)) {
    const proxyServerInfo = proxyList.value.find(item => item.id === proxyServer)
    return `[${ proxyServerInfo.type }]${ proxyServerInfo.name }`
  }
  return '--'
}
</script>

<style lang="scss" scoped>
.host_card {
  margin: 0 16px 16px;
  border: 1px solid var(--el-border-color-lighter);
  border-radius: 10px;
  overflow: hidden;

  :deep(.el-table) {
    --el-table-header-bg-color: var(--el-fill-color-light);
    --el-table-row-hover-bg-color: var(--el-fill-color-light);
  }

  :deep(.el-table th.el-table__cell) {
    height: 46px;
    color: var(--el-text-color-secondary);
    font-weight: 600;
  }

  :deep(.el-table td.el-table__cell) {
    padding: 13px 0;
  }

  :deep(.el-table__inner-wrapper::before) {
    display: none;
  }

  .no_client_data {
    font-size: 14px;
    font-weight: normal;
    line-height: 23px;
    text-align: center;
    color: var(--el-color-warning);
  }
  .host_info {
    padding: 0 20px;
  }
}

.host_name {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 0;
  border: 0;
  border-bottom: 1px dashed transparent;
  background: none;
  color: var(--el-text-color-primary);
  font: inherit;
  font-weight: 600;
  white-space: nowrap;
  cursor: pointer;
  transition: color 0.18s ease, border-color 0.18s ease;

  &:enabled:hover,
  &:focus-visible {
    color: var(--el-color-primary);
    border-bottom-color: var(--el-color-primary-light-5);
  }

  &:focus-visible {
    outline: 2px solid var(--el-color-primary);
    outline-offset: 3px;
  }

  &:disabled {
    cursor: inherit;
  }

  .icon {
    flex: 0 0 auto;
  }
}

.copyable_value {
  cursor: copy;
  border-bottom: 1px dashed transparent;
  transition: color 0.18s ease, border-color 0.18s ease;

  &:hover {
    color: var(--el-color-primary);
    border-color: var(--el-color-primary-light-5);
  }
}

.row_actions {
  display: inline-flex;
  align-items: center;
  justify-content: flex-end;
  gap: 6px;
  white-space: nowrap;

  :deep(.el-button) {
    height: 32px;
    border-radius: 6px;
  }

  .row_connect_btn {
    padding: 0 10px;
  }

  .row_more_btn {
    width: 32px;
    height: 32px;
    padding: 0;
    color: var(--el-text-color-secondary);

    &:hover,
    &:focus-visible {
      color: var(--el-text-color-primary);
      background: var(--el-fill-color);
    }
  }
}

:deep(.danger_menu_item) {
  color: var(--el-color-danger);
}
</style>
