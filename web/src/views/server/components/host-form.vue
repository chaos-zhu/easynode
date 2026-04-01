<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="65px"
    :append-to-body="false"
    :title="title"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    @open="handleOpen"
    @closed="handleClosed"
  >
    <div v-if="isBatchModify" class="batch_info">
      <el-alert :title="t('server.form.batchModifyHint')" type="warning" :closable="false" />
      <el-tag
        v-for="item in batchHosts"
        :key="item.id"
        class="host_name_tag"
        type="success"
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
      <el-form-item key="connectType" :label="t('server.form.connectType')" prop="connectType">
        <el-radio-group v-model="hostForm.connectType">
          <el-radio value="ssh">SSH <svg-icon name="icon-linux" class="icon" /></el-radio>
          <PlusSupportTip>
            <el-radio value="rdp" :disabled="!isPlusActive">RDP <svg-icon name="icon-Windows" class="icon" /></el-radio>
          </PlusSupportTip>
        </el-radio-group>
      </el-form-item>
      <el-form-item key="group" :label="t('server.form.group')" prop="group">
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
          :label="t('server.form.name')"
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
          :label="t('server.form.index')"
          prop="index"
        >
          <el-input
            v-model.trim.number="hostForm.index"
            clearable
            :placeholder="t('server.form.indexPlaceholder')"
            autocomplete="off"
          />
        </el-form-item>
      </div>
      <div key="instance_info" class="instance_info">
        <el-form-item
          v-if="!isBatchModify"
          key="host"
          class="form_item_left"
          :label="t('server.form.host')"
          prop="host"
        >
          <el-input
            v-model.trim="hostForm.host"
            clearable
            :placeholder="t('server.form.ipPlaceholder')"
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item
          key="port"
          class="form_item_right"
          :label="t('server.form.port')"
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
      <el-form-item key="username" :label="t('server.form.username')" prop="username">
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
        :label="t('server.form.authType')"
        prop="authType"
      >
        <el-radio v-model="hostForm.authType" value="privateKey">{{ t('server.privateKey') }}</el-radio>
        <el-radio v-model="hostForm.authType" value="password">{{ t('server.password') }}</el-radio>
        <el-radio v-model="hostForm.authType" value="credential">{{ t('menu.credentials') }}</el-radio>
      </el-form-item>
      <el-form-item
        v-if="isSSH && hostForm.authType === 'privateKey'"
        key="privateKey"
        prop="privateKey"
        :label="t('server.privateKey')"
      >
        <el-button type="primary" size="small" @click="handleClickUploadBtn">
          {{ t('credentials.localPrivateKey') }}
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
        <div v-if="hasEncryptedKey" class="key_warning">
          <el-icon><WarningFilled /></el-icon>
          <span>{{ t('server.form.encryptedKeyPrefix') }}</span>
          <a href="javascript:void(0)" @click="toCredentials">{{ t('menu.credentials') }}</a>
          <span>{{ t('server.form.encryptedKeySuffix') }}</span>
        </div>
      </el-form-item>
      <el-form-item
        v-if="hostForm.authType === 'password' || isRDP"
        key="password"
        prop="password"
        :label="t('server.password')"
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
        :label="t('menu.credentials')"
      >
        <el-select v-model="hostForm.credential" placeholder="">
          <template #empty>
            <div class="empty_text">
              <span>{{ t('server.form.noCredentialData') }}</span>
              <el-button type="primary" link @click="toCredentials">
                {{ t('server.form.goAdd') }}
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
                {{ item.authType === 'privateKey' ? t('server.privateKey') : t('server.password') }}
              </span>
            </div>
          </el-option>
        </el-select>
      </el-form-item>
      <el-collapse v-model="advancedSettingsCollapsed" accordion>
        <el-collapse-item name="advanced" :title="t('terminal.otherSettings')">
          <PlusSupportTip>
            <el-form-item
              v-if="isSSH"
              key="proxyType"
              :label="t('server.proxyType')"
              prop="proxyType"
            >
              <el-radio-group v-model="hostForm.proxyType" :disabled="!isPlusActive">
                <el-radio value="">{{ t('server.form.noProxy') }}</el-radio>
                <el-radio value="proxyServer">{{ t('server.proxyServerLabel') }}</el-radio>
                <el-radio value="jumpHosts">{{ t('server.jumpHost') }}</el-radio>
              </el-radio-group>
            </el-form-item>
          </PlusSupportTip>
          <el-form-item
            v-if="isSSH && hostForm.proxyType === 'jumpHosts'"
            key="jumpHosts"
            prop="jumpHosts"
            :label="t('server.jumpHost')"
          >
            <el-select
              v-model="hostForm.jumpHosts"
              :placeholder="t('server.form.jumpHostPlaceholder')"
              multiple
              :disabled="!isPlusActive"
            >
              <template #empty>
                <div class="empty_text">
                  <span>{{ t('server.form.noJumpHost') }}</span>
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
            :label="t('server.proxyServerLabel')"
          >
            <el-select
              v-model="hostForm.proxyServer"
              placeholder=""
              :disabled="!isPlusActive"
            >
              <template #empty>
                <div class="empty_text">
                  <span>{{ t('server.form.noProxyService') }}</span>
                  <el-button type="primary" link @click="toProxy">
                    {{ t('server.form.goAdd') }}
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
            :label="t('server.form.loginCommand')"
          >
            <el-input
              v-model="hostForm.command"
              type="textarea"
              :rows="3"
              clearable
              autocomplete="off"
              :placeholder="t('server.form.loginCommandPlaceholder')"
            />
          </el-form-item>

          <el-form-item key="expired" :label="t('server.expiredAt')" prop="expired">
            <el-date-picker
              v-model="hostForm.expired"
              type="date"
              :editable="false"
              style="width: 100%;"
              value-format="x"
              :placeholder="t('server.form.expiredPlaceholder')"
            />
          </el-form-item>
          <el-form-item
            v-if="isValidDate(hostForm.expired)"
            key="expiredNotify"
            :label="t('server.form.expiredNotify')"
            prop="expiredNotify"
          >
            <el-tooltip :content="t('server.form.expiredNotifyTip')" placement="right">
              <el-switch v-model="hostForm.expiredNotify" :active-value="true" :inactive-value="false" />
            </el-tooltip>
          </el-form-item>
          <el-form-item key="consoleUrl" :label="t('server.consoleUrl')" prop="consoleUrl">
            <el-input
              v-model.trim="hostForm.consoleUrl"
              clearable
              :placeholder="t('server.form.consoleUrlPlaceholder')"
              autocomplete="off"
              @keyup.enter="handleSave"
            />
          </el-form-item>
          <el-form-item key="tag" :label="t('server.tag')" prop="tag">
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
        <el-button @click="visible = false">{{ t('common.close') }}</el-button>
        <el-button v-if="!isBatchModify" type="primary" @click="handleSave">{{ t('common.confirm') }}</el-button>
        <PlusSupportTip v-else>
          <el-button type="primary" :disabled="!isPlusActive" @click="handleSave">{{ t('common.confirm') }}</el-button>
        </PlusSupportTip>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'
import { RSAEncrypt, AESEncrypt, randomStr } from '@utils/index.js'
import { isValidDate } from '@/utils'
import { WarningFilled } from '@element-plus/icons-vue'

const { proxy: { $api, $router, $message, $store } } = getCurrentInstance()
const { t } = useI18n()

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
    connectType: { required: true, message: t('server.form.validation.connectType') },
    group: { required: !isBatchModify.value, message: t('server.form.validation.group') },
    name: { required: !isBatchModify.value, message: t('server.form.validation.name'), trigger: 'change' },
    host: { required: !isBatchModify.value, message: t('server.form.validation.host'), trigger: 'change' },
    port: { required: !isBatchModify.value, type: 'number', message: t('server.form.validation.port'), trigger: 'change' },
    jumpHosts: { required: false, type: 'array' },
    index: { required: !isBatchModify.value, type: 'number', message: t('server.group.numberRequired'), trigger: 'change' },
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
  return isBatchModify.value ? t('server.batchModify') : (defaultData.value ? t('server.form.editTitle') : t('server.form.addTitle'))
})

// 连接类型计算属性
const isSSH = computed(() => hostForm.value.connectType === 'ssh')
const isRDP = computed(() => hostForm.value.connectType === 'rdp')

// 检测是否为加密密钥或需要密码的 OpenSSH 密钥
const hasEncryptedKey = computed(() => {
  const privateKey = hostForm.value.privateKey
  if (!privateKey) return false
  return privateKey.includes('ENCRYPTED') || privateKey.includes('OPENSSH PRIVATE KEY')
})

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
        if (Object.keys(updateFieldData).length === 0) return $message.warning(t('server.form.noChanges'))
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

.key_warning {
  display: flex;
  align-items: center;
  gap: 3px;
  margin-top: 5px;
  font-size: 13px;
  color: #CF8A20;
}
</style>
