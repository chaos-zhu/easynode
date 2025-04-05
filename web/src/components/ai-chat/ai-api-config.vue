<template>
  <el-dialog
    v-model="visible"
    width="600px"
    title="AI API配置"
    :top="'15vh'"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :show-close="false"
    center
    custom-class="ai_config_container"
  >
    <el-form
      ref="AIconfigFormRef"
      :model="AIconfigFormData"
      :rules="rules"
      label-width="80px"
      class="config_form"
    >
      <el-form-item label="接口地址" prop="apiUrl">
        <el-autocomplete
          v-model.trim="AIconfigFormData.apiUrl"
          :fetch-suggestions="inputApiUrlSuggestion"
          style="width: 100%;"
          clearable
        >
          <template #default="{ item }">
            <div class="value">{{ item.value }}</div>
          </template>
        </el-autocomplete>
      </el-form-item>
      <el-form-item label="API KEY" prop="apiKey">
        <el-input v-model="AIconfigFormData.apiKey" clearable placeholder="例如: sk-xxx" />
      </el-form-item>
      <el-form-item label="模型列表" prop="models">
        <div class="models_input_wrap">
          <el-input-tag
            v-model="AIconfigFormData.models"
            class="models_input_tag"
            tag-type="success"
            tag-effect="plain"
            clearable
          />
          <el-button type="primary" :loading="fetchingModels" @click="handleFetchModels">获取模型</el-button>
        </div>
      </el-form-item>
    </el-form>
    <el-alert title="提示:" type="warning" :closable="false">
      <div class="ai_config_alert_content">
        <p>1. 接口地址需填写完整，例如：<span class="ai_config_alert_content_span">https://api.openai.com/v1/chat/completions</span></p>
        <p>2. 获取模型列表只支持通过<span class="ai_config_alert_content_span">https://{host}/v1/models API</span>获取</p>
        <p>3. 模型对话在web端进行，因此需供应方支持<span class="ai_config_alert_content_span">cors跨域</span>, 例如阿里通义API<span class="ai_config_alert_content_span">不支持</span></p>
        <p>4. 多渠道建议使用<a class="ai_config_alert_content_span one_api_link" href="https://github.com/songquanpeng/one-api" target="_blank">one-api</a>等专业AI平台聚合服务</p>
      </div>
    </el-alert>
    <template #footer>
      <footer>
        <div class="footer_btns">
          <el-button type="info" @click="handleClose">关闭</el-button>
          <el-button type="primary" :loading="loading" @click="handleSave">保存</el-button>
        </div>
      </footer>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, watch, getCurrentInstance } from 'vue'

const { proxy: { $api, $message, $store } } = getCurrentInstance()

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  },
  aiConfig: {
    type: Object,
    default: () => ({})
  }
})

const emit = defineEmits(['update:show',])

const loading = ref(false)

const visible = computed({
  get() {
    return props.show
  },
  set(newVal) {
    emit('update:show', newVal)
  }
})

const AIconfigFormRef = ref(null)
const fetchingModels = ref(false)

const AIconfigFormData = ref({
  apiUrl: '',
  apiKey: '',
  models: []
})

watch(props.aiConfig, (newVal) => {
  if (Object.keys(newVal).length >= 3) {
    AIconfigFormData.value = { ...newVal }
  }
}, { immediate: true })

const rules = {
  apiUrl: [
    { required: true, message: '请输入接口地址', trigger: 'change' },
    {
      pattern: /^https?:\/\/.+/,
      message: '请输入以http或https开头的有效URL',
      trigger: 'change'
    },
  ],
  apiKey: [{ required: true, message: '请输入API KEY', trigger: 'change' },],
  models: [{ required: true, message: '请输入或获取模型列表', trigger: 'change' },]
}

const handleFetchModels = async () => {
  if (!AIconfigFormData.value.apiUrl || !AIconfigFormData.value.apiKey) {
    $message.warning('请先填写接口地址和API KEY')
    return
  }
  fetchingModels.value = true
  try {
    const { data } = await $api.getAIModels({
      apiUrl: AIconfigFormData.value.apiUrl,
      apiKey: AIconfigFormData.value.apiKey
    })
    console.log('models: ', data)
    if (Array.isArray(data)) {
      AIconfigFormData.value.models = data.map(item => item.id).filter(item => item)
      $message.success('获取模型列表成功')
    } else {
      $message.error(`获取模型列表失败：${ data.msg }`)
    }
  } catch (error) {
    $message.error(`获取模型列表失败：${ error.message }`)
  } finally {
    fetchingModels.value = false
  }
}

const handleSave = async () => {
  if (!AIconfigFormRef.value) return
  try {
    await AIconfigFormRef.value.validate()
    loading.value = true
    await $api.saveAIConfig(AIconfigFormData.value)
    await $store.getAIConfig()
    $message.success('保存成功')
    visible.value = false
  } catch (error) {
    console.error(error)
  } finally {
    loading.value = false
  }
}

const handleClose = () => {
  visible.value = false
}

const inputApiUrlSuggestion = (query, cb) => {
  if (!AIconfigFormData.value.apiUrl) return cb([{ value: 'https://api.openai.com/v1/chat/completions' },])
  const origin = new URL(AIconfigFormData.value.apiUrl).origin
  cb([{ value: `${ origin }/v1/chat/completions` },])
}
</script>

<style lang="scss" scoped>
.config_form {
  padding: 20px;
}
.models_input_wrap {
  width: 100%;
  display: flex;
  gap: 10px;
  .models_input_tag {
    flex: 1;
  }
}
</style>

<style lang="scss">
.ai_config_container {
}

.ai_config_alert_content {
  padding: 0 8px;
  p {
    line-height: 28px;
  }
  .ai_config_alert_content_span {
    font-weight: bold;
    margin: 0 5px;
  }
  .one_api_link {
    color: var(--el-color-warning);
    text-decoration: underline;
    &:hover {
      color: #409eff;
    }
  }
}
</style>