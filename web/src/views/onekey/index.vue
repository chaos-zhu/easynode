<template>
  <div class="onekey_container">
    <div class="header">
      <el-button
        type="primary"
        :disabled="isExecuting"
        :loading="isExecuting"
        @click="addOnekey"
      >
        {{ isExecuting ? `执行中，剩余${timeRemaining}秒` : '批量下发指令' }}
      </el-button>
      <el-button
        v-show="recordList.length"
        :disabled="isExecuting"
        type="danger"
        @click="handleRemoveAll"
      >
        删除全部记录
      </el-button>
    </div>
    <!-- default-expand-all -->
    <el-table
      v-loading="loading"
      :data="tableData"
      row-key="id"
      :expand-row-keys="expandRows"
    >
      <el-table-column type="expand">
        <template #default="{ row }">
          <div class="detail_content_box">
            {{ row.result }}
          </div>
        </template>
      </el-table-column>
      <el-table-column
        prop="name"
        label="实例"
        show-overflow-tooltip
        min-width="120px"
      >
        <template #default="{ row }">
          <span style="letter-spacing: 2px;"> {{ row.name }} </span> -
          <span style="letter-spacing: 2px;"> {{ row.host }} </span> :
          <span style="letter-spacing: 2px;"> {{ row.port }} </span>
        </template>
      </el-table-column>
      <el-table-column
        prop="command"
        label="指令"
        show-overflow-tooltip
        min-width="150px"
      >
        <template #default="{ row }">
          <span> {{ row.command }} </span>
        </template>
      </el-table-column>
      <el-table-column
        prop="status"
        label="执行结果"
        show-overflow-tooltip
        min-width="100px"
      >
        <template #default="{ row }">
          <el-tag :color="getStatusType(row.status)">
            <span style="color: rgb(54, 52, 52);">{{ row.status }}</span>
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" fixed="right" width="90px">
        <template #default="{ row }">
          <el-button
            v-if="!row.pending"
            v-show="row.id !== 'own'"
            :loading="row.loading"
            type="danger"
            @click="handleRemove([row.id])"
          >
            删除
          </el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog
      v-model="formVisible"
      width="600px"
      top="150px"
      title="批量下发指令"
      :close-on-click-modal="false"
      @close="clearFormInfo"
    >
      <el-form
        ref="updateFormRef"
        :model="formData"
        :rules="rules"
        :hide-required-asterisk="true"
        label-suffix="："
        label-width="80px"
        :show-message="false"
      >
        <el-form-item label="实例" prop="hostIds">
          <div class="select_host_wrap">
            <el-select
              v-model="formData.hostIds"
              :teleported="false"
              multiple
              placeholder=""
              class="select"
              clearable
              tag-type="primary"
            >
              <template #header>
                <el-checkbox
                  v-model="checkAll"
                  :indeterminate="indeterminate"
                  @change="selectAllHost"
                >
                  全选 <span class="tips">(未配置ssh连接信息的实例不会显示在列表中)</span>
                </el-checkbox>
              </template>
              <el-option
                v-for="item in hasConfigHostList"
                :key="item.id"
                :label="item.name"
                :value="item.id"
              />
            </el-select>
            <!-- <el-button type="primary" class="btn" @click="selectAllHost">全选</el-button> -->
          </div>
        </el-form-item>
        <el-form-item prop="command" label="指令">
          <div class="command_wrap">
            <el-dropdown
              trigger="click"
              max-height="50vh"
              :teleported="false"
              class="scripts_menu"
            >
              <span class="link_text">从脚本库导入...<el-icon><arrow-down /></el-icon></span>
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item v-for="item in scriptList" :key="item.id" @click="handleImportScript(item)">
                    <span>{{ item.name }}</span>
                  </el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
            <el-input
              v-model="formData.command"
              class="input"
              type="textarea"
              :rows="5"
              clearable
              autocomplete="off"
              placeholder="shell script, ex: ping -c 10 google.com"
            />
          </div>
        </el-form-item>
        <el-form-item prop="timeout" label="超时(s)">
          <el-input
            v-model.trim.number="formData.timeout"
            type="number"
            clearable
            autocomplete="off"
            placeholder="指令执行超时时间，单位秒，超时自动中断"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <span>
          <el-button @click="formVisible = false">取消</el-button>
          <el-button type="primary" @click="execOnekey">执行</el-button>
        </span>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, computed, watch, nextTick, getCurrentInstance, onActivated } from 'vue'
import { ArrowDown } from '@element-plus/icons-vue'
import socketIo from 'socket.io-client'
import { useRoute } from 'vue-router'

const { io } = socketIo

const { proxy: { $api, $notification,$messageBox, $message, $router, $serviceURI, $store } } = getCurrentInstance()
const route = useRoute()

const loading = ref(false)
const formVisible = ref(false)
const socket = ref(null)
let recordList = ref([])
let pendingRecord = ref([])
let checkAll = ref(false)
let indeterminate = ref(false)
const updateFormRef = ref(null)
let timeRemaining = ref(0)
const isClient = ref(false)

let formData = reactive({
  hostIds: [],
  command: '',
  timeout: 120
})

const token = computed(() => $store.token)
const hostList = computed(() => $store.hostList)
let scriptList = computed(() => $store.scriptList)
let isExecuting = computed(() => timeRemaining.value > 0)
const hasConfigHostList = computed(() => hostList.value.filter(item => item.isConfig))

const tableData = computed(() => {
  return pendingRecord.value.concat(recordList.value).map(item => {
    item.loading = false
    return item
  })
})
const expandRows = computed(() => {
  let rows = tableData.value.filter(item => item.pending).map(item => item.id)
  return rows
})

const rules = computed(() => {
  return {
    hostIds: { required: true, trigger: 'change' },
    command: { required: true, trigger: 'change' },
    timeout: { required: true, type: 'number', trigger: 'change' }
  }
})

watch(() => formData.hostIds, (val) => {
  if (val.length === 0) {
    checkAll.value = false
    indeterminate.value = false
  } else if (val.length === hasConfigHostList.value.length) {
    checkAll.value = true
    indeterminate.value = false
  } else {
    indeterminate.value = true
  }
})

const createExecShell = (hostIds = [], command = 'ls', timeout = 60) => {
  loading.value = true
  timeRemaining.value = Number(formData.timeout)
  let timer = null
  socket.value = io($serviceURI, {
    path: '/onekey',
    forceNew: false,
    reconnectionAttempts: 1
  })
  socket.value.on('connect', () => {
    timer = setInterval(() => {
      timeRemaining.value -= 1
    }, 1000)
    console.log('onekey socket已连接：', socket.value.id)

    socket.value.on('ready', () => {
      pendingRecord.value = [] // 每轮执行前清空
    })

    socket.value.emit('create', { hostIds, token: token.value, command, timeout })

    socket.value.on('output', (result) => {
      loading.value = false
      if (Array.isArray(result) && result.length > 0) {
        // console.log('output', result)
        result = result.map(item => ({ ...item, pending: true }))
        pendingRecord.value = result
        nextTick(() => {
          document.querySelectorAll('.detail_content_box').forEach(container => {
            container.scrollTop = container.scrollHeight
          })
        })
      }
    })

    socket.value.on('timeout', ({ reason, result }) => {
      $notification({
        title: '批量指令执行超时',
        message: reason,
        type: 'error'
      })
      if (Array.isArray(result) && result.length > 0) {
        // console.log('output', result)
        result = result.map(item => ({ ...item, pending: true }))
        pendingRecord.value = result
      }
    })
    socket.value.on('create_fail', (reason) => {
      $notification({
        title: '批量指令执行失败',
        message: reason,
        type: 'error'
      })
    })

    socket.value.on('token_verify_fail', () => {
      $message.error('token验证失败，请重新登录')
      $router.push('/login')
    })

    socket.value.on('exec_complete', () => {
      $notification({
        title: '批量指令执行完成',
        message: '执行完成',
        type: 'success'
      })
    })
  })

  socket.value.on('disconnect', () => {
    loading.value = false
    timeRemaining.value = 0
    if (isClient.value) $store.getHostList() // 如果是客户端安装/卸载脚本，更新下host
    isClient.value = false
    clearInterval(timer)
    console.warn('onekey websocket 连接断开')
  })

  socket.value.on('connect_error', (err) => {
    loading.value = false
    console.error('onekey websocket 连接错误：', err)
    $notification({
      title: 'onekey websocket 连接错误：',
      message: '请检查socket服务是否正常',
      type: 'error'
    })
  })
}

onMounted(async () => {
  getOnekeyRecord()
})

let selectAllHost = (val) => {
  indeterminate.value = false
  if (val) {
    formData.hostIds = hasConfigHostList.value.map(item => item.id)
  } else {
    formData.hostIds = []
  }
}

let handleImportScript = (scriptObj) => {
  isClient.value = scriptObj.id.startsWith('client')
  formData.command = scriptObj.command
}

let getStatusType = (status) => {
  switch (status) {
    case '连接中':
      return '#FFDEAD'
    case '连接失败':
      return '#FFCCCC'
    case '执行中':
      return '#ADD8E6'
    case '执行成功':
      return '#90EE90'
    case '执行失败':
      return '#FFCCCC'
    case '执行超时':
      return '#FFFFE0'
    case '执行中断':
      return '#E6E6FA'
    default:
      return 'info'
  }
}

let getOnekeyRecord = async () => {
  loading.value = true
  let { data } = await $api.getOnekeyRecord()
  recordList.value = data
  loading.value = false
}

let addOnekey = () => {
  formVisible.value = true
}

function execOnekey() {
  updateFormRef.value.validate()
    .then(async () => {
      let { hostIds, command, timeout } = formData
      timeout = Number(timeout)
      if (timeout < 1) {
        return $message.error('超时时间不能小于1秒')
      }
      if (hostIds.length === 0) {
        return $message.error('请选择主机')
      }
      await getOnekeyRecord() // 获取新纪录前会清空 pendingRecord，所以需要获取一次最新的list
      createExecShell(hostIds, command, timeout)
      formVisible.value = false
    })
}

const clearFormInfo = () => {
  nextTick(() => updateFormRef.value.resetFields())
}

const handleRemove = async (ids = []) => {
  tableData.value.filter(item => ids.includes(item.id)).forEach(item => item.loading = true)
  await $api.deleteOnekeyRecord(ids)
  await getOnekeyRecord()
  $message.success('success')
}

const handleRemoveAll = async () => {
  $messageBox.confirm(`确认删除所有执行记录：${ name }`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  })
    .then(async () => {
      await $api.deleteOnekeyRecord('ALL')
      pendingRecord.value = []
      await getOnekeyRecord()
      $message.success('success')
    })
}

onActivated(async () => {
  await nextTick()
  const { hostIds, execClientInstallScript } = route.query
  if (!hostIds) return
  if (execClientInstallScript === 'true') {
    let clientInstallScript = 'curl -o- https://ghfast.top/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-install.sh | bash\n'
    console.log(hostIds.split(','))
    createExecShell(hostIds.split(','), clientInstallScript, 300)
    // $messageBox.confirm(`准备安装客户端服务监控应用：${ host }`, 'Warning', {
    //   confirmButtonText: '确定',
    //   cancelButtonText: '取消',
    //   type: 'warning'
    // })
    //   .then(async () => {
    //     let clientInstallScript = 'curl -o- https://ghfast.top/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-install.sh | bash\n'
    //     createExecShell([host,], clientInstallScript, 300)
    //   })
  }
})
</script>

<style lang="scss" scoped>
.onekey_container {
  padding: 20px;
  .header {
    padding: 15px;
    display: flex;
    align-items: center;
    justify-content: end;
    position: sticky;
    top: 0;
    z-index: 1;
  }
  .detail_content_box {
    max-height: 200px;
    overflow: auto;
    white-space: pre-line;
    line-height: 1.1;
    // background: rgba(227, 230, 235, .7);
    padding: 25px;
    border-radius: 3px;
  }
  .select_host_wrap {
    width: 100%;
    display: flex;
    .select {
      flex: 1;
      margin-right: 15px;
      .tips {
        color: #999;
        font-size: 12px;
      }
    }
    .btn {
      width: 52px;
    }
  }
  .command_wrap {
    width: 100%;
    padding-top: 8px;
    display: flex;
    flex-direction: column;
    .scripts_menu {
      :deep(.el-dropdown-menu) {
        min-width: 120px;
        max-width: 300px;
      }
    }
    .link_text {
      font-size: var(--el-font-size-base);
      // color: var(--el-text-color-regular);
      color: var(--el-color-primary);
      cursor: pointer;
      margin-right: 15px;
      user-select: none;
    }
    .input {
      margin-top: 10px;
    }
  }
}
</style>