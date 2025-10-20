<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="65px"
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
      <el-form-item key="connectType" label="连接类型" prop="connectType">
        <el-radio-group v-model="hostForm.connectType">
          <el-radio value="ssh">SSH <svg-icon name="icon-linux" class="icon" /></el-radio>
          <PlusSupportTip>
            <el-radio value="rdp" :disabled="!isPlusActive">RDP <svg-icon name="icon-Windows" class="icon" /></el-radio>
          </PlusSupportTip>
        </el-radio-group>
      </el-form-item>
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
      <div key="instance_info" class="instance_info">
        <el-form-item
          v-if="!isBatchModify"
          key="name"
          class="form_item_left"
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
        <el-form-item
          v-if="!isBatchModify"
          key="index"
          class="form_item_right"
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
      </div>
      <div key="instance_info" class="instance_info">
        <el-form-item
          v-if="!isBatchModify"
          key="host"
          class="form_item_left"
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
          class="form_item_right"
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
      <el-form-item
        v-if="isSSH"
        key="authType"
        label="认证方式"
        prop="authType"
      >
        <el-radio v-model="hostForm.authType" value="privateKey">密钥</el-radio>
        <el-radio v-model="hostForm.authType" value="password">密码</el-radio>
        <el-radio v-model="hostForm.authType" value="credential">凭据</el-radio>
      </el-form-item>
      <el-form-item
        v-if="isSSH && hostForm.authType === 'privateKey'"
        key="privateKey"
        prop="privateKey"
        label="密钥"
      >
        <el-button type="primary" size="small" @click="handleClickUploadBtn">
          本地私钥...
        </el-button>
        <input
          ref="privateKeyRef"
          type="file"
          name="privateKey"
          style="display: none;"
          autocomplete="off"
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
        v-if="hostForm.authType === 'password' || isRDP"
        key="password"
        prop="password"
        label="密码"
      >
        <el-input
          v-model.trim="hostForm.password"
          type="password"
          placeholder=""
          autocomplete="new-password"
          clearable
          show-password
        />
      </el-form-item>
      <el-form-item
        v-if="isSSH && hostForm.authType === 'credential'"
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
      <el-collapse v-model="advancedSettingsCollapsed" accordion>
        <el-collapse-item name="advanced" title="其他设置">
          <PlusSupportTip>
            <el-form-item
              v-if="isSSH"
              key="proxyType"
              label="代理类型"
              prop="proxyType"
            >
              <el-radio-group v-model="hostForm.proxyType" :disabled="!isPlusActive">
                <el-radio value="">不使用代理</el-radio>
                <el-radio value="proxyServer">代理服务</el-radio>
                <el-radio value="jumpHosts">跳板机</el-radio>
              </el-radio-group>
            </el-form-item>
          </PlusSupportTip>
          <el-form-item
            v-if="isSSH && hostForm.proxyType === 'jumpHosts'"
            key="jumpHosts"
            prop="jumpHosts"
            label="跳板机"
          >
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
          </el-form-item>
          <el-form-item
            v-if="isSSH && hostForm.proxyType === 'proxyServer'"
            key="proxyServer"
            prop="proxyServer"
            label="代理服务"
          >
            <el-select
              v-model="hostForm.proxyServer"
              placeholder=""
              :disabled="!isPlusActive"
            >
              <template #empty>
                <div class="empty_text">
                  <span>无可用代理服务,</span>
                  <el-button type="primary" link @click="toProxy">
                    去添加
                  </el-button>
                </div>
              </template>
              <el-option
                v-for="item in proxyList"
                :key="item.id"
                :label="item.name"
                :value="item.id"
              >
                <div class="select_warp">
                  <span>{{ item.name }}</span>
                  <span class="auth_type_text">
                    {{ item.type === 'socks5' ? 'SOCKS5' : 'HTTP' }}
                  </span>
                </div>
              </el-option>
            </el-select>
          </el-form-item>
          <el-form-item
            v-if="isSSH"
            key="command"
            prop="command"
            label="登录指令"
          >
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
            v-if="isValidDate(hostForm.expired)"
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
              placeholder="用于直达云服务控制台"
              autocomplete="off"
              @keyup.enter="handleSave"
            />
          </el-form-item>
          <el-form-item key="tag" label="标签" prop="tag">
            <el-input-tag v-model="hostForm.tag" tag-type="success" tag-effect="plain" />
          </el-form-item>
        </el-collapse-item>
      </el-collapse>
      <!-- <el-form-item key="remark" label="备注" prop="remark">
        <el-input
          v-model="hostForm.remark"
          type="textarea"
          :rows="3"
          clearable
          autocomplete="off"
          placeholder="简单记录实例用途"
        />
      </el-form-item> -->
    </el-form>
    <template #footer>
      <span class="dialog-footer">
        <el-button @click="visible = false">关闭</el-button>
        <el-button v-if="!isBatchModify" type="primary" @click="handleSave">确认</el-button>
        <PlusSupportTip v-else>
          <el-button type="primary" :disabled="!isPlusActive" @click="handleSave">确认</el-button>
        </PlusSupportTip>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick, watch } from 'vue'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'
import { RSAEncrypt, AESEncrypt, randomStr } from '@utils/index.js'
import { isValidDate } from '@/utils'

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
  connectType: 'ssh', // ssh, rdp
  group: 'default',
  name: '',
  host: '',
  port: 22,
  username: 'root',
  authType: 'privateKey', // privateKey, password, credential
  password: '',
  privateKey: '',
  credential: '', // credentials -> _id
  index: 0,
  expired: null,
  expiredNotify: false,
  consoleUrl: '',
  tag: [],
  command: '',
  proxyType: '', // , jumpHosts, proxyServer
  jumpHosts: [],
  proxyServer: ''
}

const hostForm = ref({ ...formField })
const privateKeyRef = ref(null)
const formRef = ref(null)

// 折叠状态，从localStorage中读取
const advancedSettingsCollapsed = ref(
  JSON.parse(localStorage.getItem('hostFormAdvancedSettingsCollapsed') || 'false')
    ? ['advanced',]
    : []
)

const isBatchModify = computed(() => props.isBatchModify)
const batchHosts = computed(() => props.batchHosts)
const defaultData = computed(() => props.defaultData)
const rules = computed(() => {
  return {
    connectType: { required: true, message: '选择一个连接类型' },
    group: { required: !isBatchModify.value, message: '选择一个分组' },
    name: { required: !isBatchModify.value, message: '输入实例别名', trigger: 'change' },
    host: { required: !isBatchModify.value, message: '输入IP/域名', trigger: 'change' },
    port: { required: !isBatchModify.value, type: 'number', message: '输入ssh端口', trigger: 'change' },
    jumpHosts: { required: false, type: 'array' },
    index: { required: !isBatchModify.value, type: 'number', message: '输入数字', trigger: 'change' },
    // password: [{ required: hostForm.authType === 'password', trigger: 'change' },],
    // privateKey: [{ required: hostForm.authType === 'privateKey', trigger: 'change' },],
    expired: { required: false },
    expiredNotify: { required: false, type: 'boolean' },
    consoleUrl: { required: false },
    tag: { required: false, type: 'array' }
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

// 连接类型计算属性
const isSSH = computed(() => hostForm.value.connectType === 'ssh')
const isRDP = computed(() => hostForm.value.connectType === 'rdp')

const groupList = computed(() => $store.groupList)
const sshList = computed(() => $store.sshList)
const hostList = computed(() => $store.hostList)
const confHostList = computed(() => hostList.value?.filter(item => item.isConfig))
const proxyList = computed(() => $store.proxyList)

// 监听连接类型变化，自动修正port&Username
watch(
  () => hostForm.value.connectType,
  (newVal) => {
    if (defaultData.value || isBatchModify.value) return
    if (newVal === 'rdp') {
      hostForm.value.port = 3389
      hostForm.value.username = 'Administrator'
    }
    if (newVal === 'ssh') {
      hostForm.value.port = 22
      hostForm.value.username = 'root'
    }
  }
)

// 监听折叠状态变化，保存到localStorage
watch(advancedSettingsCollapsed, (newVal) => {
  localStorage.setItem('hostFormAdvancedSettingsCollapsed', JSON.stringify(newVal.includes('advanced')))
}, { deep: true })

const setDefaultData = () => {
  if (!defaultData.value) {
    // 添加新实例时，设置index为当前最大index + 1
    const maxIndex = Math.max(...hostList.value.map(host => host.index || 0), 0)
    hostForm.value.index = maxIndex + 1
    return
  }
  // eslint-disable-next-line no-unused-vars
  let { id, ...rest } = defaultData.value
  for (let [key,] of Object.entries(hostForm.value)) {
    if (rest[key] !== undefined) hostForm.value[key] = rest[key]
  }
  hostForm.value.id = id
}

const setBatchDefaultData = () => {
  if (!isBatchModify.value) return
  Object.assign(hostForm.value, { ...formField }, { group: '', port: '', username: '', authType: '', proxyType: '', jumpHosts: [], proxyServer: '' })
}

const handleOpen = async () => {
  if (isBatchModify.value) {
    setBatchDefaultData()
  } else {
    setDefaultData()
  }
  await nextTick()
  formRef.value.clearValidate()
}

const handleClosed = async () => {
  emit('closed')
  hostForm.value = { ...formField }
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

const defaultWindowsUsers = [
  { value: 'Administrator' },
  { value: 'admin' },
  { value: 'user' },
  { value: 'Guest' },
]

const userSearch = (keyword, cb) => {
  // 根据连接类型选择不同的用户名建议
  const users = isRDP.value ? defaultWindowsUsers : defaultUsers
  let res = keyword
    ? users.filter((item) => item.value.toLowerCase().includes(keyword.toLowerCase()))
    : users
  cb(res)
}

const toProxy = () => {
  visible.value = false
  $router.push({ path: '/setting', query: { tabKey: 'proxy' } })
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
        let updateFieldData = Object.fromEntries(Object.entries(formData).filter(([key, value]) => {
          if (Array.isArray(value)) return value.length > 0
          return Boolean(value)
        })) // 剔除掉未更改的值
        if (isRDP.value) updateFieldData.authType = 'password'
        let { authType = '' } = updateFieldData
        if (authType && !updateFieldData[authType]) {
          delete updateFieldData.authType
          delete updateFieldData.privateKey
          delete updateFieldData.password
          delete updateFieldData.credential
        }
        if (Object.keys(updateFieldData).length === 0) return $message.warning('没有任何修改')
        console.log(updateFieldData)
        if (updateFieldData.authType) {
          let tempKey = randomStr(16)
          updateFieldData[authType] = AESEncrypt(updateFieldData[authType], tempKey)
          updateFieldData.tempKey = RSAEncrypt(tempKey)
        }
        let updateIds = batchHosts.value.map(item => item.id)
        let { msg } = await $api.batchUpdateHost({ updateIds, updateFieldData })
        $message({ type: 'success', center: true, message: msg })
      } else {
        if (isRDP.value) formData.authType = 'password'
        let { authType } = formData
        if (formData[authType]) {
          let tempKey = randomStr(16)
          formData[authType] = AESEncrypt(formData[authType], tempKey)
          formData.tempKey = RSAEncrypt(tempKey)
        }
        if (defaultData.value) {
          let { msg } = await $api.updateHost({ ...formData })
          $message({ type: 'success', center: true, message: msg })
        } else {
          let { msg } = await $api.addHost({ ...formData })
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

  .form_item_left {
    width: 60%;
  }

  .form_item_right {
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
