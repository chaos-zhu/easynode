<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="45px"
    modal-class="host_form_dialog"
    :append-to-body="false"
    :title="title"
    :close-on-click-modal="false"
    @open="handleOpen"
    @closed="handleClosed"
  >
    <div v-if="isBatchModify" class="batch_info">
      <el-alert title="正在进行批量修改操作,留空默认保留原值" type="warning" :closable="false" />
      <el-tag
        v-for="item in batchHosts"
        :key="item.id"
        class="host_name_tag"
        type="warning"
      >
        {{ item.name }}
      </el-tag>
    </div>
    <el-form
      ref="formRef"
      :model="hostForm"
      :rules="rules"
      :hide-required-asterisk="true"
      label-suffix="："
      label-width="100px"
      :show-message="false"
    >
      <transition-group name="list" mode="out-in" tag="div">
        <el-form-item key="group" label="分组" prop="group">
          <el-select
            v-model="hostForm.group"
            placeholder=""
            clearable
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
        <el-form-item
          v-if="!isBatchModify"
          key="name"
          label="名称"
          prop="name"
        >
          <el-input
            v-model="hostForm.name"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <div key="instance_info" class="instance_info">
          <el-form-item
            v-if="!isBatchModify"
            key="host"
            class="form_item_host"
            label="主机"
            prop="host"
          >
            <el-input
              v-model.trim="hostForm.host"
              clearable
              placeholder="IP"
              autocomplete="off"
            />
          </el-form-item>
          <el-form-item
            key="port"
            class="form_item_port"
            label="端口"
            prop="port"
          >
            <el-input
              v-model.trim.number="hostForm.port"
              clearable
              placeholder=""
              autocomplete="off"
            />
          </el-form-item>
        </div>
        <el-form-item key="username" label="用户名" prop="username">
          <el-autocomplete
            v-model.trim="hostForm.username"
            :fetch-suggestions="userSearch"
            style="width: 100%;"
            clearable
          >
            <template #default="{ item }">
              <div class="value">{{ item.value }}</div>
            </template>
          </el-autocomplete>
        </el-form-item>
        <el-form-item key="authType" label="认证方式" prop="authType">
          <el-radio v-model="hostForm.authType" value="privateKey">密钥</el-radio>
          <el-radio v-model="hostForm.authType" value="password">密码</el-radio>
          <el-radio v-model="hostForm.authType" value="credential">凭据</el-radio>
        </el-form-item>
        <el-form-item
          v-if="hostForm.authType === 'privateKey'"
          key="privateKey"
          prop="privateKey"
          label="密钥"
        >
          <el-button type="primary" size="small" @click="handleClickUploadBtn">
            本地私钥...
          </el-button>
          <!-- <el-button type="primary" size="small" @click="handleClickUploadBtn">
            从凭据导入...
          </el-button> -->
          <input
            ref="privateKeyRef"
            type="file"
            name="privateKey"
            style="display: none;"
            @change="handleSelectPrivateKeyFile"
          >
          <el-input
            v-model="hostForm.privateKey"
            type="textarea"
            :rows="3"
            clearable
            autocomplete="off"
            style="margin-top: 5px;"
            placeholder="-----BEGIN RSA PRIVATE KEY-----"
          />
        </el-form-item>
        <el-form-item
          v-if="hostForm.authType === 'password'"
          key="password"
          prop="password"
          label="密码"
        >
          <el-input
            v-model.trim="hostForm.password"
            type="password"
            placeholder=""
            autocomplete="off"
            clearable
            show-password
          />
        </el-form-item>
        <el-form-item
          v-if="hostForm.authType === 'credential'"
          key="credential"
          prop="credential"
          label="凭据"
        >
          <el-select v-model="hostForm.credential" placeholder="">
            <template #empty>
              <div class="empty_text">
                <span>无凭据数据,</span>
                <el-button type="primary" link @click="toCredentials">
                  去添加
                </el-button>
              </div>
            </template>
            <el-option
              v-for="item in sshList"
              :key="item.id"
              :label="item.name"
              :value="item.id"
            >
              <div class="select_warp">
                <span>{{ item.name }}</span>
                <span class="auth_type_text">
                  {{ item.authType === 'privateKey' ? '密钥' : '密码' }}
                </span>
              </div>
            </el-option>
          </el-select>
        </el-form-item>
        <el-form-item
          key="jumpHosts"
          prop="jumpHosts"
          label="跳板机"
        >
          <PlusSupportTip>
            <el-select
              v-model="hostForm.jumpHosts"
              placeholder="支持多选,跳板机连接顺序从前到后"
              multiple
              :disabled="!isPlusActive"
            >
              <template #empty>
                <div class="empty_text">
                  <span>无可用跳板机器</span>
                </div>
              </template>
              <el-option
                v-for="item in confHostList"
                :key="item.id"
                :label="item.name"
                :value="item.id"
              >
                <div class="select_wrap">
                  <span>{{ item.name }}</span>
                </div>
              </el-option>
            </el-select>
          </PlusSupportTip>
        </el-form-item>
        <el-form-item key="command" prop="command" label="登录指令">
          <el-input
            v-model="hostForm.command"
            type="textarea"
            :rows="3"
            clearable
            autocomplete="off"
            placeholder="连接服务器后自动执行的指令(例如: sudo -i)"
          />
        </el-form-item>

        <el-form-item key="expired" label="到期时间" prop="expired">
          <el-date-picker
            v-model="hostForm.expired"
            type="date"
            :editable="false"
            style="width: 100%;"
            value-format="x"
            placeholder="实例到期时间"
          />
        </el-form-item>
        <el-form-item
          v-if="hostForm.expired"
          key="expiredNotify"
          label="到期提醒"
          prop="expiredNotify"
        >
          <el-tooltip content="将在实例到期前7、3、1天发送提醒(需在设置中绑定有效邮箱)" placement="right">
            <el-switch v-model="hostForm.expiredNotify" :active-value="true" :inactive-value="false" />
          </el-tooltip>
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
        <el-form-item key="clientPort" label="客户端端口" prop="clientPort">
          <el-input
            v-model.trim.number="hostForm.clientPort"
            clearable
            placeholder="客户端上报信息端口(默认22022)"
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item
          v-if="!isBatchModify"
          key="index"
          label="序号"
          prop="index"
        >
          <el-input
            v-model.trim.number="hostForm.index"
            clearable
            placeholder="用于实例列表中排序(填写数字)"
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item key="remark" label="备注" prop="remark">
          <el-input
            v-model="hostForm.remark"
            type="textarea"
            :rows="3"
            clearable
            autocomplete="off"
            placeholder="简单记录实例用途"
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
import { ref, computed, getCurrentInstance, nextTick } from 'vue'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'
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
  },
  isBatchModify: {
    required: false,
    type: Boolean,
    default: false
  },
  batchHosts: {
    required: false,
    type: Array,
    default: null
  }
})
const emit = defineEmits(['update:show', 'update-list', 'closed',])

const formField = {
  group: 'default',
  name: '',
  host: '',
  port: 22,
  username: 'root',
  authType: 'privateKey',
  password: '',
  privateKey: '',
  credential: '', // credentials -> _id
  clientPort: 22022,
  index: 0,
  expired: null,
  expiredNotify: false,
  consoleUrl: '',
  remark: '',
  command: '',
  jumpHosts: []
}

let hostForm = ref({ ...formField })
let privateKeyRef = ref(null)
let oldHost = ref('')
let formRef = ref(null)

let isBatchModify = computed(() => props.isBatchModify)
let batchHosts = computed(() => props.batchHosts)
let defaultData = computed(() => props.defaultData)
const rules = computed(() => {
  return {
    group: { required: !isBatchModify.value, message: '选择一个分组' },
    name: { required: !isBatchModify.value, message: '输入实例别名', trigger: 'change' },
    host: { required: !isBatchModify.value, message: '输入IP/域名', trigger: 'change' },
    port: { required: !isBatchModify.value, type: 'number', message: '输入ssh端口', trigger: 'change' },
    clientPort: { required: false, type: 'number' },
    jumpHosts: { required: false, type: 'array' },
    index: { required: !isBatchModify.value, type: 'number', message: '输入数字', trigger: 'change' },
    // password: [{ required: hostForm.authType === 'password', trigger: 'change' },],
    // privateKey: [{ required: hostForm.authType === 'privateKey', trigger: 'change' },],
    expired: { required: false },
    expiredNotify: { required: false, type: 'boolean' },
    consoleUrl: { required: false },
    remark: { required: false }
  }
})
const isPlusActive = computed(() => $store.isPlusActive)

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

const title = computed(() => {
  return isBatchModify.value ? '批量修改实例' : (defaultData.value ? '修改实例' : '添加实例')
})

let groupList = computed(() => $store.groupList)
let sshList = computed(() => $store.sshList)
let hostList = computed(() => $store.hostList)
let confHostList = computed(() => {
  return hostList.value?.filter(item => item.isConfig)
})

const setDefaultData = () => {
  if (!defaultData.value) return
  // eslint-disable-next-line no-unused-vars
  let { host, monitorData, ...rest } = defaultData.value
  oldHost.value = host
  Object.assign(hostForm.value, { host, ...rest })
}

const setBatchDefaultData = () => {
  if (!isBatchModify.value) return
  Object.assign(hostForm.value, { ...formField }, { group: '', port: '', username: '', authType: '', clientPort: '', jumpHosts: [] })
}
const handleOpen = async () => {
  setDefaultData()
  setBatchDefaultData()
  await nextTick()
  formRef.value.clearValidate()
}

const handleClosed = async () => {
  emit('closed')
  Object.assign(hostForm.value, { ...formField })
  await nextTick()
  formRef.value.resetFields()
}

const handleClickUploadBtn = () => {
  privateKeyRef.value.click()
}

const handleSelectPrivateKeyFile = (event) => {
  let file = event.target.files[0]
  let reader = new FileReader()
  reader.onload = (e) => {
    hostForm.value.privateKey = e.target.result
    privateKeyRef.value = ''
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
      let formData = { ...hostForm.value }
      if (isBatchModify.value) {
        // eslint-disable-next-line
        let updateFileData = Object.fromEntries(Object.entries(formData).filter(([key, value]) => Boolean(value))) // 剔除掉未更改的值
        if (Object.keys(updateFileData).length === 0) return $message.warning('没有任何修改')
        console.log(updateFileData)
        let newHosts = batchHosts.value
          .map(item => ({ ...item, ...updateFileData }))
          .map(item => {
            const { authType } = item
            let tempKey = randomStr(16)
            if (item[authType]) item[authType] = AESEncrypt(item[authType], tempKey)
            item.tempKey = RSAEncrypt(tempKey)
            return item
          })
        let { msg } = await $api.updateHost({ hosts: newHosts })
        $message({ type: 'success', center: true, message: msg })
      } else {
        let tempKey = randomStr(16)
        let { authType } = formData
        if (formData[authType]) formData[authType] = AESEncrypt(formData[authType], tempKey)
        formData.tempKey = RSAEncrypt(tempKey)
        if (defaultData.value) {
          let { msg } = await $api.updateHost(Object.assign({}, formData, { oldHost: oldHost.value }))
          $message({ type: 'success', center: true, message: msg })
        } else {
          let { msg } = await $api.addHost(formData)
          $message({ type: 'success', center: true, message: msg })
        }
      }
      visible.value = false
      emit('update-list', { host: isBatchModify.value ? batchHosts.value : hostForm.value.host })
    })
}
</script>

<style lang="scss" scoped>
.batch_info {
  :deep(.el-alert) {
    padding-top: 2px;
    padding-bottom: 2px;
    margin-bottom: 5px;
  }
  :deep(.el-tag) {
    margin-right: 10px;
    margin-bottom: 6px;
  }
}
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

.empty_text {
  display: flex;
  align-items: center;
  justify-content: center;
}

.select_warp {
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
