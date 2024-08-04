<template>
  <el-card shadow="always" class="host_card">
    <el-table
      ref="tableRef"
      :data="hosts"
      row-key="host"
      @selection-change="handleSelectionChange"
    >
      <el-table-column type="expand">
        <template #default="{ row }">
          <!-- { monitorData: { connect, cpuInfo, memInfo, driveInfo, ipInfo, netstatInfo } } -->
          <el-descriptions
            v-if="row.monitorData?.connect"
            title="实例信息"
            :column="5"
            direction="vertical"
          >
            <el-descriptions-item label="CPU" width="35%">
              {{ `${row.monitorData?.cpuInfo?.cpuModel}-${row.monitorData?.cpuInfo?.cpuCount}-(${row.monitorData?.cpuInfo?.cpuUsage}%)` }}
            </el-descriptions-item>
            <el-descriptions-item label="内存" width="15%">
              {{ `${$tools.toFixed(row.monitorData?.memInfo?.usedMemMb / 1024)}GB / ${$tools.toFixed(row.monitorData?.memInfo?.totalMemMb / 1024)}GB-(${row.monitorData?.memInfo?.usedMemPercentage}%)` }}
            </el-descriptions-item>
            <el-descriptions-item label="硬盘" width="15%">
              {{ `${$tools.toFixed(row.monitorData?.driveInfo?.usedGb)}GB / ${$tools.toFixed(row.monitorData?.driveInfo?.totalGb)}GB-(${row.monitorData?.driveInfo?.usedPercentage}%)` }}
            </el-descriptions-item>
            <el-descriptions-item label="网络" width="15%">
              <el-icon><Upload /></el-icon>
              {{ `${$tools.formatNetSpeed(row.monitorData?.netstatInfo.total?.outputMb)}` }}
              <el-icon><Download /></el-icon>
              {{ `${$tools.formatNetSpeed(row.monitorData?.netstatInfo.total?.inputMb)}` }}
            </el-descriptions-item>
            <el-descriptions-item label="位置" width="20%">
              {{ row.monitorData?.ipInfo.country || '--' }} {{ row.monitorData?.ipInfo.regionName }}
            </el-descriptions-item>
            <el-descriptions-item v-show="row.consoleUrl" label="其他" width="20%">
              <span class="link" @click="handleToConsole(row)">服务商控制台</span>
            </el-descriptions-item>
          </el-descriptions>
          <div v-else class="no_client_data">
            监控客户端未安装，无法获取实时数据。<span class="link" @click="handleOnekey(row)">去安装</span>
          </div>
        </template>
      </el-table-column>
      <el-table-column type="selection" reserve-selection />
      <el-table-column prop="index" label="序号" width="100px" />
      <el-table-column label="名称">
        <template #default="scope">{{ scope.row.name }}</template>
      </el-table-column>
      <el-table-column property="username" label="用户名" />
      <el-table-column property="host" label="IP" />
      <el-table-column property="port" label="端口" />
      <!-- <el-table-column property="port" label="认证类型">
        <template #default="scope">{{ scope.row.authType === 'password' ? '密码' : '密钥' }}</template>
      </el-table-column> -->
      <el-table-column property="isConfig" label="监控服务">
        <template #default="scope">
          <el-tag v-if="scope.row.monitorData?.connect" type="success">已安装</el-tag>
          <el-tag v-else type="warning">未安装</el-tag>
        </template>
      </el-table-column>
      <!-- <el-table-column property="isConfig" label="登录配置" /> -->
      <el-table-column label="操作" width="300px">
        <template #default="{ row }">
          <el-tooltip
            :disabled="row.isConfig"
            effect="dark"
            content="请先配置ssh连接信息"
            placement="left"
          >
            <el-button type="success" :disabled="!row.isConfig" @click="handleSSH(row)">连接终端</el-button>
          </el-tooltip>
          <el-button type="primary" @click="handleUpdate(row)">修改</el-button>
          <el-button type="danger" @click="handleRemoveHost(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
  </el-card>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick, defineExpose } from 'vue'
import { Download, Upload } from '@element-plus/icons-vue'

const { proxy: { $message, $messageBox, $api, $router, $tools } } = getCurrentInstance()

const props = defineProps({
  hosts: {
    required: true,
    type: Array
  }
})

const emit = defineEmits(['update-list', 'update-host', 'select-change',])

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
  let { host } = row
  $router.push({ path: '/terminal', query: { host } })
}

const handleOnekey = async (row) => {
  let { host, isConfig } = row
  if (!isConfig) {
    $message({
      message: '请先配置SSH连接信息',
      type: 'warning',
      center: true
    })
    handleUpdate(row)
    return
  }
  $router.push({ path: '/onekey', query: { host, execClientInstallScript: 'true' } })
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

const handleRemoveHost = async ({ host }) => {
  $messageBox.confirm('确认删除实例', 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    let { data } = await $api.removeHost({ host })
    $message({
      message: data,
      type: 'success',
      center: true
    })
    emit('update-list')
    clearSelection()
  })
}
</script>

<style lang="scss" scoped>
.host_card {
  margin: -10px 30px 0 30px;
  transition: all 0.5s;
  position: relative;

  // &:hover {
  //   box-shadow: 0px 0px 15px rgba(6, 30, 37, 0.5);
  // }

  :deep(.el-descriptions__title) {
    display: none;
  }
  :deep(.el-descriptions) {
    padding: 0 25px;
  }

  .no_client_data {
    font-size: 14px;
    font-weight: normal;
    line-height: 23px;
    text-align: center;
    color: var(--el-color-warning);;
  }
  .link {
    color: var(--el-color-primary);
    cursor: pointer;
  }
}
</style>
