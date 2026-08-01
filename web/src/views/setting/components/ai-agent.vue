<template>
  <div class="ai_agent_settings">
    <section class="settings_section">
      <div class="section_head">
        <div>
          <h3>Provider 设置</h3>
          <p>配置 AI 助手使用的模型服务，保存后运维助手和终端助手共用此配置。</p>
        </div>
      </div>

      <el-form
        ref="providerFormRef"
        :model="providerForm"
        :rules="providerRules"
        label-width="106px"
        class="provider_form"
      >
        <el-form-item label="Provider" prop="providerType">
          <el-select v-model="providerForm.providerType" style="width: 260px">
            <el-option
              v-for="item in PROVIDERS"
              :key="item.value"
              :label="item.label"
              :value="item.value"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="Base URL" prop="apiUrl">
          <div class="api_url_wrap">
            <el-autocomplete
              v-model.trim="providerForm.apiUrl"
              :fetch-suggestions="suggestApiUrl"
              :placeholder="apiUrlPlaceholder"
              clearable
              style="width: 100%"
            />
            <p class="field_tip">{{ apiUrlTip }}</p>
          </div>
        </el-form-item>
        <el-form-item label="API Key" prop="apiKey">
          <el-input
            v-model="providerForm.apiKey"
            type="password"
            show-password
            clearable
            style="width: min(620px, 100%)"
          />
        </el-form-item>
        <el-form-item label="模型列表" prop="models">
          <div class="models_input_wrap">
            <el-select
              v-model="providerForm.models"
              class="models_input_tag"
              multiple
              filterable
              allow-create
              default-first-option
              collapse-tags
              collapse-tags-tooltip
              clearable
              placeholder="搜索或输入模型 ID"
              no-data-text="点击“获取模型”加载候选项，或直接输入模型 ID"
            >
              <el-option
                v-for="model in modelOptions"
                :key="model"
                :label="model"
                :value="model"
              />
            </el-select>
            <el-button
              v-if="providerForm.providerType === 'openai-compatible'"
              type="primary"
              :loading="fetchingModels"
              @click="fetchModels"
            >
              获取模型
            </el-button>
          </div>
          <p v-if="providerForm.providerType !== 'openai-compatible'" class="field_tip">当前 Provider 请手动填写可用模型 ID。</p>
        </el-form-item>
        <el-form-item label="上下文窗口">
          <el-input-number
            v-model="providerForm.contextLimit"
            :min="1024"
            :step="1024"
            :precision="0"
            controls-position="right"
          />
          <span class="field_tip inline_tip">默认 65,536，按模型实际上下文窗口调整。</span>
        </el-form-item>
        <el-form-item label="最大迭代次数">
          <el-input-number
            v-model="providerForm.maxSteps"
            :min="1"
            :max="50"
            :step="1"
            :precision="0"
            controls-position="right"
          />
          <span class="field_tip inline_tip">单次对话最多允许模型调用工具并继续推理的次数；默认 25，最多 50。</span>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="savingProvider" @click="saveProvider">保存 Provider 设置</el-button>
        </el-form-item>
      </el-form>
    </section>

    <section class="settings_section host_policy_section">
      <div class="section_head">
        <div>
          <h3>主机 AI 策略</h3>
          <p>限制每台主机允许的操作范围和最高权限模式，会话不能突破这里的设置。</p>
        </div>
      </div>

      <el-table :data="hostPolicies" border class="host_policy_table">
        <el-table-column label="主机" min-width="180">
          <template #default="{ row }">
            <div class="host_name">{{ row.name }}</div>
            <div class="host_addr">{{ row.host }}:{{ row.port }}</div>
          </template>
        </el-table-column>
        <el-table-column label="允许 AI" width="108" align="center">
          <template #default="{ row }">
            <el-switch v-model="row.aiPolicy.enabled" />
          </template>
        </el-table-column>
        <el-table-column label="允许操作" min-width="160">
          <template #default="{ row }">
            <el-select v-model="row.aiPolicy.maxEffect">
              <el-option
                v-for="item in EFFECTS"
                :key="item.value"
                :label="item.label"
                :value="item.value"
              />
            </el-select>
          </template>
        </el-table-column>
        <el-table-column label="最高权限模式" min-width="180">
          <template #default="{ row }">
            <el-select v-model="row.aiPolicy.maxMode">
              <el-option
                v-for="item in MODES"
                :key="item.value"
                :label="item.label"
                :value="item.value"
              />
            </el-select>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="170" fixed="right">
          <template #default="{ row }">
            <el-button
              link
              type="primary"
              :loading="savingHostId === row.id"
              @click="saveHostPolicy(row)"
            >
              保存
            </el-button>
            <el-button link @click="resetHostPolicy(row)">恢复默认</el-button>
          </template>
        </el-table-column>
      </el-table>
    </section>
  </div>
</template>

<script setup>
import { computed, getCurrentInstance, onMounted, ref, watch } from 'vue'

const { proxy: { $api, $message, $store } } = getCurrentInstance()

const PROVIDERS = [
  { value: 'openai-compatible', label: 'OpenAI 兼容' },
  { value: 'anthropic', label: 'Anthropic' },
  { value: 'google', label: 'Google Gemini' },
]

const EFFECTS = [
  { value: 'read', label: '仅只读' },
  { value: 'write', label: '允许读写' },
]

const MODES = [
  { value: 'review', label: '审查' },
  { value: 'assist', label: '协助' },
  { value: 'authorized', label: '授权' },
]

const DEFAULT_HOST_POLICY = {
  enabled: true,
  maxEffect: 'write',
  maxMode: 'authorized'
}

const DEFAULT_CONTEXT_LIMIT = 64 * 1024
const DEFAULT_MAX_STEPS = 25

const providerFormRef = ref(null)
const fetchingModels = ref(false)
const savingProvider = ref(false)
const savingHostId = ref('')
const providerForm = ref(createProviderForm())
const availableModels = ref([])
const hostPolicies = ref([])

const providerRules = {
  apiUrl: [
    { required: true, message: '请输入 Base URL', trigger: 'blur' },
    { pattern: /^https?:\/\/.+/, message: '请输入以 http 或 https 开头的有效 URL', trigger: 'blur' },
  ],
  apiKey: [{ required: true, message: '请输入 API Key', trigger: 'blur' },],
  models: [{ type: 'array', required: true, min: 1, message: '请至少填写一个模型', trigger: 'change' },]
}

const apiUrlPlaceholder = computed(() => {
  if (providerForm.value.providerType === 'anthropic') return 'https://api.anthropic.com/v1'
  if (providerForm.value.providerType === 'google') return 'https://generativelanguage.googleapis.com/v1beta'
  return 'https://api.openai.com/v1'
})

const apiUrlTip = computed(() => {
  if (providerForm.value.providerType === 'anthropic') {
    return '格式：API 前缀，例如 https://api.anthropic.com/v1；不要附加 /messages。'
  }
  if (providerForm.value.providerType === 'google') {
    return '格式：API 前缀，例如 https://generativelanguage.googleapis.com/v1beta；不要附加 /models/...:generateContent。'
  }
  return '格式：API 前缀，例如 https://api.openai.com/v1；兼容旧的完整 /v1/chat/completions 地址。'
})

const modelOptions = computed(() => [...new Set([
  ...availableModels.value,
  ...providerForm.value.models,
]),])

function createProviderForm(config = {}) {
  const form = {
    providerType: 'openai-compatible',
    apiUrl: '',
    apiKey: '',
    models: [],
    contextLimit: DEFAULT_CONTEXT_LIMIT,
    maxSteps: DEFAULT_MAX_STEPS,
    ...config
  }
  form.providerType = PROVIDERS.some((item) => item.value === config.providerType) ? config.providerType : 'openai-compatible'
  form.models = Array.isArray(config.models) ? [...config.models,] : []
  form.contextLimit = Number(config.contextLimit) > 0 ? Number(config.contextLimit) : DEFAULT_CONTEXT_LIMIT
  form.maxSteps = Number.isInteger(Number(config.maxSteps)) && Number(config.maxSteps) >= 1
    ? Math.min(Number(config.maxSteps), 50)
    : DEFAULT_MAX_STEPS
  return form
}

function syncProviderForm(config) {
  providerForm.value = createProviderForm(config || {})
  availableModels.value = [...new Set([...availableModels.value, ...providerForm.value.models,]),]
}

function syncHostPolicies(hosts) {
  hostPolicies.value = (hosts || []).map((host) => ({
    id: host.id || host._id,
    name: host.name,
    host: host.host,
    port: host.port,
    aiPolicy: {
      enabled: host.aiPolicy?.enabled !== false,
      maxEffect: ['read', 'write',].includes(host.aiPolicy?.maxEffect) ? host.aiPolicy.maxEffect : 'write',
      maxMode: ['review', 'assist', 'authorized',].includes(host.aiPolicy?.maxMode)
        ? host.aiPolicy.maxMode
        : 'authorized'
    }
  }))
}

function suggestApiUrl(query, callback) {
  const examples = [apiUrlPlaceholder.value,]
  const value = query?.trim()
  if (value && !examples.includes(value)) examples.unshift(value)
  callback(examples.map((item) => ({ value: item })))
}

async function fetchModels() {
  if (!providerForm.value.apiUrl || !providerForm.value.apiKey) {
    return $message.warning('请先填写 Base URL 和 API Key')
  }
  fetchingModels.value = true
  try {
    const { data } = await $api.getAIModels({
      apiUrl: providerForm.value.apiUrl,
      apiKey: providerForm.value.apiKey
    })
    if (!Array.isArray(data)) throw new Error(data?.msg || '接口未返回模型列表')
    availableModels.value = data.map((item) => item.id).filter(Boolean)
    $message.success(`已加载 ${ availableModels.value.length } 个模型，请从下拉列表选择`)
  } catch (error) {
    $message.error(`获取模型列表失败：${ error.message || '未知错误' }`)
  } finally {
    fetchingModels.value = false
  }
}

async function saveProvider() {
  if (!providerFormRef.value) return
  try {
    await providerFormRef.value.validate()
    savingProvider.value = true
    // 旧 titleGenMedel 等字段不再展示，但必须随保存保留，避免升级后丢数据。
    await $api.saveAIConfig({ ...($store.aiConfig || {}), ...providerForm.value })
    await $store.getAIConfig()
    $message.success('Provider 设置已保存')
  } catch (error) {
    if (error?.message) $message.error(error.message)
  } finally {
    savingProvider.value = false
  }
}

async function saveHostPolicy(row) {
  savingHostId.value = row.id
  try {
    await $api.updateHost({ id: row.id, aiPolicy: { ...row.aiPolicy } })
    await $store.getHostList()
    $message.success(`已保存 ${ row.name } 的 AI 策略`)
  } catch (error) {
    $message.error(error.message || '保存主机 AI 策略失败')
  } finally {
    savingHostId.value = ''
  }
}

async function resetHostPolicy(row) {
  row.aiPolicy = { ...DEFAULT_HOST_POLICY }
  await saveHostPolicy(row)
}

watch(() => $store.aiConfig, syncProviderForm, { immediate: true, deep: true })
watch(() => $store.hostList, syncHostPolicies, { immediate: true, deep: true })

onMounted(async () => {
  if (!$store.hostList.length) await $store.getHostList()
  await $store.getAIConfig()
})
</script>

<style lang="scss" scoped>
.ai_agent_settings {
  max-width: 1100px;
}

.settings_section {
  margin-bottom: 28px;
  padding: 20px;
  border: 1px solid var(--el-border-color-light);
  border-radius: 8px;
  background: var(--el-bg-color);
}

.section_head {
  margin-bottom: 18px;
  h3 { margin: 0 0 6px; font-size: 16px; }
  p { margin: 0; color: var(--el-text-color-secondary); font-size: 13px; line-height: 1.6; }
}

.provider_form { max-width: 760px; }

.api_url_wrap { width: min(620px, 100%); }

.models_input_wrap {
  display: flex;
  width: min(620px, 100%);
  gap: 10px;
  .models_input_tag { flex: 1; }
}

.field_tip {
  margin: 6px 0 0;
  color: var(--el-text-color-secondary);
  font-size: 12px;
  line-height: 1.5;
  &.inline_tip { margin: 0 0 0 10px; }
}

.host_policy_table { width: 100%; }
.host_name { font-weight: 500; }
.host_addr { margin-top: 3px; color: var(--el-text-color-secondary); font-size: 12px; }

@media (max-width: 768px) {
  .settings_section { padding: 14px; }
  .host_policy_section { overflow-x: auto; }
  .host_policy_table { min-width: 760px; }
  .models_input_wrap { align-items: flex-start; flex-direction: column; }
}
</style>
