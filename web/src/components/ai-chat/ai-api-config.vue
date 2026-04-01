<template>
  <el-dialog
    v-model="visible"
    width="600px"
    :title="t('aiChat.configTitle')"
    :top="isMobile() ? '45px' : '10vh'"
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
      <el-form-item :label="t('aiChat.apiUrl')" prop="apiUrl">
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
      <el-form-item :label="t('aiChat.apiKey')" prop="apiKey">
        <el-input v-model="AIconfigFormData.apiKey" clearable :placeholder="t('aiChat.apiKeyPlaceholder')" />
      </el-form-item>
      <el-form-item :label="t('aiChat.modelList')" prop="models">
        <div class="models_input_wrap">
          <el-input-tag
            v-model="AIconfigFormData.models"
            class="models_input_tag"
            tag-type="success"
            tag-effect="plain"
            clearable
            @change="handleModelsChange"
          />
          <el-button type="primary" :loading="fetchingModels" @click="handleFetchModels">{{ t('aiChat.fetchModels') }}</el-button>
        </div>
      </el-form-item>
      <el-form-item :label="t('aiChat.titleGeneration')" prop="titleGenMedel">
        <el-select v-model="AIconfigFormData.titleGenMedel" clearable :placeholder="t('aiChat.selectTitleModel')">
          <el-option
            v-for="(item, index) in AIconfigFormData.models"
            :key="index"
            :label="item"
            :value="item"
          />
        </el-select>
      </el-form-item>
    </el-form>
    <el-alert :title="t('aiChat.alertTitle')" type="warning" :closable="false">
      <div class="ai_config_alert_content">
        <p>{{ t('aiChat.alert1') }}<span class="ai_config_alert_content_span">https://api.openai.com/v1/chat/completions</span></p>
        <p>{{ t('aiChat.alert2Prefix') }}<span class="ai_config_alert_content_span">https://{host}/v1/models API</span>{{ t('aiChat.alert2Suffix') }}</p>
        <p>{{ t('aiChat.alert3Prefix') }}<span class="ai_config_alert_content_span">{{ t('aiChat.alert3Middle') }}</span>{{ t('aiChat.alert3Suffix') }}</p>
        <p>{{ t('aiChat.alert4Prefix') }}<a class="ai_config_alert_content_span one_api_link" href="https://github.com/songquanpeng/one-api" target="_blank">one-api</a>{{ t('aiChat.alert4Suffix') }}</p>
      </div>
    </el-alert>
    <template #footer>
      <footer>
        <div class="footer_btns">
          <el-button type="info" @click="handleClose">{{ t('common.close') }}</el-button>
          <el-button type="primary" :loading="loading" @click="handleSave">{{ t('common.save') }}</el-button>
        </div>
      </footer>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, watch, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'
import { isMobile } from '@/utils'

const { proxy: { $api, $message, $store } } = getCurrentInstance()
const { t } = useI18n()

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
  models: [],
  titleGenMedel: ''
})

watch(props.aiConfig, (newVal) => {
  if (Object.keys(newVal).length >= 3) {
    AIconfigFormData.value = { ...newVal }
  }
}, { immediate: true })

const rules = {
apiUrl: [
  { required: true, message: t('aiChat.validation.apiUrlRequired'), trigger: 'change' },
  {
    pattern: /^https?:\/\/.+/,
    message: t('aiChat.validation.apiUrlInvalid'),
    trigger: 'change'
  },
],
apiKey: [{ required: true, message: t('aiChat.validation.apiKeyRequired'), trigger: 'change' },],
models: [{ required: true, message: t('aiChat.validation.modelListRequired'), trigger: 'change' },],
titleGenMedel: [{ required: true, message: t('aiChat.validation.titleModelRequired'), trigger: 'change' },]
}

const handleFetchModels = async () => {
  if (!AIconfigFormData.value.apiUrl || !AIconfigFormData.value.apiKey) {
    $message.warning(t('aiChat.fillApiUrlAndKeyFirst'))
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
      $message.success(t('aiChat.fetchModelsSuccess'))
    } else {
      $message.error(t('aiChat.fetchModelsFailed', { message: data.msg }))
    }
  } catch (error) {
    $message.error(t('aiChat.fetchModelsFailed', { message: error.message }))
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
    $message.success(t('aiChat.saveSuccess'))
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

const handleModelsChange = (newVal) => {
  if (!newVal?.includes(AIconfigFormData.value.titleGenMedel)) {
    AIconfigFormData.value.titleGenMedel = ''
  }
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
    max-height: 250px;
    overflow-y: auto;
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