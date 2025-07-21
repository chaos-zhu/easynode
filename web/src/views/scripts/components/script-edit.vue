<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="150px"
    :title="isModify ? '修改脚本' : '添加脚本'"
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
      <el-form-item key="group" label="分组" prop="group">
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
      <el-form-item label="名称" prop="name">
        <el-input
          v-model="formData.name"
          clearable
          placeholder=""
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item label="描述" prop="description">
        <el-input
          v-model="formData.description"
          clearable
          placeholder=""
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item label="序号" prop="index">
        <el-input
          v-model.trim.number="formData.index"
          clearable
          placeholder=""
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item prop="command" label="内容">
        <el-input
          v-model="formData.command"
          type="textarea"
          :rows="5"
          clearable
          autocomplete="off"
          style="margin-top: 5px;"
          placeholder="shell script"
        />
      </el-form-item>
    </el-form>
    <template #footer>
      <span>
        <el-button @click="visible = false">关闭</el-button>
        <el-button type="primary" @click="handleSubmit">{{ isModify ? '修改' : '添加' }}</el-button>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, reactive, watch } from 'vue'
import { getCurrentInstance } from 'vue'

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
  command: ''
})
const isModify = computed(() => Boolean(formData.id))

const rules = {
  group: { required: true, message: '选择一个分组' },
  name: { required: true, trigger: 'change' },
  description: { required: false, trigger: 'change' },
  index: { required: false, type: 'number', trigger: 'change' },
  command: { required: true, trigger: 'change' }
}

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
    command: props.defaultScript || ''
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