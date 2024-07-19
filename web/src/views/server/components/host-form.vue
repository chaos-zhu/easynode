<template>
  <el-dialog
    v-model="visible"
    width="400px"
    :title="title"
    :close-on-click-modal="false"
    @open="setDefaultData"
    @closed="handleClosed"
  >
    <el-form
      ref="formRef"
      :model="hostForm"
      :rules="rules"
      :hide-required-asterisk="true"
      label-suffix="："
      label-width="100px"
      :show-message="false"
    >
      <transition-group
        name="list"
        mode="out-in"
        tag="div"
      >
        <el-form-item key="group" label="分组" prop="group">
          <el-select
            v-model="hostForm.group"
            placeholder="服务器分组"
            style="width: 100%;"
          >
            <el-option
              v-for="item in groupList"
              :key="item.id"
              :label="item.name"
              :value="item.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item key="name" label="服务器名称" prop="name">
          <el-input
            v-model.trim="hostForm.name"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item key="host" label="服务器IP" prop="host">
          <el-input
            v-model.trim="hostForm.host"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item key="expired" label="到期时间" prop="expired">
          <el-date-picker
            v-model="hostForm.expired"
            type="date"
            style="width: 100%;"
            value-format="x"
            placeholder="服务器到期时间"
          />
        </el-form-item>
        <el-form-item
          v-if="hostForm.expired"
          key="expiredNotify"
          label="到期提醒"
          prop="expiredNotify"
        >
          <el-tooltip content="将在服务器到期前7、3、1天发送提醒(需在设置中绑定有效邮箱)" placement="right">
            <el-switch
              v-model="hostForm.expiredNotify"
              :active-value="true"
              :inactive-value="false"
            />
          </el-tooltip>
        </el-form-item>
        <el-form-item key="index" label="序号" prop="index">
          <el-input
            v-model.trim.number="hostForm.index"
            clearable
            placeholder="用于服务器列表中排序(填写数字)"
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item key="consoleUrl" label="控制台URL" prop="consoleUrl">
          <el-input
            v-model.trim="hostForm.consoleUrl"
            clearable
            placeholder="用于直达云服务商控制台"
            autocomplete="off"
            @keyup.enter="handleSave"
          />
        </el-form-item>
        <el-form-item key="remark" label="备注" prop="remark">
          <el-input
            v-model.trim="hostForm.remark"
            type="textarea"
            :rows="3"
            clearable
            autocomplete="off"
            placeholder="简单记录服务器用途"
          />
        </el-form-item>
      </transition-group>
    </el-form>
    <template #footer>
      <span class="dialog-footer">
        <el-button @click="visible = false">关闭</el-button>
        <el-button type="primary" @click="handleSave">确认</el-button>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, reactive, computed, getCurrentInstance, nextTick } from 'vue'

const { proxy: { $api, $message, $store } } = getCurrentInstance()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  },
  defaultData: {
    required: false,
    type: Object,
    default: null
  }
})
const emit = defineEmits(['update:show', 'update-list', 'closed',])

const resetForm = () => ({
  group: 'default',
  name: '',
  host: '',
  index: 0,
  expired: null,
  expiredNotify: false,
  consoleUrl: '',
  remark: ''
})

const hostForm = reactive(resetForm())
const oldHost = ref('')
const rules = reactive({
  group: { required: true, message: '选择一个分组' },
  name: { required: true, message: '输入主机别名', trigger: 'change' },
  host: { required: true, message: '输入IP/域名', trigger: 'change' },
  index: { required: true, type: 'number', message: '输入数字', trigger: 'change' },
  expired: { required: false },
  expiredNotify: { required: false },
  consoleUrl: { required: false },
  remark: { required: false }
})

const formRef = ref(null)

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

const title = computed(() => props.defaultData ? '修改服务器' : '新增服务器')

let groupList = computed(() => $store.groupList || [])

const handleClosed = () => {
  // console.log('handleClosed')
  Object.assign(hostForm, resetForm())
  emit('closed')
  nextTick(() => formRef.value.resetFields())
}

const setDefaultData = () => {
  if (!props.defaultData) return
  // console.log(props.defaultData)
  let { name, host, index, expired, expiredNotify, consoleUrl, group, remark } = props.defaultData
  oldHost.value = host
  Object.assign(hostForm, { name, host, index, expired, expiredNotify, consoleUrl, group, remark })
}

const handleSave = () => {
  formRef.value.validate()
    .then(async () => {
      if (!hostForm.expired || !hostForm.expiredNotify) {
        hostForm.expired = null
        hostForm.expiredNotify = false
      }
      if (props.defaultData) {
        let { msg } = await $api.updateHost(Object.assign({}, hostForm, { oldHost: oldHost.value }))
        $message({ type: 'success', center: true, message: msg })
      } else {
        let { msg } = await $api.saveHost(hostForm)
        $message({ type: 'success', center: true, message: msg })
      }
      visible.value = false
      emit('update-list')
      Object.assign(hostForm, resetForm())
    })
}
</script>

<style lang="scss" scoped>
.dialog-footer {
  display: flex;
  justify-content: center;
}
</style>
