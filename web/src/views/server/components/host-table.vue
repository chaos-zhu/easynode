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
      <el-table-column v-if="props.columnSettings.selection" type="selection" reserve-selection />
      <el-table-column
        v-if="props.columnSettings.index"
        property="index"
        :label="t('server.index')"
        sortable
        width="100px"
      />
      <el-table-column
        v-if="props.columnSettings.name"
        :label="t('common.name')"
        property="name"
        sortable
        :sort-method="(a, b) => a.name - b.name"
      >
        <template #default="scope">
          <span v-if="scope.row.connectType !== 'rdp'">
            <svg-icon name="icon-linux" class="icon" />
            {{ scope.row.name }}
          </span>
          <span v-else>
            <svg-icon name="icon-Windows" class="icon" />
            {{ scope.row.name }}
          </span>
        </template>
      </el-table-column>
      <el-table-column v-if="props.columnSettings.username" property="username" :label="t('server.username')" />
      <el-table-column v-if="props.columnSettings.host" property="host" :label="t('server.ip')">
        <template #default="scope">
          <span @click="handleCopy(scope.row.host)">{{ scope.row.host }}</span>
        </template>
      </el-table-column>
      <el-table-column v-if="props.columnSettings.port" property="port" :label="t('server.port')" />
      <el-table-column v-if="props.columnSettings.authType" property="port" :label="t('server.authType')">
        <template #default="scope">{{ scope.row.authType === 'password' ? t('server.password') : t('server.privateKey') }}</template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.proxyType"
        property="port"
        show-overflow-tooltip
        :label="t('server.proxyType')"
      >
        <template #default="scope">{{ formatProxyType(scope.row) }}</template>
      </el-table-column>
      <el-table-column v-if="props.columnSettings.expired" property="expired" :label="t('server.expiredAt')" sortable />
      <el-table-column
        v-if="props.columnSettings.consoleUrl"
        property="consoleUrl"
        show-overflow-tooltip
        :label="t('server.consoleUrl')"
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
        :label="t('server.tag')"
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
      <el-table-column :label="t('server.group.actions')" fixed="right" :width="isMobileScreen ? 'auto' : '260px'">
        <template #default="{ row }">
          <el-dropdown v-if="isMobileScreen" trigger="click">
            <span class="link">
              {{ t('server.group.actions') }}
              <el-icon class="el-icon--right">
                <arrow-down />
              </el-icon>
            </span>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item>
                  <el-tooltip
                    :disabled="row.isConfig"
                    effect="dark"
                    :content="t('server.configSshFirst')"
                    placement="left"
                  >
                    <el-button type="success" :disabled="!row.isConfig" @click="handleSSH(row)">{{ t('server.connect') }}</el-button>
                  </el-tooltip>
                </el-dropdown-item>
                <el-dropdown-item>
                  <el-button type="primary" @click="handleUpdate(row)">{{ t('server.config') }}</el-button>
                </el-dropdown-item>
                <el-dropdown-item>
                  <el-button type="danger" @click="handleRemoveHost(row)">{{ t('server.delete') }}</el-button>
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <template v-else>
            <el-tooltip
              :disabled="row.isConfig"
              effect="dark"
              :content="t('server.configSshFirst')"
              placement="left"
            >
              <el-button type="success" :disabled="!row.isConfig" @click="handleSSH(row)">{{ t('server.connect') }}</el-button>
            </el-tooltip>
            <el-button type="primary" @click="handleUpdate(row)">{{ t('server.config') }}</el-button>
            <el-button type="danger" @click="handleRemoveHost(row)">{{ t('server.delete') }}</el-button>
          </template>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { ArrowDown } from '@element-plus/icons-vue'
import useMobileWidth from '@/composables/useMobileWidth'
import clipboard from '@/utils/clipboard'

const { proxy: { $message, $messageBox, $api, $router, $store } } = getCurrentInstance()
const { t } = useI18n()

const props = defineProps({
  hosts: {
    required: true,
    type: Array
  },
  columnSettings: {
    type: Object,
    default: () => ({
      selection: true,
      index: true,
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
  }
})

const emit = defineEmits(['update-list', 'update-host', 'select-change',])

const { isMobileScreen } = useMobileWidth()
const tableRef = ref(null)

const hosts = computed(() => props.hosts)
const hostList = computed(() => $store.hostList)
const proxyList = computed(() => $store.proxyList)

const handleUpdate = (hostInfo) => {
  emit('update-host', hostInfo)
}

const handleToConsole = ({ consoleUrl }) => {
  if (!consoleUrl) return $message({ message: t('server.noConsoleUrl'), type: 'warning', center: true })
  window.open(consoleUrl)
}

const handleSSH = async (row) => {
  let { id, connectType } = row
  $router.push({ path: connectType === 'rdp' ? '/rdp' : '/terminal', query: { hostIds: id } })
}

const defaultSortLocal = localStorage.getItem('host_table_sort')
const defaultSort = ref(defaultSortLocal ? JSON.parse(defaultSortLocal) : { prop: 'index', order: null }) // 'ascending' or 'descending'

const handleSortChange = (sortObj) => {
  defaultSort.value = sortObj
  localStorage.setItem('host_table_sort', JSON.stringify(sortObj))
}

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
  $messageBox.confirm(t('server.deleteInstanceConfirm'), 'Warning', {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
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
  clipboard.copy(host)
}

const formatProxyType = ({ proxyType, jumpHosts, proxyServer }) => {
  if (!proxyType) return t('scripts.noAction')
  if (proxyType === 'jumpHosts' && jumpHosts?.length > 0) {
    const jumpHostsName = jumpHosts.map(item => {
      const hostInfo = hostList.value.find(host => host.id === item)
      return hostInfo?.name || 'Error'
    }).join('>>>')
    return `[${ t('server.jumpHost') }]${ jumpHostsName }`
  }
  if (proxyType === 'proxyServer' && proxyList.value.some(item => item.id === proxyServer)) {
    const proxyServerInfo = proxyList.value.find(item => item.id === proxyServer)
    return `[${ proxyServerInfo.type }]${ proxyServerInfo.name }`
  }
  return t('scripts.noAction')
}
</script>

<style lang="scss" scoped>
.host_card {
  margin: 0px 10px;
  // transition: all 0.5s;
  .no_client_data {
    font-size: 14px;
    font-weight: normal;
    line-height: 23px;
    text-align: center;
    color: var(--el-color-warning);;
  }
  .host_info {
    padding: 0 20px;
  }
}
</style>
