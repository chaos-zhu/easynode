<template>
  <el-card shadow="always" class="host_card">
    <el-table
      ref="tableRef"
      :data="hosts"
      @select="handleSelectionChange"
      @select-all="handleSelectionChange"
    >
      <el-table-column type="selection" />
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
          <el-tag v-if="scope.row.connect || scope.row.monitorData?.connect" type="success">已安装</el-tag>
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
import { ref, computed, getCurrentInstance, nextTick, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'

const { proxy: { $api, $router, $tools } } = getCurrentInstance()

const props = defineProps({
  hosts: {
    required: true,
    type: Array
  },
  hiddenIp: {
    required: true,
    type: [Number, Boolean,]
  }
})

const emit = defineEmits(['update-list', 'update-host', 'select-change',])

let tableRef = ref(null)

const hostInfo = computed(() => props.hostInfo || {})
// const host = computed(() => hostInfo.value?.host)
const name = computed(() => hostInfo.value?.name)
const ping = computed(() => hostInfo.value?.ping || '')
const expiredTime = computed(() => $tools.formatTimestamp(hostInfo.value?.expired, 'date'))
const consoleUrl = computed(() => hostInfo.value?.consoleUrl)
const ipInfo = computed(() => hostInfo.value?.ipInfo || {})
const isError = computed(() => !Boolean(hostInfo.value?.osInfo))
const cpuInfo = computed(() => hostInfo.value?.cpuInfo || {})
const memInfo = computed(() => hostInfo.value?.memInfo || {})
const osInfo = computed(() => hostInfo.value?.osInfo || {})
const driveInfo = computed(() => hostInfo.value?.driveInfo || {})
const netstatInfo = computed(() => {
  let { total: netTotal, ...netCards } = hostInfo.value?.netstatInfo || {}
  return { netTotal, netCards: netCards || {} }
})
const openedCount = computed(() => hostInfo.value?.openedCount || 0)

const setColor = (num) => {
  num = Number(num)
  return num ? (num < 80 ? '#595959' : (num >= 80 && num < 90 ? '#FF6600' : '#FF0000')) : '#595959'
}

const handleUpdate = (hostInfo) => {
  emit('update-host', hostInfo)
}

const handleToConsole = () => {
  window.open(consoleUrl.value)
}

const handleSSH = async ({ host }) => {
  // if (!hostInfo?.isConfig) {
  //   ElMessage({
  //     message: '请先配置SSH连接信息',
  //     type: 'warning',
  //     center: true
  //   })
  //   handleUpdate()
  //   return
  // }
  $router.push({ path: '/terminal', query: { host } })
}

let selectHosts = ref([])
// 由于table数据内部字段更新后table组件会自动取消勾选,所以这里需要手动set勾选
watch(() => props.hosts, () => {
  // console.log('hosts change')
  nextTick(() => {
    selectHosts.value.forEach(row => {
      tableRef.value.toggleRowSelection && tableRef.value.toggleRowSelection(row, true)
    })
  })
}, { immediate: true, deep: true })

const handleSelectionChange = (val) => {
  // console.log('select: ', val)
  selectHosts.value = val
  emit('select-change', val)
}

const handleRemoveHost = async ({ host }) => {
  ElMessageBox.confirm('确认删除实例', 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    let { data } = await $api.removeHost({ host })
    ElMessage({
      message: data,
      type: 'success',
      center: true
    })
    emit('update-list')
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

  .host-state {
    position: absolute;
    top: 0px;
    left: 0px;

    span {
      font-size: 10px;
      // transform: rotate(-45deg);
      // transform: scale(0.95);
      display: inline-block;
      padding: 3px 5px;
    }

    .online {
      color: #009933;
      background-color: #e8fff3;
    }

    .offline {
      color: #FF0033;
      background-color: #fff5f8;
    }
  }

  .info {
    display: flex;
    align-items: center;
    height: 50px;

    &>div {
      flex: 1
    }

    .field {
      height: 100%;
      display: flex;
      align-items: center;

      .svg-icon {
        width: 25px;
        height: 25px;
        color: #1989fa;
        cursor: pointer;
      }

      .fields {
        display: flex;
        flex-direction: column;

        // justify-content: center;
        span {
          padding: 3px 0;
          margin-left: 5px;
          font-weight: 600;
          font-size: 13px;
          color: #595959;
        }

        .name {
          display: inline-block;
          height: 19px;
          cursor: pointer;

          &:hover {
            text-decoration-line: underline;
            text-decoration-color: #1989fa;

            .svg-icon {
              display: inline-block;
            }
          }

          .svg-icon {
            display: none;
            width: 13px;
            height: 13px;
          }
        }
      }
    }

    .actions {
      .actions-icon {
        margin: 0 10px;
        width: 16px;
        height: 16px;
        color: #1989fa;
        cursor: pointer;
      }
    }

    .web-ssh {

      // ::v-deep has been deprecated. Use :deep(<inner-selector>) instead.
      :deep(.el-dropdown__caret-button) {
        margin-left: -5px;
      }
    }
  }
}
</style>

<style lang="scss">
.field-detail {
  display: flex;
  flex-direction: column;

  h2 {
    font-weight: 600;
    font-size: 16px;
    margin: 0px 0 8px 0;
  }

  h3 {
    span {
      font-weight: 600;
      color: #797979;
    }
  }

  span {
    display: inline-block;
    margin: 4px 0;
  }
}
</style>
