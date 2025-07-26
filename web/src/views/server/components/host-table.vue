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
      <el-table-column type="selection" reserve-selection />
      <el-table-column
        property="index"
        label="序号"
        sortable
        width="100px"
      />
      <el-table-column
        label="名称"
        property="name"
        sortable
        :sort-method="(a, b) => a.name - b.name"
      >
        <template #default="scope">{{ scope.row.name }}</template>
      </el-table-column>
      <el-table-column property="username" label="用户名" />
      <el-table-column property="host" label="IP">
        <template #default="scope">
          <span @click="handleCopy(scope.row.host)">{{ scope.row.host }}</span>
        </template>
      </el-table-column>
      <el-table-column property="port" label="端口" />
      <el-table-column property="port" label="认证类型">
        <template #default="scope">{{ scope.row.authType === 'password' ? '密码' : '密钥' }}</template>
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
import { Download, Upload } from '@element-plus/icons-vue'
import { ArrowDown } from '@element-plus/icons-vue'
import useMobileWidth from '@/composables/useMobileWidth'

const { proxy: { $message, $messageBox, $api, $router, $tools } } = getCurrentInstance()

const props = defineProps({
  hosts: {
    required: true,
    type: Array
  }
})

const emit = defineEmits(['update-list', 'update-host', 'select-change',])

const { isMobileScreen } = useMobileWidth()
let tableRef = ref(null)

let hosts = computed(() => {
  return props.hosts
})

const handleUpdate = (hostInfo) => {
  emit('update-host', hostInfo)
}

const handleToConsole = ({ consoleUrl }) => {
  if (!consoleUrl) return $message({ message: '未配置服务商控制台地址', type: 'warning', center: true })
  window.open(consoleUrl)
}

const handleSSH = async (row) => {
  let { id } = row
  $router.push({ path: '/terminal', query: { hostIds: id } })
}

const handleOnekey = async (row) => {
  let { id, isConfig } = row
  if (!isConfig) {
    $message({
      message: '请先配置SSH连接信息',
      type: 'warning',
      center: true
    })
    handleUpdate(row)
    return
  }
  $router.push({ path: '/onekey', query: { hostIds: id, execClientInstallScript: 'true' } })
}

let defaultSortLocal = localStorage.getItem('host_table_sort')
defaultSortLocal = defaultSortLocal ? JSON.parse(defaultSortLocal) : { prop: 'index', order: null } // 'ascending' or 'descending'
let defaultSort = ref(defaultSortLocal)

const handleSortChange = (sortObj) => {
  defaultSort.value = sortObj
  localStorage.setItem('host_table_sort', JSON.stringify(sortObj))
}

let selectHosts = ref([])
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

defineExpose({
  getSelectHosts,
  clearSelection
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
