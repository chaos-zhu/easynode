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
        label="序号"
        sortable
        width="100px"
      />
      <el-table-column
        v-if="props.columnSettings.name"
        label="名称"
        property="name"
        sortable
        :sort-method="(a, b) => a.name - b.name"
      >
        <template #default="scope">{{ scope.row.name }}</template>
      </el-table-column>
      <el-table-column v-if="props.columnSettings.username" property="username" label="用户名" />
      <el-table-column v-if="props.columnSettings.host" property="host" label="IP">
        <template #default="scope">
          <span @click="handleCopy(scope.row.host)">{{ scope.row.host }}</span>
        </template>
      </el-table-column>
      <el-table-column v-if="props.columnSettings.port" property="port" label="端口" />
      <el-table-column v-if="props.columnSettings.authType" property="port" label="认证类型">
        <template #default="scope">{{ scope.row.authType === 'password' ? '密码' : '密钥' }}</template>
      </el-table-column>
      <el-table-column
        v-if="props.columnSettings.proxyType"
        property="port"
        show-overflow-tooltip
        label="代理类型"
      >
        <template #default="scope">{{ formatProxyType(scope.row) }}</template>
      </el-table-column>
      <el-table-column v-if="props.columnSettings.expired" property="expired" label="到期时间" />
      <el-table-column
        v-if="props.columnSettings.consoleUrl"
        property="consoleUrl"
        show-overflow-tooltip
        label="控制台URL"
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
      <el-table-column label="操作" fixed="right" :width="isMobileScreen ? 'auto' : '260px'">
        <template #default="{ row }">
          <el-dropdown v-if="isMobileScreen" trigger="click">
            <span class="link">
              操作
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
                    content="请先配置ssh连接信息"
                    placement="left"
                  >
                    <el-button type="success" :disabled="!row.isConfig" @click="handleSSH(row)">连接</el-button>
                  </el-tooltip>
                </el-dropdown-item>
                <el-dropdown-item>
                  <el-button type="primary" @click="handleUpdate(row)">配置</el-button>
                </el-dropdown-item>
                <el-dropdown-item>
                  <el-button type="danger" @click="handleRemoveHost(row)">删除</el-button>
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <template v-else>
            <el-tooltip
              :disabled="row.isConfig"
              effect="dark"
              content="请先配置ssh连接信息"
              placement="left"
            >
              <el-button type="success" :disabled="!row.isConfig" @click="handleSSH(row)">连接</el-button>
            </el-tooltip>
            <el-button type="primary" @click="handleUpdate(row)">配置</el-button>
            <el-button type="danger" @click="handleRemoveHost(row)">删除</el-button>
          </template>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick } from 'vue'
import { ArrowDown } from '@element-plus/icons-vue'
import useMobileWidth from '@/composables/useMobileWidth'

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
  if (!consoleUrl) return $message({ message: '未配置服务商控制台地址', type: 'warning', center: true })
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

defineExpose({
  getSelectHosts,
  clearSelection,
  selectAll
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

const handleCopy = async (host) => {
  await navigator.clipboard.writeText(host)
  $message.success({ message: '复制成功', center: true })
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
