<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="150px"
    :title="isModify ? t('scripts.editScriptTitle') : t('scripts.addScriptTitle')"
    :close-on-click-modal="false"
    @open="handleOpen"
    @close="handleClose"
  >
    <el-form
      ref="formRef"
      :model="formData"
      :rules="rules"
      :hide-required-asterisk="true"
      label-suffix="："
      label-width="100px"
      :show-message="false"
    >
      <el-form-item key="group" :label="t('scripts.group')" prop="group">
        <el-select
          v-model="formData.group"
          placeholder=""
          clearable
          style="width: 100%;"
        >
          <el-option
            v-for="item in groupList"
            :key="item.id"
            :label="item.name"
            :value="item.id"
            :disabled="item.id === 'builtin'"
          />
        </el-select>
      </el-form-item>
      <el-form-item :label="t('scripts.name')" prop="name">
        <el-input
          v-model="formData.name"
          clearable
          placeholder=""
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item :label="t('scripts.description')" prop="description">
        <el-input
          v-model="formData.description"
          clearable
          placeholder=""
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item :label="t('scripts.order')" prop="index">
        <el-input
          v-model.trim.number="formData.index"
          clearable
          placeholder=""
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item prop="command" :label="t('scripts.content')">
        <el-input
          v-model="formData.command"
          type="textarea"
          :rows="5"
          clearable
          autocomplete="off"
          style="margin-top: 5px;"
          :placeholder="t('scripts.shellScriptPlaceholder')"
        />
      </el-form-item>
      <el-form-item :label="t('scripts.encodingMode')" prop="useBase64">
        <el-radio-group v-model="formData.useBase64">
          <el-radio :value="false">
            <span>{{ t('scripts.directSend') }}</span>
            <el-tooltip placement="right">
              <template #content>
                <div style="max-width: 300px;">
                  {{ t('scripts.directSendTip1') }}<br>
                  {{ t('scripts.directSendTip2') }}<br>
                  {{ t('scripts.directSendTip3') }}
                </div>
              </template>
              <el-icon style="margin-left: 4px; cursor: help;"><QuestionFilled /></el-icon>
            </el-tooltip>
          </el-radio>
          <el-radio :value="true">
            <span>{{ t('scripts.base64Encoding') }}</span>
            <el-tooltip placement="right">
              <template #content>
                <div style="max-width: 300px;">
                  {{ t('scripts.base64Tip1') }}<br>
                  {{ t('scripts.base64Tip2') }}<br>
                  {{ t('scripts.base64TipEscape') }}<br>
                  {{ t('scripts.base64TipHeredoc') }}<br>
                  {{ t('scripts.base64TipNewline') }}<br>
                  {{ t('scripts.commandFormat') }}
                </div>
              </template>
              <el-icon style="margin-left: 4px; cursor: help;"><QuestionFilled /></el-icon>
            </el-tooltip>
          </el-radio>
        </el-radio-group>
      </el-form-item>
    </el-form>
    <template #footer>
      <span>
        <el-button @click="visible = false">{{ t('scripts.close') }}</el-button>
        <el-button type="primary" @click="handleSubmit">{{ isModify ? t('scripts.edit') : t('scripts.add') }}</el-button>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, reactive, watch } from 'vue'
import { getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'
import { QuestionFilled } from '@element-plus/icons-vue'

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  },
  defaultData: {
    type: Object,
    default: () => ({})
  },
  defaultScript: {
    type: String,
    default: ''
  },
  defaultGroup: {
    type: String,
    default: 'default'
  }
})

const emit = defineEmits(['update:show', 'success',])

const { proxy: { $api, $message, $store } } = getCurrentInstance()
const { t } = useI18n()

const visible = computed({
  get: () => props.show,
  set: (val) => emit('update:show', val)
})

const formRef = ref(null)

const groupList = computed(() => $store.scriptGroupList || [])
const scriptList = computed(() => $store.scriptList)
const curGroupScripts = computed(() => scriptList.value.filter(item => item.group === props.defaultGroup))
const nextIndex = computed(() => curGroupScripts.value.reduce((acc, cur) => Math.max(acc, Number(cur.index) || 0), 0) + 1)

const formData = reactive({
  group: '',
  name: '',
  description: '',
  index: nextIndex.value || 0,
  command: '',
  useBase64: false
})
const isModify = computed(() => Boolean(formData.id))

const rules = computed(() => ({
  group: { required: true, message: t('scripts.selectGroupRequired') },
  name: { required: true, trigger: 'change' },
  description: { required: false, trigger: 'change' },
  index: { required: false, type: 'number', trigger: 'change' },
  command: { required: true, trigger: 'change' }
}))

watch(() => props.defaultData, (newVal) => {
  if (newVal?.id) {
    Object.assign(formData, { ...newVal })
  }
}, { immediate: true, deep: true })

watch(() => props.defaultScript, (newVal) => {
  if (newVal && !formData.id) {
    formData.command = newVal
  }
}, { immediate: true })

watch(() => props.defaultGroup, (newVal) => {
  if (newVal && !formData.id) {
    if (newVal === 'builtin') {
      formData.group = 'default'
    } else {
      formData.group = newVal
    }
  }
}, { immediate: true })

const handleClose = () => {
  formRef.value?.resetFields()
  Object.assign(formData, {
    id: null,
    group: props.defaultGroup,
    name: '',
    description: '',
    index: nextIndex.value,
    command: props.defaultScript || '',
    useBase64: false
  })
}

const handleOpen = () => {
  if (!formData.id) {
    formData.index = nextIndex.value
  }
}

const handleSubmit = () => {
  formRef.value.validate()
    .then(async () => {
      const data = { ...formData }
      if (isModify.value) {
        await $api.updateScript(data.id, data)
      } else {
        await $api.addScript(data)
      }
      visible.value = false
      await $store.getScriptList()
      emit('success')
      $message.success('success')
    })
}
</script>