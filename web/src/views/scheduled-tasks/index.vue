<!-- eslint-disable vue/max-attributes-per-line -->
<template>
  <div class="scheduled_tasks data_page">
    <el-tabs v-model="activeView" class="view_tabs" @tab-change="handleTabChange">
      <el-tab-pane label="任务列表" name="tasks">
        <div class="data_page_toolbar">
          <el-input
            v-model="keyword"
            class="search_input"
            placeholder="搜索任务名称、Cron 或时区"
            clearable
            @keyup.enter="loadTasks"
            @clear="loadTasks"
          >
            <template #prefix><el-icon><Search /></el-icon></template>
          </el-input>
          <div class="toolbar_actions">
            <el-button :icon="Refresh" :loading="tasksLoading" @click="loadTasks">刷新</el-button>
            <el-button type="primary" :icon="Plus" @click="openCreate">新建任务</el-button>
          </div>
        </div>

        <div class="data_table_wrap task_table_wrap">
          <el-table v-loading="tasksLoading" :data="tasks" height="100%" row-key="id" empty-text="暂无定时任务">
            <el-table-column label="任务" min-width="190">
              <template #default="{ row }">
                <div class="task_name">{{ row.name }}</div>
                <div v-if="row.disabledReason" class="disabled_reason">{{ row.disabledReason }}</div>
              </template>
            </el-table-column>
            <el-table-column label="启用" width="76" align="center">
              <template #default="{ row }">
                <el-switch
                  :model-value="row.enabled"
                  :loading="switchingIds.has(row.id)"
                  @change="value => toggleTask(row, value)"
                />
              </template>
            </el-table-column>
            <el-table-column label="计划" min-width="180">
              <template #default="{ row }">
                <el-tooltip placement="top" :disabled="!row.nextRunTimes?.length">
                  <template #content>
                    <div class="next_runs">
                      <div class="next_runs_title">未来 5 次执行时间:</div>
                      <div v-for="time in row.nextRunTimes" :key="time">{{ formatTimeInTimezone(time, row.timezone) }}</div>
                    </div>
                  </template>
                  <code class="cron_expression">{{ row.cron }}</code>
                </el-tooltip>
                <div class="secondary">{{ row.timezone }}</div>
              </template>
            </el-table-column>
            <el-table-column label="目标" min-width="160">
              <template #default="{ row }">
                <el-tooltip :content="hostNames(row.hostIds)" placement="top">
                  <span>{{ row.hostIds.length }} 台主机</span>
                </el-tooltip>
                <div class="secondary">超时 {{ row.timeoutSeconds }} 秒</div>
              </template>
            </el-table-column>
            <el-table-column label="指令" min-width="130">
              <template #default="{ row }">{{ scriptLabel(row) }}</template>
            </el-table-column>
            <el-table-column label="下次执行" min-width="166">
              <template #default="{ row }">{{ formatTimeInTimezone(row.nextRunAt, row.timezone) }}</template>
            </el-table-column>
            <el-table-column label="最近结果" width="112">
              <template #default="{ row }">
                <el-tag v-if="row.lastRunStatus" :type="statusType(row.lastRunStatus)" effect="plain">
                  {{ statusLabel(row.lastRunStatus) }}
                </el-tag>
                <span v-else>--</span>
              </template>
            </el-table-column>
            <el-table-column label="通知" width="92">
              <template #default="{ row }">{{ notificationLabel(row.notificationPolicy) }}</template>
            </el-table-column>
            <el-table-column label="操作" fixed="right" width="210" align="right" header-align="right">
              <template #default="{ row }">
                <div class="task_actions">
                  <el-button
                    text
                    type="primary"
                    :icon="VideoPlay"
                    :loading="executingIds.has(row.id)"
                    @click="runNow(row)"
                  >
                    执行
                  </el-button>
                  <el-button text @click="openEdit(row)">编辑</el-button>
                  <el-dropdown trigger="click">
                    <el-button text :icon="MoreFilled" aria-label="更多操作" title="更多操作" />
                    <template #dropdown>
                      <el-dropdown-menu>
                        <el-dropdown-item :icon="Clock" @click="showTaskRuns(row)">执行历史</el-dropdown-item>
                        <el-dropdown-item :icon="Delete" divided @click="removeTask(row)">删除任务</el-dropdown-item>
                      </el-dropdown-menu>
                    </template>
                  </el-dropdown>
                </div>
              </template>
            </el-table-column>
          </el-table>
        </div>
      </el-tab-pane>

      <el-tab-pane label="执行历史" name="history">
        <div class="data_page_toolbar history_toolbar">
          <div class="history_filters">
            <el-select v-model="historyFilters.taskId" clearable filterable placeholder="全部任务" @change="resetHistory">
              <el-option v-for="task in tasks" :key="task.id" :label="task.name" :value="task.id" />
            </el-select>
            <el-select v-model="historyFilters.status" clearable placeholder="全部状态" @change="resetHistory">
              <el-option v-for="status in runStatuses" :key="status" :label="statusLabel(status)" :value="status" />
            </el-select>
          </div>
          <div class="toolbar_actions">
            <el-button :icon="Refresh" :loading="runsLoading" @click="loadRuns">刷新</el-button>
            <el-button
              type="danger"
              plain
              :icon="Delete"
              :loading="clearingRuns"
              @click="clearRunHistory"
            >
              清空记录
            </el-button>
          </div>
        </div>

        <div class="data_table_wrap history_table_wrap">
          <el-table
            v-loading="runsLoading"
            :data="runs"
            height="100%"
            row-key="id"
            empty-text="暂无执行记录"
            @row-click="openRun"
          >
            <el-table-column prop="taskName" label="任务" min-width="180" />
            <el-table-column label="触发" width="100">
              <template #default="{ row }">{{ row.trigger === 'manual' ? '手动' : '计划' }}</template>
            </el-table-column>
            <el-table-column label="状态" width="116">
              <template #default="{ row }">
                <el-tag :type="statusType(row.status)" effect="plain">{{ statusLabel(row.status) }}</el-tag>
              </template>
            </el-table-column>
            <el-table-column label="主机" width="110">
              <template #default="{ row }">{{ row.targetCount || 0 }} 台</template>
            </el-table-column>
            <el-table-column label="开始时间" min-width="170">
              <template #default="{ row }">{{ formatTime(row.startedAt) }}</template>
            </el-table-column>
            <el-table-column label="耗时" width="112">
              <template #default="{ row }">{{ formatDuration(row.durationMs) }}</template>
            </el-table-column>
            <el-table-column label="操作" width="90" align="right" header-align="right">
              <template #default="{ row }">
                <el-button text type="primary" @click.stop="openRun(row)">详情</el-button>
              </template>
            </el-table-column>
          </el-table>
        </div>
        <div class="pagination_container">
          <el-pagination
            v-model:current-page="historyFilters.page"
            v-model:page-size="historyFilters.pageSize"
            :page-sizes="[20, 50, 100]"
            :total="runTotal"
            layout="total, sizes, prev, pager, next"
            @change="loadRuns"
          />
        </div>
      </el-tab-pane>
    </el-tabs>

    <el-dialog
      v-model="formVisible"
      class="scheduled_task_dialog"
      :title="editingId ? '编辑定时任务' : '新建定时任务'"
      :width="isMobileScreen ? '94%' : '720px'"
      destroy-on-close
      :close-on-click-modal="false"
    >
      <el-form ref="formRef" :model="form" :rules="formRules" label-position="top" @submit.prevent>
        <div class="form_grid">
          <el-form-item label="任务名称" prop="name">
            <el-input v-model="form.name" maxlength="100" show-word-limit />
          </el-form-item>
          <el-form-item label="目标主机" prop="hostIds">
            <el-select v-model="form.hostIds" multiple filterable collapse-tags :max-collapse-tags="2" placeholder="选择 SSH 主机">
              <el-option v-for="host in sshHosts" :key="host.id" :label="host.name" :value="host.id" />
            </el-select>
          </el-form-item>
          <el-form-item label="Cron（分 时 日 月 周）" prop="cron">
            <el-autocomplete
              v-model="form.cron"
              :fetch-suggestions="queryCronSuggestions"
              value-key="value"
              popper-class="scheduled_cron_suggestions"
              placeholder="0 2 * * *"
              clearable
              @select="selectCronSuggestion"
            >
              <template #default="{ item }">
                <div class="cron_suggestion">
                  <span>{{ item.label }}</span>
                  <code>{{ item.value }}</code>
                </div>
              </template>
            </el-autocomplete>
          </el-form-item>
          <el-form-item label="时区" prop="timezone">
            <el-select v-model="form.timezone" filterable allow-create default-first-option>
              <el-option v-for="timezone in timezones" :key="timezone" :label="timezone" :value="timezone" />
            </el-select>
          </el-form-item>
          <el-form-item label="超时（秒）" prop="timeoutSeconds">
            <el-input-number v-model="form.timeoutSeconds" :min="1" :max="1800" controls-position="right" />
          </el-form-item>
          <el-form-item label="执行通知" prop="notificationPolicy">
            <el-select v-model="form.notificationPolicy">
              <el-option label="仅失败时" value="failure" />
              <el-option label="每次执行" value="always" />
              <el-option label="从不通知" value="never" />
            </el-select>
          </el-form-item>
        </div>

        <el-form-item v-if="!form.referenceScript" label="执行方式">
          <el-radio-group v-model="form.useBase64">
            <el-radio-button :value="false">直接执行</el-radio-button>
            <el-radio-button :value="true">Base64 脚本</el-radio-button>
          </el-radio-group>
        </el-form-item>

        <el-form-item class="command_form_item" label="指令" prop="command">
          <div class="command_wrap">
            <div class="command_toolbar">
              <el-dropdown v-if="!form.referenceScript" trigger="click" max-height="50vh">
                <span class="script_import">从脚本库导入<el-icon><ArrowDown /></el-icon></span>
                <template #dropdown>
                  <el-dropdown-menu>
                    <el-dropdown-item v-for="script in scriptList" :key="script.id" @click="importScript(script)">
                      {{ script.name }}
                    </el-dropdown-item>
                  </el-dropdown-menu>
                </template>
              </el-dropdown>
              <span v-else />
              <el-switch v-model="form.referenceScript" active-text="引用脚本库" @change="handleReferenceChange" />
            </div>
            <el-select
              v-if="form.referenceScript"
              v-model="form.scriptId"
              filterable
              placeholder="选择脚本库脚本"
              @change="clearInstructionValidation"
            >
              <el-option v-for="script in scriptList" :key="script.id" :label="script.name" :value="script.id">
                <span>{{ script.name }}</span>
                <span class="script_group">{{ script.builtin ? '内置' : '自定义' }}</span>
              </el-option>
            </el-select>
            <template v-else>
              <el-input
                v-model="form.command"
                class="script_input"
                type="textarea"
                :rows="12"
                spellcheck="false"
                placeholder="输入 Shell 指令"
              />
              <div class="byte_count" :class="{ exceeded: scriptBytes > maxScriptBytes }">
                {{ formatBytes(scriptBytes) }} / 256 KiB
              </div>
            </template>
          </div>
        </el-form-item>
        <el-form-item class="enabled_form_item">
          <el-checkbox v-model="form.enabled">启用任务</el-checkbox>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="formVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="saveTask">保存</el-button>
      </template>
    </el-dialog>

    <el-drawer v-model="runDrawerVisible" title="执行详情" :size="isMobileScreen ? '100%' : '72%'" destroy-on-close>
      <div v-loading="runDetailLoading" class="run_detail">
        <template v-if="runDetail">
          <div class="run_summary">
            <div><span>任务</span><strong>{{ runDetail.taskName }}</strong></div>
            <div><span>状态</span><el-tag :type="statusType(runDetail.status)">{{ statusLabel(runDetail.status) }}</el-tag></div>
            <div><span>触发</span><strong>{{ runDetail.trigger === 'manual' ? '手动执行' : 'Cron 调度' }}</strong></div>
            <div><span>耗时</span><strong>{{ formatDuration(runDetail.durationMs) }}</strong></div>
          </div>
          <div v-if="runDetail.status === 'running'" class="run_actions">
            <el-button type="danger" plain :loading="stopping" @click="stopRun">停止整批</el-button>
          </div>
          <el-collapse class="target_results">
            <el-collapse-item v-for="target in runDetail.targets" :key="target.id" :name="target.id">
              <template #title>
                <div class="target_title">
                  <strong>{{ target.hostName }}</strong>
                  <el-tag size="small" :type="statusType(target.status)" effect="plain">{{ statusLabel(target.status) }}</el-tag>
                  <span>{{ formatDuration(target.durationMs) }}</span>
                  <span v-if="target.truncated" class="truncated">输出已截断至 256 KiB</span>
                </div>
              </template>
              <p v-if="target.error" class="target_error">原因：{{ target.error }}</p>
              <div class="output_grid">
                <section>
                  <h4>stdout</h4>
                  <pre>{{ target.stdout || '(无输出)' }}</pre>
                </section>
                <section>
                  <h4>stderr</h4>
                  <pre>{{ target.stderr || '(无输出)' }}</pre>
                </section>
              </div>
            </el-collapse-item>
          </el-collapse>
        </template>
      </div>
    </el-drawer>
  </div>
</template>

<script setup>
import { computed, getCurrentInstance, nextTick, onBeforeUnmount, reactive, ref, watch } from 'vue'
import dayjs from 'dayjs'
import { ArrowDown, Clock, Delete, MoreFilled, Plus, Refresh, Search, VideoPlay } from '@element-plus/icons-vue'
import useMobileWidth from '@/composables/useMobileWidth'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()
const { isMobileScreen } = useMobileWidth()
const maxScriptBytes = 256 * 1024
const runStatuses = ['running', 'success', 'partial', 'failed', 'timeout', 'cancelled', 'skipped', 'interrupted',]
const completedRunStatuses = new Set(['success', 'partial', 'failed', 'timeout', 'cancelled', 'skipped', 'interrupted',])
const timezones = ['Asia/Shanghai', 'UTC', 'Asia/Hong_Kong', 'Asia/Tokyo', 'Europe/London', 'America/New_York',]
const cronSuggestions = [
  { label: '每分钟', value: '* * * * *' },
  { label: '每 30 分钟', value: '*/30 * * * *' },
  { label: '每小时', value: '0 * * * *' },
  { label: '每天 12:00', value: '0 12 * * *' },
  { label: '每天 00:00', value: '0 0 * * *' },
  { label: '每周一 00:00', value: '0 0 * * 1' },
  { label: '每月 1 号', value: '0 0 1 * *' },
]
const activeView = ref('tasks')
const tasks = ref([])
const tasksLoading = ref(false)
const keyword = ref('')
const switchingIds = reactive(new Set())
const executingIds = reactive(new Set())
const runs = ref([])
const runTotal = ref(0)
const runsLoading = ref(false)
const clearingRuns = ref(false)
const historyFilters = reactive({ taskId: '', status: '', page: 1, pageSize: 20 })
const formVisible = ref(false)
const formRef = ref()
const editingId = ref('')
const saving = ref(false)
const runDrawerVisible = ref(false)
const runDetail = ref(null)
const runDetailLoading = ref(false)
const stopping = ref(false)
let pollTimer = null
let runRequestGeneration = 0
let activeRunId = ''

const emptyForm = () => ({
  name: '', enabled: true, hostIds: [], cron: '0 2 * * *', timezone: 'Asia/Shanghai',
  timeoutSeconds: 120, notificationPolicy: 'failure', referenceScript: false, command: '', useBase64: false, scriptId: ''
})
const form = reactive(emptyForm())
const sshHosts = computed(() => $store.hostList.filter(host => host.connectType !== 'rdp'))
const scriptList = computed(() => $store.scriptList || [])
const scriptBytes = computed(() => new TextEncoder().encode(form.command || '').length)

const validateCron = (rule, value, callback) => {
  if (String(value || '').trim().split(/\s+/).length !== 5) callback(new Error('请输入 5 段 Cron 表达式'))
  else callback()
}

function queryCronSuggestions(query, callback) {
  const keyword = String(query || '').trim().toLowerCase()
  const matches = cronSuggestions.filter(item => !keyword
    || item.label.toLowerCase().includes(keyword)
    || item.value.includes(keyword))
  callback(matches.length ? matches : cronSuggestions)
}

function selectCronSuggestion(item) { form.cron = item.value }
const validateScript = (rule, value, callback) => {
  if (form.referenceScript) {
    if (!form.scriptId) return callback(new Error('请选择脚本库脚本'))
    return callback()
  }
  if (!String(value || '').trim()) return callback(new Error('脚本内容不能为空'))
  if (scriptBytes.value > maxScriptBytes) return callback(new Error('脚本内容不能超过 256 KiB'))
  callback()
}
const formRules = {
  name: [{ required: true, message: '请输入任务名称', trigger: 'blur' },],
  hostIds: [{ type: 'array', required: true, min: 1, message: '至少选择一台主机', trigger: 'change' },],
  cron: [{ required: true, validator: validateCron, trigger: 'blur' },],
  timezone: [{ required: true, message: '请输入时区', trigger: 'change' },],
  timeoutSeconds: [{ required: true, type: 'number', min: 1, max: 1800, message: '范围为 1-1800 秒' },],
  command: [{ validator: validateScript, trigger: 'blur' },]
}

async function loadTasks() {
  tasksLoading.value = true
  try {
    const { data } = await $api.getScheduledTasks({ keyword: keyword.value })
    tasks.value = data || []
  } finally {
    tasksLoading.value = false
  }
}

async function loadRuns() {
  runsLoading.value = true
  try {
    const { data } = await $api.getScheduledTaskRuns({ ...historyFilters })
    runs.value = data.items || []
    runTotal.value = data.total || 0
  } finally {
    runsLoading.value = false
  }
}

function clearRunHistory() {
  $messageBox.confirm('将清空所有已结束的执行记录，正在执行的批次会保留。是否继续？', '清空执行记录', {
    type: 'warning', confirmButtonText: '清空', cancelButtonText: '取消'
  }).then(async () => {
    clearingRuns.value = true
    try {
      const { data } = await $api.clearScheduledTaskRuns()
      historyFilters.page = 1
      await loadRuns()
      $message.success(`已清空 ${ data.batchesRemoved || 0 } 条执行记录`)
    } finally {
      clearingRuns.value = false
    }
  })
}

function handleTabChange(name) {
  if (name === 'history') loadRuns()
}

function resetHistory() {
  historyFilters.page = 1
  loadRuns()
}

function openCreate() {
  editingId.value = ''
  Object.assign(form, emptyForm())
  formVisible.value = true
}

async function openEdit(row) {
  const { data } = await $api.getScheduledTask(row.id)
  editingId.value = row.id
  Object.assign(form, emptyForm(), {
    ...data,
    referenceScript: data.script?.type === 'library',
    command: data.script?.command || '',
    useBase64: data.script?.useBase64 === true,
    scriptId: data.script?.scriptId || ''
  })
  formVisible.value = true
}

function formPayload() {
  const script = form.referenceScript
    ? { type: 'library', scriptId: form.scriptId }
    : { type: 'inline', command: form.command, useBase64: form.useBase64 }
  return {
    name: form.name,
    enabled: form.enabled,
    hostIds: form.hostIds,
    cron: form.cron,
    timezone: form.timezone,
    timeoutSeconds: form.timeoutSeconds,
    notificationPolicy: form.notificationPolicy,
    script
  }
}

async function importScript(script) {
  form.referenceScript = false
  form.scriptId = ''
  form.command = script.command || ''
  form.useBase64 = script.useBase64 === true
  await nextTick()
  clearInstructionValidation()
}

async function handleReferenceChange(referenceScript) {
  if (!referenceScript) form.scriptId = ''
  await nextTick()
  clearInstructionValidation()
}

function clearInstructionValidation() { formRef.value?.clearValidate('command') }

async function saveTask() {
  await formRef.value.validate()
  saving.value = true
  try {
    if (editingId.value) await $api.updateScheduledTask(editingId.value, formPayload())
    else await $api.addScheduledTask(formPayload())
    formVisible.value = false
    $message.success('定时任务已保存')
    await loadTasks()
  } finally {
    saving.value = false
  }
}

async function toggleTask(row, enabled) {
  switchingIds.add(row.id)
  try {
    await $api.updateScheduledTask(row.id, { enabled })
    row.enabled = enabled
    await loadTasks()
  } finally {
    switchingIds.delete(row.id)
  }
}

async function runNow(row) {
  if (executingIds.has(row.id)) return
  executingIds.add(row.id)
  try {
    const { data } = await $api.runScheduledTask(row.id)
    $message.success(data.status === 'skipped' ? '已有批次运行，本次执行已跳过' : '任务已开始执行')
    activeView.value = 'history'
    historyFilters.taskId = row.id
    historyFilters.page = 1
    await loadRuns()
    if (data.id) openRun(data)
  } finally {
    executingIds.delete(row.id)
  }
}

function removeTask(row) {
  $messageBox.confirm(`确认删除定时任务“${ row.name }”？`, '删除任务', {
    type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消'
  }).then(async () => {
    await $api.removeScheduledTask(row.id)
    $message.success('定时任务已删除')
    await loadTasks()
  })
}

function showTaskRuns(row) {
  activeView.value = 'history'
  historyFilters.taskId = row.id
  historyFilters.page = 1
  loadRuns()
}

async function openRun(row) {
  const runId = row.id
  const generation = ++runRequestGeneration
  activeRunId = runId
  runDrawerVisible.value = true
  runDetailLoading.value = runDetail.value?.id !== runId
  clearPoll()
  let shouldPoll = runDetail.value?.id === runId && !completedRunStatuses.has(runDetail.value.status)
  try {
    const { data } = await $api.getScheduledTaskRun(runId)
    if (generation !== runRequestGeneration || !runDrawerVisible.value || activeRunId !== runId) return
    runDetail.value = data
    shouldPoll = !completedRunStatuses.has(data.status)
  } catch (error) {
    if (runDetail.value?.id !== runId) throw error
  } finally {
    if (generation === runRequestGeneration) {
      runDetailLoading.value = false
      if (runDrawerVisible.value && activeRunId === runId && shouldPoll) {
        pollTimer = setTimeout(() => openRun({ id: runId }), 3000)
      }
    }
  }
}

async function stopRun() {
  const runId = runDetail.value.id
  stopping.value = true
  try {
    await $api.stopScheduledTaskRun(runId)
    $message.success('已提交停止请求')
    if (runDrawerVisible.value && activeRunId === runId) {
      clearPoll()
      pollTimer = setTimeout(() => openRun({ id: runId }), 3000)
    }
  } finally {
    stopping.value = false
  }
}

function clearPoll() {
  if (pollTimer) clearTimeout(pollTimer)
  pollTimer = null
}

function hostNames(ids = []) {
  const map = new Map($store.hostList.map(host => [host.id, host.name,]))
  return ids.map(id => map.get(id) || id).join('、')
}
function scriptLabel(task) {
  if (task.script?.type !== 'library') return '独立指令'
  const script = scriptList.value.find(item => item.id === task.script.scriptId)
  return script?.name || task.script.scriptId || '引用脚本库'
}
function notificationLabel(policy) { return ({ failure: '仅失败', always: '每次', never: '关闭' })[policy] || policy }
function statusLabel(status) {
  return ({ running: '运行中', success: '成功', partial: '部分失败', failed: '失败', timeout: '超时', cancelled: '已取消', skipped: '已跳过', interrupted: '已中断' })[status] || status
}
function statusType(status) {
  return ({ success: 'success', running: 'primary', partial: 'warning', failed: 'danger', timeout: 'danger', cancelled: 'info', skipped: 'info', interrupted: 'danger' })[status] || 'info'
}
function formatTime(value) { return value ? dayjs(value).format('YYYY-MM-DD HH:mm:ss') : '--' }
function formatTimeInTimezone(value, timezone) {
  if (!value) return '--'
  const parts = new Intl.DateTimeFormat('zh-CN', {
    timeZone: timezone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23'
  }).formatToParts(new Date(value))
  const values = Object.fromEntries(parts.map(part => [part.type, part.value,]))
  return `${ values.year }-${ values.month }-${ values.day } ${ values.hour }:${ values.minute }:${ values.second }`
}
function formatDuration(value) {
  if (value === undefined || value === null) return '--'
  return value < 1000 ? `${ value } ms` : `${ (value / 1000).toFixed(1) } s`
}
function formatBytes(value) { return value < 1024 ? `${ value } B` : `${ (value / 1024).toFixed(1) } KiB` }

loadTasks()
watch(runDrawerVisible, async value => {
  if (!value) {
    clearPoll()
    runRequestGeneration += 1
    activeRunId = ''
    runDetailLoading.value = false
    await Promise.all([
      loadTasks(),
      activeView.value === 'history' ? loadRuns() : Promise.resolve(),
    ])
  }
})
onBeforeUnmount(() => {
  clearPoll()
  runRequestGeneration += 1
})
</script>

<style lang="scss" scoped>
.scheduled_tasks {
  overflow: hidden;

  .view_tabs {
    min-height: 0;
    flex: 1;
    display: flex;
    flex-direction: column;
  }
  .view_tabs :deep(.el-tabs__header) { flex: 0 0 auto; }
  .view_tabs :deep(.el-tabs__content) { min-height: 0; flex: 1; overflow: hidden; }
  .view_tabs :deep(.el-tab-pane) { height: 100%; min-height: 0; display: flex; flex-direction: column; }
  .search_input { width: clamp(280px, 36vw, 460px); }
  .task_table_wrap, .history_table_wrap { min-height: 0; flex: 1; margin-top: 14px; }
  .task_name { font-weight: 600; color: var(--el-text-color-primary); }
  .task_actions { display: flex; align-items: center; justify-content: flex-end; flex-wrap: nowrap; gap: 2px; white-space: nowrap; }
  .task_actions :deep(.el-button + .el-button) { margin-left: 0; }
  .secondary { margin-top: 4px; color: var(--el-text-color-secondary); font-size: 12px; }
  .disabled_reason { margin-top: 4px; color: var(--el-color-warning); font-size: 12px; }
  code { padding: 2px 5px; border-radius: 4px; background: var(--el-fill-color-light); }
  .cron_expression { cursor: help; }
  .history_filters { display: flex; gap: 10px; }
  .history_filters .el-select { width: 190px; }
  .pagination_container { display: flex; justify-content: flex-end; margin-top: 14px; }
  .form_grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0 16px; }
  .form_grid :deep(.el-input-number), .form_grid :deep(.el-select), .form_grid :deep(.el-autocomplete) { width: 100%; }
  .command_wrap { width: 100%; }
  .command_toolbar { display: flex; align-items: center; justify-content: space-between; min-height: 32px; margin-bottom: 8px; }
  .script_import { display: inline-flex; align-items: center; gap: 3px; color: var(--el-color-primary); cursor: pointer; }
  .command_wrap > .el-select { width: 100%; }
  .script_input :deep(textarea) { font-family: 'JetBrains Mono', Menlo, Consolas, monospace; line-height: 1.55; }
  .command_form_item { margin-bottom: 8px; }
  .enabled_form_item { margin-bottom: 0; }
  .byte_count { width: 100%; margin-top: 4px; line-height: 20px; text-align: right; color: var(--el-text-color-secondary); font-size: 12px; }
  .byte_count.exceeded { color: var(--el-color-danger); }
  .script_group { float: right; margin-left: 20px; color: var(--el-text-color-secondary); font-size: 12px; }
  .run_summary { display: grid; grid-template-columns: repeat(4, minmax(120px, 1fr)); border-bottom: 1px solid var(--el-border-color-lighter); }
  .run_summary > div { display: flex; flex-direction: column; gap: 8px; padding: 12px 16px; }
  .run_summary span { color: var(--el-text-color-secondary); font-size: 12px; }
  .run_actions { display: flex; justify-content: flex-end; padding: 14px 0; }
  .target_title { display: flex; align-items: center; gap: 10px; min-width: 0; }
  .target_title > span:not(.el-tag) { color: var(--el-text-color-secondary); font-size: 12px; }
  .target_title .truncated { color: var(--el-color-warning); }
  .target_error { color: var(--el-color-danger); }
  .output_grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .output_grid section { min-width: 0; }
  .output_grid h4 { margin: 0 0 6px; font-size: 12px; color: var(--el-text-color-secondary); }
  .output_grid pre { min-height: 92px; max-height: 420px; margin: 0; padding: 10px; overflow: auto; border: 1px solid var(--el-border-color-lighter); border-radius: 6px; background: var(--el-fill-color-light); white-space: pre-wrap; overflow-wrap: anywhere; font-size: 12px; }
}

@media (max-width: 768px) {
  .scheduled_tasks {
    .view_tabs :deep(.el-tabs__header) { padding-left: 55px; }
    .data_page_toolbar { align-items: stretch; flex-direction: column; gap: 10px; }
    .search_input { width: 100%; }
    .toolbar_actions { display: flex; justify-content: flex-end; }
    .history_toolbar { flex-direction: row; align-items: flex-end; }
    .history_filters { flex: 1; flex-direction: column; }
    .history_filters .el-select { width: 100%; }
    .form_grid { grid-template-columns: 1fr; }
    .run_summary { grid-template-columns: 1fr 1fr; }
    .output_grid { grid-template-columns: 1fr; }
    .target_title { flex-wrap: wrap; }
    .pagination_container { overflow-x: auto; justify-content: flex-start; }
  }
}

:global(.scheduled_cron_suggestions .cron_suggestion) {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  min-width: 240px;
}
:global(.scheduled_cron_suggestions .cron_suggestion code) { color: var(--el-text-color-secondary); }
:global(.next_runs) { display: grid; gap: 4px; font-variant-numeric: tabular-nums; }
:global(.next_runs_title) { margin-bottom: 2px; color: var(--el-text-color-secondary); font-size: 12px; }
:global(.scheduled_task_dialog .el-dialog__body) { padding-bottom: 10px; }
:global(.scheduled_task_dialog .el-dialog__footer) { padding-top: 8px; }
</style>
