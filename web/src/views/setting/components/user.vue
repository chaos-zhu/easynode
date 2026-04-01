<template>
  <el-form
    ref="formRef"
    class="password-form"
    :model="formData"
    :rules="rules"
    :hide-required-asterisk="true"
    label-suffix="："
    label-width="86px"
    :show-message="false"
  >
    <el-form-item :label="t('settings.user.oldUsername')" prop="oldLoginName" class="form_item">
      <el-input
        v-model.trim="formData.oldLoginName"
        clearable
        :placeholder="t('settings.user.oldUsername')"
        autocomplete="off"
        class="input"
      />
    </el-form-item>
    <el-form-item :label="t('settings.user.oldPassword')" prop="oldPwd" class="form_item">
      <el-input
        v-model.trim="formData.oldPwd"
        type="password"
        clearable
        show-password
        :placeholder="t('settings.user.oldPassword')"
        autocomplete="off"
        class="input"
      />
    </el-form-item>
    <el-form-item :label="t('settings.user.newUsername')" prop="newLoginName" class="form_item">
      <el-input
        v-model.trim="formData.newLoginName"
        clearable
        :placeholder="t('settings.user.newUsername')"
        autocomplete="off"
        class="input"
      />
    </el-form-item>
    <el-form-item :label="t('settings.user.newPassword')" prop="newPwd" class="form_item">
      <el-input
        v-model.trim="formData.newPwd"
        type="password"
        show-password
        clearable
        :placeholder="t('settings.user.newPassword')"
        autocomplete="off"
        class="input"
        @keyup.enter="handleUpdate"
      />
    </el-form-item>
    <el-form-item>
      <el-button type="primary" :loading="loading" @click="handleUpdate">{{ t('common.confirm') }}</el-button>
    </el-form-item>
  </el-form>
  <h2 class="mfa2_title">{{ t('settings.user.mfaTitle') }}</h2>
  <div v-if="isEnableMFA2">
    <span class="enable_text">{{ t('settings.user.enabled') }}</span>
    <el-button class="disable_btn" type="danger" @click="handleDisableMFA2">{{ t('settings.user.disable') }}</el-button>
  </div>
  <template v-else>
    <el-button v-if="startEnableMFA2" type="primary" @click="handleMFA2">{{ t('settings.user.enable') }}</el-button>
    <template v-else>
      <div class="mfa2_container">
        <p>
          {{ t('settings.user.mfaStep1Prefix') }}
          <a href="https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2" target="_blank" class="link">Google Authenticator</a>
          {{ t('settings.user.mfaStep1Middle') }}
          <span class="secret">{{ MFA2Data.secret }}</span>
        </p>
        <img :src="MFA2Data.qrImage" :alt="MFA2Data.secret">
        <p>{{ t('settings.user.mfaStep2') }}</p>
        <el-input
          v-model="mfa2Token"
          class="mfa2_input"
          clearable
          :placeholder="t('settings.user.mfaTokenPlaceholder')"
          autofocus
          @keyup.enter="handleEnableMFA2"
        />
        <el-button type="primary" @click="handleEnableMFA2">{{ t('common.save') }}</el-button>
      </div>
    </template>
  </template>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'
import { RSAEncrypt } from '@utils/index.js'

const { proxy: { $api, $message, $messageBox, $store, $router } } = getCurrentInstance()
const { t } = useI18n()

const loading = ref(false)
const formRef = ref(null)
const formData = reactive({
  oldLoginName: '',
  oldPwd: '',
  newLoginName: '',
  newPwd: ''
})
const rules = reactive({
  oldLoginName: { required: true, message: t('settings.user.validation.enterOldUsername'), trigger: 'change' },
  oldPwd: { required: true, message: t('settings.user.validation.enterOldPassword'), trigger: 'change' },
  newLoginName: { required: true, message: t('settings.user.validation.enterNewUsername'), trigger: 'change' },
  newPwd: { required: true, message: t('settings.user.validation.enterNewPassword'), trigger: 'change' }
})

const startEnableMFA2 = ref(true)
const isEnableMFA2 = ref(false)
const MFA2Data = ref({
  qrImage: '',
  secret: ''
})
const mfa2Token = ref('')

const handleUpdate = () => {
  formRef.value.validate()
    .then(async () => {
      $messageBox.confirm(
        t('settings.user.changeLoginConfirm'),
        t('settings.user.changeLoginTitle'),
        {
          confirmButtonText: t('common.confirm'),
          cancelButtonText: t('common.cancel'),
          type: 'warning',
          showCancelButton: true,
          cancelButtonClass: 'el-button--info',
          confirmButtonClass: 'el-button--warning'
        }
      ).then(async () => {
        let { oldLoginName, oldPwd, newLoginName, newPwd } = formData
        oldPwd = RSAEncrypt(oldPwd)
        newPwd = RSAEncrypt(newPwd)
        let { msg } = await $api.updatePwd({ oldLoginName, oldPwd, newLoginName, newPwd })
        $message({ type: 'success', center: true, message: msg })
        formData.oldLoginName = ''
        formData.oldPwd = ''
        formData.newLoginName = ''
        formData.newPwd = ''
        formRef.value.resetFields()
        if (oldLoginName !== newLoginName) {
          $message({ type: 'success', center: true, message: t('settings.user.usernameChangedRelogin') })
          $store.removeLoginInfo()
          $router.push('/login')
        }
      })
    })
}

const getMFA2Status = async () => {
  let { data } = await $api.getMFA2Status()
  isEnableMFA2.value = data
}
const handleMFA2 = async () => {
  let { data } = await $api.getMFA2QR()
  MFA2Data.value = data
  startEnableMFA2.value = false
}

const handleEnableMFA2 = async () => {
  if (!mfa2Token.value) return $message({ type: 'error', center: true, message: t('settings.user.enterMfaToken') })
  let { msg } = await $api.enableMFA2({ token: mfa2Token.value })
  $message({ type: 'success', center: true, message: msg })
  getMFA2Status()
}
const handleDisableMFA2 = async () => {
  $messageBox.prompt(t('settings.user.disableMfaPrompt'), t('settings.user.disableMfaTitle'), {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
    inputPlaceholder: t('settings.user.mfaTokenPlaceholder'),
    inputType: 'text',
    inputPattern: /^\d{6}$/,
    inputErrorMessage: t('settings.user.invalidMfaToken'),
    beforeClose: (action, instance, done) => {
      if (action === 'confirm') {
        instance.confirmButtonLoading = true
        instance.confirmButtonText = t('settings.user.verifying')
        $api.disableMFA2({ token: instance.inputValue })
          .then(({ msg }) => {
            $message({ type: 'success', center: true, message: msg })
            getMFA2Status()
            done()
            startEnableMFA2.value = true
            mfa2Token.value = ''
          })
          .finally(() => {
            instance.confirmButtonLoading = false
            instance.confirmButtonText = t('common.confirm')
          })
      } else {
        done()
      }
    }
  })
}

onMounted(() => {
  getMFA2Status()
})
</script>

<style lang="scss" scoped>
.password-form {
  .form_item {
    .input {
      width: 450px;
    }
  }
}
.mfa2_title {
  font-size: 18px;
  margin-bottom: 20px;
}
.mfa2_container {
  align-items: flex-start;
  color: var(--el-text-color-regular);
  font-size: var(--el-form-label-font-size);
  line-height: 32px;
  .secret {
    color: var(--el-color-primary);
    text-decoration: underline;
  }
  img {
      width: 150px;
      height: 150px;
      border-radius: 5px;
  }
  .mfa2_input {
    width: 150px;
    margin-right: 15px;
  }
}
.enable_text {
  color: var(--el-color-primary);
}
.disable_btn {
  margin: 0 15px;
}
</style>
