<template>
  <div class="onekey_container data_page">
    <div class="data_page_toolbar">
      <span v-if="pendingRecord.length" class="data_page_summary">当前批次 {{ pendingRecord.length }} 条</span>
      <div class="toolbar_actions">
        <el-button
          v-if="!isExecuting"
          type="primary"
          :icon="Promotion"
          @click="addOnekey"
        >
          执行指令
        </el-button>
        <el-button
          v-else
          type="danger"
          :icon="VideoPause"
          :loading="stoppingAll"
          @click="stopAll"
        >
          {{ stoppingAll ? '停止中' : `停止执行（剩余 ${ timeRemaining } 秒）` }}
        </el-button>
        <el-dropdown v-if="tableData.length || historyTotal" trigger="click">
          <el-button
            class="compact_more_btn"
            :icon="MoreFilled"
            aria-label="更多操作"
            title="更多操作"
          />
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item :disabled="!tableData.length" @click="setPageExpanded(!hasExpandedRows)">
                {{ hasExpandedRows ? '折叠本页' : '展开本页' }}
              </el-dropdown-item>
              <el-dropdown-item
                v-if="historyTotal"
                :icon="Delete"
                :disabled="isExecuting"
                divided
                @click="handleRemoveAll"
              >
                删除全部记录
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
    </div>
    <div class="onekey_table_wrap data_table_wrap">
      <el-table
        ref="recordTableRef"
        v-loading="loading"
        :data="tableData"
        height="100%"
        :row-key="getRecordKey"
        :expand-row-keys="expandRows"
        empty-text="暂无执行记录"
        @expand-change="handleExpandChange"
      >
        <el-table-column type="expand" width="48">
          <template #default="{ row }">
            <div
              :ref="element => setOutputContainer(element, getRecordKey(row))"
              v-loading="outputDetails.get(getRecordKey(row))?.loading"
              class="detail_content_box"
              @scroll.passive="handleOutputScroll($event, getRecordKey(row))"
            >
              <div class="output_text">{{ getOutputText(row) }}</div>
              <div v-if="!row.pending && outputDetails.get(getRecordKey(row))?.error" class="output_actions">
                <el-button link type="primary" @click="loadRecordOutput(row, true)">重试加载</el-button>
              </div>
              <div v-else-if="!row.pending && outputDetails.get(getRecordKey(row))?.hasMore" class="output_actions">
                <el-button link type="primary" @click="loadRecordOutput(row, true)">加载更多输出</el-button>
              </div>
            </div>
          </template>
        </el-table-column>
        <el-table-column
          prop="name"
          label="实例"
          show-overflow-tooltip
          min-width="190px"
        >
          <template #default="{ row }">
            <div class="instance_cell">
              <strong>{{ row.name }}</strong>
              <small>{{ row.host }}:{{ row.port }}</small>
            </div>
          </template>
        </el-table-column>
        <el-table-column
          prop="command"
          label="指令"
          show-overflow-tooltip
          min-width="220px"
        >
          <template #default="{ row }">
            <code class="command_cell">{{ row.command }}</code>
          </template>
        </el-table-column>
        <el-table-column
          prop="startDate"
          label="开始时间"
          show-overflow-tooltip
          min-width="170px"
        >
          <template #default="{ row }">
            <span>{{ $tools.formatTimestamp(row.startDate) }}</span>
          </template>
        </el-table-column>
        <el-table-column
          prop="endDate"
          label="结束时间"
          show-overflow-tooltip
          min-width="170px"
        >
          <template #default="{ row }">
            <span>{{ row.endDate ? $tools.formatTimestamp(row.endDate) : '--' }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="执行结果" min-width="110px">
          <template #default="{ row }">
            <el-tag :type="getStatusType(row.status)" effect="light" round>
              {{ row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column
          label="操作"
          fixed="right"
          width="96px"
          align="right"
          header-align="right"
        >
          <template #default="{ row }">
            <el-button
              v-if="canStopHost(row)"
              :loading="isHostStopping(row.hostId)"
              text
              type="danger"
              @click="stopHost(row)"
            >
              停止
            </el-button>
            <el-button
              v-else-if="!row.pending && row.id !== 'own'"
              :loading="row.loading"
              text
              type="danger"
              @click="handleRemove([row.id])"
            >
              删除
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </div>
    <div class="onekey_pagination">
      <el-pagination
        v-model:current-page="currentPage"
        v-model:page-size="pageSize"
        :total="historyTotal"
        :page-sizes="[20, 50, 100]"
        layout="total, sizes, prev, pager, next"
        @size-change="currentPage = 1"
      />
    </div>
    <el-dialog
      v-model="formVisible"
      width="600px"
      top="6vh"
      class="management_dialog onekey_form_dialog"
      title="批量下发指令"
      :close-on-click-modal="false"
      @close="clearFormInfo"
    >
      <template #header>
        <div class="management_dialog_title">批量下发指令</div>
      </template>
      <el-form
        ref="updateFormRef"
        :model="formData"
        :rules="rules"
        :hide-required-asterisk="true"
        label-position="top"
        :show-message="false"
        class="management_form"
      >
        <el-form-item label="实例" prop="hostIds">
          <div class="select_host_wrap">
            <el-select
              v-model="formData.hostIds"
              :teleported="false"
              multiple
              placeholder="选择要执行指令的实例"
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
                  全选 <span class="tips">仅显示已配置 SSH 连接的实例</span>
                </el-checkbox>
              </template>
              <el-option
                v-for="item in hasConfigHostList"
                :key="item.id"
                :label="item.name"
                :value="item.id"
              />
            </el-select>
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
              <span class="link_text">从脚本库导入<el-icon><ArrowDown /></el-icon></span>
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
              placeholder="输入 Shell 指令，例如：ping -c 10 google.com"
            />
          </div>
        </el-form-item>
        <el-form-item prop="timeout" label="超时时间（秒）">
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
        <el-button @click="formVisible = false">取消</el-button>
        <el-button type="primary" @click="execOnekey">开始执行</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, onBeforeUnmount, computed, watch, nextTick, getCurrentInstance } from 'vue'
import { ArrowDown, Delete, MoreFilled, Promotion, VideoPause } from '@element-plus/icons-vue'
import { generateSocketInstance } from '@/utils'

const { proxy: { $api, $notification, $messageBox, $message, $store, $tools } } = getCurrentInstance()

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
const executionState = ref('idle')
const stoppingAll = ref(false)
const stoppingHostIds = ref(new Set())
const recordTableRef = ref(null)
const currentPage = ref(1)
const pageSize = ref(20)
const historyTotal = ref(0)
const expandedRecordState = reactive(new Map())
const outputDetails = reactive(new Map())
let activeOutputLoads = 0
let historyRequestId = 0
let loadedPage = 0
let loadedPageSize = 0
let disposed = false
const outputContainers = new Map()
const outputFollowState = new Map()
const OUTPUT_BOTTOM_THRESHOLD = 20

let formData = reactive({
  hostIds: [],
  command: '',
  timeout: 120
})

const token = computed(() => $store.token)
const hostList = computed(() => $store.hostList)
let scriptList = computed(() => $store.scriptList)
let isExecuting = computed(() => executionState.value !== 'idle')
const hasConfigHostList = computed(() => hostList.value.filter(item => item.isConfig))

const tableData = computed(() => pendingRecord.value.concat(recordList.value))
// 同一批次的记录落库后会获得 id，使用批次和主机保持实时记录与历史记录的身份一致。
const getRecordKey = row => row.batchId && row.hostId
  ? `batch-${ row.batchId }-${ row.hostId }`
  : row.id || `pending-${ row.startDate }-${ row.hostId }`
const expandRows = computed(() => tableData.value
  .filter(row => expandedRecordState.get(getRecordKey(row)) ?? row.pending)
  .map(getRecordKey))
const hasExpandedRows = computed(() => expandRows.value.length > 0)

const handleExpandChange = (row, expandedRows) => {
  const key = getRecordKey(row)
  expandedRecordState.set(key, expandedRows.some(item => getRecordKey(item) === key))
}

const setPageExpanded = expanded => {
  tableData.value.forEach(row => expandedRecordState.set(getRecordKey(row), expanded))
}

watch([currentPage, pageSize,], async () => {
  await nextTick()
  recordTableRef.value?.setScrollTop(0)
  if (currentPage.value !== loadedPage || pageSize.value !== loadedPageSize) getOnekeyRecord()
})

const getOutputText = row => {
  if (row.pending) return row.result || '暂无输出'
  const detail = outputDetails.get(getRecordKey(row))
  return detail?.result || (detail?.loading ? '加载中…' : detail?.error ? '输出加载失败' : '暂无输出')
}

const loadRecordOutput = async (row, append = false) => {
  const key = getRecordKey(row)
  if (!recordList.value.some(item => getRecordKey(item) === key)) return
  if (!outputDetails.has(key)) {
    outputDetails.set(key, { result: '', loading: false, error: false, nextOffset: 0, hasMore: false })
  }
  const detail = outputDetails.get(key)
  if (detail.loading) return
  detail.loading = true
  detail.error = false
  try {
    const { data } = await $api.getOnekeyRecordOutput(row.id, { offset: append ? detail.nextOffset : 0 })
    if (outputDetails.get(key) !== detail) return
    detail.result = append ? detail.result + data.result : data.result
    detail.nextOffset = data.nextOffset
    detail.hasMore = data.hasMore
  } catch {
    if (outputDetails.get(key) === detail) detail.error = true
  } finally {
    detail.loading = false
  }
}

const loadExpandedOutputs = () => {
  if (disposed) return
  const expanded = new Set(expandRows.value)
  const missing = recordList.value.filter(row => expanded.has(getRecordKey(row)) && !outputDetails.has(getRecordKey(row)))
  // 批量展开时限制并发；翻页后丢弃上一页的输出缓存和迟到的响应。
  while (activeOutputLoads < 4 && missing.length) {
    activeOutputLoads++
    loadRecordOutput(missing.shift()).finally(() => {
      activeOutputLoads--
      loadExpandedOutputs()
    })
  }
}

watch([expandRows, recordList,], loadExpandedOutputs, { flush: 'post' })

const setOutputContainer = (element, recordKey) => {
  if (element) outputContainers.set(recordKey, element)
  else outputContainers.delete(recordKey)
}

const handleOutputScroll = (event, recordKey) => {
  const container = event.currentTarget
  const distanceToBottom = container.scrollHeight - container.scrollTop - container.clientHeight
  outputFollowState.set(recordKey, distanceToBottom <= OUTPUT_BOTTOM_THRESHOLD)
}

const scrollFollowingOutputs = (rows) => {
  rows.forEach(row => {
    const recordKey = getRecordKey(row)
    if (outputFollowState.get(recordKey) === false) return
    const container = outputContainers.get(recordKey)
    if (container) container.scrollTop = container.scrollHeight
  })
}

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
  currentPage.value = 1
  loading.value = true
  executionState.value = 'running'
  stoppingAll.value = false
  stoppingHostIds.value = new Set()
  timeRemaining.value = Number(timeout)
  let timer = null
  let terminalEventReceived = false
  const execSocket = generateSocketInstance('/onekey', { forceNew: true, reconnection: false })
  socket.value = execSocket

  execSocket.on('connect', () => {
    timer = setInterval(() => {
      timeRemaining.value = Math.max(0, timeRemaining.value - 1)
    }, 1000)
    console.log('onekey socket已连接：', execSocket.id)
    execSocket.emit('ws_onekey', { hostIds, token: token.value, command, timeout })
  })

  execSocket.on('ready', () => {
    loading.value = false
    outputFollowState.clear()
    pendingRecord.value = [] // 每轮执行前清空
  })

  execSocket.on('output', (result) => {
    loading.value = false
    if (Array.isArray(result) && result.length > 0) {
      const nextPendingRecord = result.map(item => ({ ...item, pending: true }))
      nextPendingRecord.forEach(row => {
        const key = getRecordKey(row)
        if (!expandedRecordState.has(key)) expandedRecordState.set(key, true)
      })
      pendingRecord.value = nextPendingRecord
      nextTick(() => {
        scrollFollowingOutputs(nextPendingRecord)
      })
    }
  })

  execSocket.on('stop_result', async ({ ok, scope, hostId, persisted = true, message }) => {
    if (scope === 'host') {
      const nextStoppingIds = new Set(stoppingHostIds.value)
      nextStoppingIds.delete(hostId)
      stoppingHostIds.value = nextStoppingIds
      if (ok) $message.success(message)
      else $message.error(message)
      return
    }

    terminalEventReceived = ok
    stoppingAll.value = false
    if (!ok) {
      executionState.value = execSocket.connected ? 'running' : 'idle'
      $message.error(message)
      return
    }

    executionState.value = 'idle'
    await getOnekeyRecord()
    $notification({
      title: '批量指令已停止',
      message,
      type: persisted ? 'warning' : 'error'
    })
  })

  execSocket.on('create_fail', (message) => {
    terminalEventReceived = true
    executionState.value = 'idle'
    loading.value = false
    $notification({
      title: '批量指令创建失败',
      message,
      type: 'error'
    })
  })

  execSocket.on('exec_timeout', ({ reason }) => {
    terminalEventReceived = true
    executionState.value = 'idle'
    $notification({
      title: '批量指令执行超时',
      message: reason,
      type: 'error'
    })
    getOnekeyRecord()
  })

  execSocket.on('exec_complete', () => {
    terminalEventReceived = true
    executionState.value = 'idle'
    $notification({
      title: '批量指令执行完成',
      message: '执行完成',
      type: 'success'
    })
    getOnekeyRecord()
  })

  execSocket.on('disconnect', () => {
    const shouldRefresh = !terminalEventReceived && executionState.value !== 'idle'
    loading.value = false
    executionState.value = 'idle'
    stoppingAll.value = false
    stoppingHostIds.value = new Set()
    timeRemaining.value = 0
    if (isClient.value) $store.getHostCatalog() // 如果是客户端安装/卸载脚本，更新下host
    isClient.value = false
    clearInterval(timer)
    if (shouldRefresh) setTimeout(() => getOnekeyRecord(), 250)
    console.warn('onekey websocket 连接断开')
  })

  execSocket.on('connect_error', (err) => {
    loading.value = false
    executionState.value = 'idle'
    stoppingAll.value = false
    clearInterval(timer)
    console.error('onekey websocket 连接错误：', err)
    $notification({
      title: 'onekey websocket 连接错误：',
      message: '请检查socket服务是否正常',
      type: 'error'
    })
  })
}

const canStopHost = row => {
  return row.pending && row.hostId && !stoppingAll.value && ['连接中', '执行中',].includes(row.status)
}

const isHostStopping = hostId => stoppingHostIds.value.has(hostId)

const stopHost = row => {
  if (!canStopHost(row) || isHostStopping(row.hostId)) return
  if (!socket.value?.connected) return $message.error('onekey websocket 已断开')
  stoppingHostIds.value = new Set([...stoppingHostIds.value, row.hostId,])
  socket.value.emit('ws_onekey_stop', { scope: 'host', hostId: row.hostId })
}

const stopAll = async () => {
  try {
    await $messageBox.confirm(
      '停止后，未完成的实例将标记为“执行中断”，是否继续？',
      '停止批量指令',
      {
        confirmButtonText: '停止执行',
        cancelButtonText: '取消',
        confirmButtonClass: 'el-button--danger',
        type: 'warning'
      }
    )
  } catch {
    return
  }

  if (!socket.value?.connected) {
    socket.value?.disconnect()
    executionState.value = 'idle'
    loading.value = false
    timeRemaining.value = 0
    return $message.warning('批量任务尚未建立连接，已取消执行')
  }

  stoppingAll.value = true
  executionState.value = 'stopping'
  socket.value.emit('ws_onekey_stop', { scope: 'all' })
}

onMounted(async () => {
  getOnekeyRecord()
})

onBeforeUnmount(() => {
  disposed = true
  historyRequestId++
  outputDetails.clear()
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
      return 'warning'
    case '连接失败':
      return 'danger'
    case '执行中':
      return 'primary'
    case '执行成功':
      return 'success'
    case '执行失败':
      return 'danger'
    case '执行超时':
      return 'warning'
    case '执行中断':
      return 'info'
    default:
      return 'info'
  }
}

let getOnekeyRecord = async ({ page = currentPage.value } = {}) => {
  const requestId = ++historyRequestId
  loading.value = true
  try {
    const { data } = await $api.getOnekeyRecord({ page, pageSize: pageSize.value })
    if (requestId !== historyRequestId) return false
    loadedPage = data.page
    loadedPageSize = data.pageSize
    currentPage.value = data.page
    historyTotal.value = data.total
    recordList.value = data.items
    if (!isExecuting.value) pendingRecord.value = []
    const recordKeys = new Set(tableData.value.map(getRecordKey))
    for (const state of [outputDetails, outputFollowState, outputContainers,]) {
      for (const key of state.keys()) {
        if (!recordKeys.has(key)) state.delete(key)
      }
    }
    if (!data.total) {
      for (const key of expandedRecordState.keys()) {
        if (!recordKeys.has(key)) expandedRecordState.delete(key)
      }
    }
    return true
  } catch {
    if (requestId === historyRequestId) $message.error('加载执行记录失败，请重试')
    return false
  } finally {
    if (requestId === historyRequestId) loading.value = false
  }
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
      if (!await getOnekeyRecord({ page: 1 })) return
      createExecShell(hostIds, command, timeout)
      formVisible.value = false
    })
}

const clearFormInfo = () => {
  nextTick(() => updateFormRef.value.resetFields())
}

const handleRemove = async (ids = []) => {
  const removedRows = recordList.value.filter(item => ids.includes(item.id))
  removedRows.forEach(item => item.loading = true)
  await $api.deleteOnekeyRecord(ids)
  removedRows.forEach(row => expandedRecordState.delete(getRecordKey(row)))
  await getOnekeyRecord()
  $message.success('success')
}

const handleRemoveAll = async () => {
  $messageBox.confirm('确认删除所有执行记录？', 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  })
    .then(async () => {
      await $api.deleteOnekeyRecord('ALL')
      expandedRecordState.clear()
      outputDetails.clear()
      pendingRecord.value = []
      await getOnekeyRecord()
      $message.success('success')
    })
}

</script>

<style lang="scss" scoped>
.onekey_container {
  overflow: hidden;

  .onekey_table_wrap {
    min-height: 0;
    flex: 1;
  }

  .onekey_pagination {
    display: flex;
    justify-content: flex-end;
    flex: 0 0 auto;
    margin-top: 14px;
  }

  .instance_cell {
    min-width: 0;
    display: grid;
    gap: 3px;

    strong {
      overflow: hidden;
      color: var(--el-text-color-primary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      overflow: hidden;
      color: var(--el-text-color-secondary);
      font-size: 12px;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  .command_cell {
    padding: 3px 6px;
    border-radius: 5px;
    background: var(--el-fill-color-light);
    color: var(--el-text-color-primary);
    font-family: var(--el-font-family-monospace, monospace);
    font-size: 12px;
  }

  .detail_content_box {
    max-height: 260px;
    margin: 2px 14px 8px 50px;
    padding: 14px 16px;
    overflow: auto;
    border: 1px solid var(--el-border-color-light);
    border-radius: 8px;
    background: var(--el-fill-color-extra-light);
    color: var(--el-text-color-primary);
    font-family: var(--el-font-family-monospace, monospace);
    font-size: 13px;
    line-height: 1.55;
    white-space: pre-wrap;
  }

  .output_actions {
    display: flex;
    justify-content: flex-end;
    padding-top: 8px;
    white-space: normal;
  }

  .select_host_wrap {
    width: 100%;
    display: flex;

    .select {
      flex: 1;

      .tips {
        margin-left: 5px;
        color: var(--el-text-color-secondary);
        font-size: 12px;
      }
    }
  }

  .command_wrap {
    width: 100%;
    display: flex;
    flex-direction: column;

    .scripts_menu {
      align-self: flex-start;

      :deep(.el-dropdown-menu) {
        min-width: 120px;
        max-width: 300px;
      }
    }

    .link_text {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      margin-bottom: 8px;
      cursor: pointer;
      color: var(--el-color-primary);
      font-size: 13px;
      user-select: none;
    }

    .input {
      width: 100%;

      :deep(.el-textarea__inner) {
        font-family: var(--el-font-family-monospace, monospace);
      }
    }
  }
}

@media screen and (max-width: 768px) {
  .onekey_container .onekey_pagination {
    overflow-x: auto;
    justify-content: flex-start;
  }

  .onekey_container .data_page_toolbar {
    align-items: stretch;
    flex-direction: column;
    padding: 12px 0;

    .toolbar_actions {
      flex-wrap: wrap;
      margin-left: 0;
    }
  }
}
</style>
