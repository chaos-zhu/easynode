<template>
  <el-dialog v-model="visible" width="600px" top="45px" modal-class="host_form_dialog" append-to-body :title="title"
    :close-on-click-modal="false" @open="setDefaultData" @closed="handleClosed">
    <el-form ref="formRef" :model="hostForm" :rules="rules" :hide-required-asterisk="true" label-suffix="："
      label-width="100px" :show-message="false">
      <transition-group name="list" mode="out-in" tag="div">
        <el-form-item key="group" label="分组" prop="group">
          <el-select v-model="hostForm.group" placeholder="实例分组" style="width: 100%;">
            <el-option v-for="item in groupList" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item key="name" label="名称" prop="name">
          <el-input v-model.trim="hostForm.name" clearable placeholder="" autocomplete="off" />
        </el-form-item>
        <div key="instance_info" class="instance_info">
          <el-form-item key="host" class="form_item_host" label="主机" prop="host">
            <el-input v-model.trim="hostForm.host" clearable placeholder="IP" autocomplete="off" />
          </el-form-item>
          <el-form-item key="port" class="form_item_port" label="端口" prop="port">
            <el-input v-model.trim.number="hostForm.port" clearable placeholder="port" autocomplete="off" />
          </el-form-item>
        </div>
        <el-form-item key="username" label="用户名" prop="username">
          <el-autocomplete v-model.trim="hostForm.username" :fetch-suggestions="userSearch" style="width: 100%;"
            clearable>
            <template #default="{ item }">
              <div class="value">{{ item.value }}</div>
            </template>
          </el-autocomplete>
        </el-form-item>
        <el-form-item key="authType" label="认证方式" prop="authType">
          <el-radio v-model.trim="hostForm.authType" value="privateKey">密钥</el-radio>
          <el-radio v-model.trim="hostForm.authType" value="password">密码</el-radio>
          <el-radio v-model.trim="hostForm.authType" value="credential">凭据</el-radio>
        </el-form-item>
        <el-form-item v-if="hostForm.authType === 'privateKey'" key="privateKey" prop="privateKey" label="密钥">
          <el-button type="primary" size="small" @click="handleClickUploadBtn">
            本地私钥...
          </el-button>
          <!-- <el-button type="primary" size="small" @click="handleClickUploadBtn">
            从凭据导入...
          </el-button> -->
          <input ref="privateKeyRef" type="file" name="privateKey" style="display: none;"
            @change="handleSelectPrivateKeyFile">
          <el-input v-model.trim="hostForm.privateKey" type="textarea" :rows="5" clearable autocomplete="off"
            style="margin-top: 5px;" placeholder="-----BEGIN RSA PRIVATE KEY-----" />
        </el-form-item>
        <el-form-item v-if="hostForm.authType === 'password'" key="password" prop="password" label="密码">
          <el-input v-model.trim="hostForm.password" type="password" placeholder="" autocomplete="off" clearable
            show-password />
        </el-form-item>
        <el-form-item v-if="hostForm.authType === 'credential'" key="credential" prop="credential" label="凭据">
          <el-select v-model="hostForm.credential" class="credential_select" placeholder="">
            <template #empty>
              <div class="empty_credential">
                <span>无凭据数据,</span>
                <el-button type="primary" link @click="toCredentials">
                  去添加
                </el-button>
              </div>
            </template>
            <el-option v-for="item in sshList" :key="item.id" :label="item.name" :value="item.id">
              <div class="auth_type_wrap">
                <span>{{ item.name }}</span>
                <span class="auth_type_text">
                  {{ item.authType === 'privateKey' ? '密钥' : '密码' }}
                </span>
              </div>
            </el-option>
          </el-select>
        </el-form-item>
        <el-form-item key="command" prop="command" label="执行指令">
          <el-input v-model="hostForm.command" type="textarea" :rows="5" clearable autocomplete="off"
            placeholder="连接服务器后自动执行的指令(例如: sudo -i)" />
        </el-form-item>
        <el-form-item key="expired" label="到期时间" prop="expired">
          <el-date-picker v-model="hostForm.expired" type="date" style="width: 100%;" value-format="x"
            placeholder="实例到期时间" />
        </el-form-item>
        <el-form-item v-if="hostForm.expired" key="expiredNotify" label="到期提醒" prop="expiredNotify">
          <el-tooltip content="将在实例到期前7、3、1天发送提醒(需在设置中绑定有效邮箱)" placement="right">
            <el-switch v-model="hostForm.expiredNotify" :active-value="true" :inactive-value="false" />
          </el-tooltip>
        </el-form-item>
        <el-form-item key="consoleUrl" label="控制台URL" prop="consoleUrl">
          <el-input v-model.trim="hostForm.consoleUrl" clearable placeholder="用于直达云服务商控制台" autocomplete="off"
            @keyup.enter="handleSave" />
        </el-form-item>
        <el-form-item key="index" label="序号" prop="index">
          <el-input v-model.trim.number="hostForm.index" clearable placeholder="用于实例列表中排序(填写数字)" autocomplete="off" />
        </el-form-item>
        <el-form-item key="remark" label="备注" prop="remark">
          <el-input v-model.trim="hostForm.remark" type="textarea" :rows="3" clearable autocomplete="off"
            placeholder="简单记录实例用途" />
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
import { RSAEncrypt, AESEncrypt, randomStr } from '@utils/index.js'

const { proxy: { $api, $router, $message, $store } } = getCurrentInstance()

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
  port: 22,
  username: 'root',
  authType: 'privateKey',
  password: '',
  privateKey: '',
  credential: '', // credentials -> _id
  index: 0,
  expired: null,
  expiredNotify: false,
  consoleUrl: '',
  remark: '',
  command: ''
})

const hostForm = reactive(resetForm())
const privateKeyRef = ref(null)
const oldHost = ref('')
const rules = computed(() => {
  return {
    group: { required: true, message: '选择一个分组' },
    name: { required: true, message: '输入实例别名', trigger: 'change' },
    host: { required: true, message: '输入IP/域名', trigger: 'change' },
    port: { required: true, type: 'number', message: '输入ssh端口', trigger: 'change' },
    index: { required: true, type: 'number', message: '输入数字', trigger: 'change' },
    // password: [{ required: hostForm.authType === 'password', trigger: 'change' },],
    // privateKey: [{ required: hostForm.authType === 'privateKey', trigger: 'change' },],
    expired: { required: false },
    expiredNotify: { required: false, type: 'boolean' },
    consoleUrl: { required: false },
    remark: { required: false }
  }
})

const formRef = ref(null)

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

const title = computed(() => props.defaultData ? '修改实例' : '新增实例')

let groupList = computed(() => $store.groupList)
let sshList = computed(() => $store.sshList)

const handleClosed = () => {
  // console.log('handleClosed')
  Object.assign(hostForm, resetForm())
  emit('closed')
  nextTick(() => formRef.value.resetFields())
}

const setDefaultData = () => {
  if (!props.defaultData) return
  let { host } = props.defaultData
  oldHost.value = host
  Object.assign(hostForm, { ...props.defaultData })
}

const handleClickUploadBtn = () => {
  privateKeyRef.value.click()
}

const handleSelectPrivateKeyFile = (event) => {
  let file = event.target.files[0]
  let reader = new FileReader()
  reader.onload = (e) => {
    hostForm.privateKey = e.target.result
    privateKeyRef.value.value = ''
  }
  reader.readAsText(file)
}

const defaultUsers = [
  { value: 'root' },
  { value: 'debian' },
  { value: 'centos' },
  { value: 'ubuntu' },
  { value: 'azureuser' },
  { value: 'ec2-user' },
  { value: 'opc' },
  { value: 'admin' },
]
const userSearch = (keyword, cb) => {
  let res = keyword
    ? defaultUsers.filter((item) => item.value.includes(keyword))
    : defaultUsers
  cb(res)
}

const toCredentials = () => {
  visible.value = false
  $router.push({ path: '/credentials' })
}

const handleSave = () => {
  formRef.value.validate()
    .then(async () => {
      let tempKey = randomStr(16)
      let formData = { ...hostForm }
      console.log('formData:', formData)
      // 加密传输
      if (formData.password) formData.password = AESEncrypt(formData.password, tempKey)
      if (formData.privateKey) formData.privateKey = AESEncrypt(formData.privateKey, tempKey)
      if (formData.credential) formData.credential = AESEncrypt(formData.credential, tempKey)
      formData.tempKey = RSAEncrypt(tempKey)
      if (props.defaultData) {
        let { msg } = await $api.updateHost(Object.assign({}, formData, { oldHost: oldHost.value }))
        $message({ type: 'success', center: true, message: msg })
      } else {
        let { msg } = await $api.addHost(formData)
        $message({ type: 'success', center: true, message: msg })
      }
      visible.value = false
      emit('update-list')
      Object.assign(hostForm, resetForm())
    })
}
</script>

<style lang="scss" scoped>
.instance_info {
  display: flex;
  justify-content: space-between;

  .form_item_host {
    width: 60%;
  }

  .form_item_port {
    flex: 1;
  }
}

.empty_credential {
  display: flex;
  align-items: center;
  justify-content: center;
}

.auth_type_wrap {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  .auth_type_text {
    color: var(--el-text-color-secondary);
  }
}

.dialog-footer {
  display: flex;
  justify-content: center;
}
</style>
