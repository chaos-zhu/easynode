<template>
  <div class="credentials_container">
    <div class="header">
      <el-button type="primary" @click="addCredentials">{{ t('credentials.add') }}</el-button>
    </div>
    <el-table v-loading="loading" :data="sshList">
      <el-table-column prop="name" :label="t('credentials.name')" />
      <el-table-column prop="authType" :label="t('credentials.type')">
        <template #default="{ row }">
          {{ row.authType === 'privateKey' ? t('credentials.key') : t('credentials.password') }}
        </template>
      </el-table-column>
      <el-table-column width="160px" :label="t('credentials.actions')">
        <template #default="{ row }">
          <el-button type="primary" @click="handleChange(row)">{{ t('credentials.edit') }}</el-button>
          <el-button v-show="row.id !== 'default'" type="danger" @click="removeSSH(row)">{{ t('credentials.delete') }}</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog
      v-model="sshFormVisible"
      width="600px"
      top="150px"
      :title="isModify ? t('credentials.editTitle') : t('credentials.addTitle')"
      :close-on-click-modal="false"
      @close="clearFormInfo"
    >
      <el-form
        ref="updateFormRef"
        :model="sshForm"
        :rules="rules"
        :hide-required-asterisk="true"
        label-suffix="："
        label-width="100px"
        :show-message="false"
      >
        <el-form-item :label="t('credentials.credentialName')" prop="name">
          <el-input
            v-model="sshForm.name"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item :label="t('credentials.authType')" prop="type">
          <el-radio v-model="sshForm.authType" value="privateKey">{{ t('credentials.key') }}</el-radio>
          <el-radio v-model="sshForm.authType" value="password">{{ t('credentials.password') }}</el-radio>
        </el-form-item>
        <el-form-item v-if="sshForm.authType === 'privateKey'" prop="privateKey" :label="t('credentials.key')">
          <el-button type="primary" size="small" @click="handleClickUploadBtn">
            {{ t('credentials.localPrivateKey') }}
          </el-button>
          <input
            ref="privateKeyRef"
            type="file"
            name="privateKey"
            style="display: none;"
            @change="handleSelectPrivateKeyFile"
          >
          <el-input
            v-model="sshForm.privateKey"
            type="textarea"
            :rows="5"
            clearable
            autocomplete="off"
            style="margin-top: 5px;"
            placeholder="-----BEGIN RSA PRIVATE KEY-----"
          />
        </el-form-item>
        <el-form-item v-if="sshForm.authType === 'privateKey' && showOpenSSHKeyField" :label="t('credentials.privateKeyPassword')">
          <el-input
            v-model="sshForm.openSSHKeyPassword"
            type="password"
            :disabled="!isPlusActive"
            :placeholder="t('credentials.opensshPasswordPlaceholder')"
            show-password
            autocomplete="off"
            clearable
          />
        </el-form-item>
        <el-form-item v-if="sshForm.authType === 'password'" prop="password" :label="t('credentials.password')">
          <el-input
            v-model="sshForm.password"
            type="text"
            placeholder=""
            autocomplete="off"
            clearable
          />
          <div v-if="passwordHasSpace" class="password-warning">
            <el-icon><WarningFilled /></el-icon>
            <span>{{ t('credentials.passwordContainsSpace') }}</span>
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <span>
          <el-button @click="sshFormVisible = false">{{ t('credentials.close') }}</el-button>
          <el-button type="primary" @click="updateForm">{{ isModify ? t('credentials.edit') : t('credentials.add') }}</el-button>
        </span>
      </template>
    </el-dialog>
    <el-dialog
      v-model="keyPasswordVisible"
      :title="t('credentials.inputKeyPasswordTitle')"
      width="400px"
      :close-on-click-modal="false"
    >
      <el-form @submit.prevent>
        <el-form-item :label="t('credentials.password')">
          <el-input
            v-model="keyPassword"
            type="password"
            :placeholder="t('credentials.inputKeyPasswordPlaceholder')"
            show-password
            autocomplete="off"
            clearable
            @keyup.enter="handleDecryptKey"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <span>
          <el-button @click="keyPasswordVisible = false">{{ t('common.cancel') }}</el-button>
          <PlusSupportTip>
            <el-button type="primary" :disabled="!isPlusActive" @click="handleDecryptKey">{{ t('common.confirm') }}</el-button>
          </PlusSupportTip>
        </span>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, computed, nextTick, getCurrentInstance, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { randomStr, AESEncrypt, RSAEncrypt } from '@utils/index.js'
import { WarningFilled } from '@element-plus/icons-vue'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()
const { t } = useI18n()

const loading = ref(false)
const sshFormVisible = ref(false)
let isModify = ref(false)
const sshForm = reactive({
  name: '',
  authType: 'privateKey',
  privateKey: '',
  password: '',
  openSSHKeyPassword: ''
})

const rules = computed(() => {
  return {
    name: { required: true, message: t('credentials.validation.nameRequired'), trigger: 'change' },
    password: [{ required: !isModify.value && sshForm.authType === 'password', trigger: 'change' },],
    privateKey: [{ required: !isModify.value && sshForm.authType === 'privateKey', trigger: 'change' },]
  }
})

const updateFormRef = ref(null)
const privateKeyRef = ref(null)

let sshList = computed(() => $store.sshList)
let isPlusActive = computed(() => $store.isPlusActive)

// 检测密码是否包含空格
const passwordHasSpace = computed(() => {
  return sshForm.authType === 'password' && sshForm.password && sshForm.password.includes(' ')
})

let addCredentials = () => {
  sshForm.id = null
  sshFormVisible.value = true
  isModify.value = false
}
const handleChange = (row) => {
  Object.assign(sshForm, { ...row })
  sshFormVisible.value = true
  isModify.value = true
}

const updateForm = () => {
  updateFormRef.value.validate()
    .then(async () => {
      let formData = { ...sshForm }
      let tempKey = randomStr(16)
      // 加密传输
      if (formData.password) formData.password = AESEncrypt(formData.password, tempKey)
      if (formData.privateKey) formData.privateKey = AESEncrypt(formData.privateKey, tempKey)
      formData.tempKey = RSAEncrypt(tempKey)
      // 加密传输
      if (isModify.value) {
        await $api.updateSSH(formData)
      } else {
        await $api.addSSH(formData)
      }
      sshFormVisible.value = false
      await $store.getSSHList()
      $message.success(t('credentials.messages.success'))
    })
}

const clearFormInfo = () => {
  nextTick(() => updateFormRef.value.resetFields())
}

const removeSSH = ({ id, name }) => {
  $messageBox.confirm(t('credentials.deleteConfirm', { name }), 'Warning', {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
    type: 'warning'
  })
    .then(async () => {
      await $api.removeSSH(id)
      await $store.getSSHList()
      await $store.getHostList()
      $message.success(t('credentials.messages.success'))
    })
}

const handleClickUploadBtn = () => {
  privateKeyRef.value.click()
}

const keyPasswordVisible = ref(false)
const keyPassword = ref('')
const tempPrivateKey = ref('')
const showOpenSSHKeyField = ref(false)

// 监听私钥内容变化，自动检测密钥类型
watch(() => sshForm.privateKey, (newValue) => {
  if (!newValue) return showOpenSSHKeyField.value = false

  // 检查是否是加密的私钥
  if (newValue.includes('ENCRYPTED')) {
    tempPrivateKey.value = newValue
    keyPasswordVisible.value = true
  } else if (newValue.includes('OPENSSH PRIVATE KEY')) {
    // 如果是 OpenSSH 格式，显示密码字段
    showOpenSSHKeyField.value = true
  } else {
    showOpenSSHKeyField.value = false
  }
})

const handleSelectPrivateKeyFile = (event) => {
  let file = event.target.files[0]
  let reader = new FileReader()
  reader.onload = async (e) => {
    sshForm.privateKey = e.target.result
    privateKeyRef.value.value = ''
  }
  reader.readAsText(file)
}

const handleDecryptKey = async () => {
  if (!keyPassword.value) return $message.error(t('credentials.messages.inputKeyPassword'))
  const { data } = await $api.decryptPrivateKey({
    privateKey: tempPrivateKey.value,
    password: keyPassword.value
  })
  sshForm.privateKey = data
  keyPasswordVisible.value = false
  keyPassword.value = ''
  tempPrivateKey.value = ''
  $message.success(t('credentials.decryptSuccess'))
}

</script>

<style lang="scss" scoped>
.credentials_container {
  padding: 0 20px 20px 20px;
  .header {
    padding: 10px;
    display: flex;
    align-items: center;
    justify-content: end;
  }
}

.host_count {
  display: block;
  width: 100px;
  text-align: center;
  font-size: 15px;
  color: #87cf63;
  cursor: pointer;
}

.password-warning {
  display: flex;
  align-items: center;
  gap: 5px;
  margin-top: 5px;
  font-size: 13px;
  color: #CF8A20;
}
</style>