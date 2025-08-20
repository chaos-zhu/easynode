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
    <el-form-item label="原用户名" prop="oldLoginName" class="form_item">
      <el-input
        v-model.trim="formData.oldLoginName"
        clearable
        placeholder=""
        autocomplete="off"
        class="input"
      />
    </el-form-item>
    <el-form-item label="原密码" prop="oldPwd" class="form_item">
      <el-input
        v-model.trim="formData.oldPwd"
        type="password"
        clearable
        show-password
        placeholder=""
        autocomplete="off"
        class="input"
      />
    </el-form-item>
    <el-form-item label="新用户名" prop="newLoginName" class="form_item">
      <el-input
        v-model.trim="formData.newLoginName"
        clearable
        placeholder=""
        autocomplete="off"
        class="input"
      />
    </el-form-item>
    <el-form-item label="新密码" prop="newPwd" class="form_item">
      <el-input
        v-model.trim="formData.newPwd"
        type="password"
        show-password
        clearable
        placeholder=""
        autocomplete="off"
        class="input"
        @keyup.enter="handleUpdate"
      />
    </el-form-item>
    <el-form-item>
      <el-button type="primary" :loading="loading" @click="handleUpdate">确认</el-button>
    </el-form-item>
  </el-form>
  <h2 class="mfa2_title">两步验证（MFA2）</h2>
  <div v-if="isEnableMFA2">
    <span class="enable_text">已启用</span>
    <el-button class="disable_btn" type="danger" @click="handleDisableMFA2">禁用</el-button>
  </div>
  <template v-else>
    <el-button v-if="startEnableMFA2" type="primary" @click="handleMFA2">启用</el-button>
    <template v-else>
      <div class="mfa2_container">
        <!-- https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2 -->
        <p>1. 使用MFA2应用(<a href="https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2" target="_blank" class="link">Google Authenticator</a>)扫描下面二维码，或者输入秘钥 <span class="secret">{{ MFA2Data.secret }}</span></p>
        <img :src="MFA2Data.qrImage" :alt="MFA2Data.secret">
        <p>2. 输入MFA2应用上的6位数字</p>
        <el-input
          v-model="mfa2Token"
          class="mfa2_input"
          clearable
          placeholder=""
          autofocus
          @keyup.enter="handleEnableMFA2"
        />
        <el-button type="primary" @click="handleEnableMFA2">保存</el-button>
      </div>
    </template>
  </template>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance } from 'vue'
import { RSAEncrypt } from '@utils/index.js'

const { proxy: { $api, $message, $messageBox, $store, $router } } = getCurrentInstance()

const loading = ref(false)
const formRef = ref(null)
const formData = reactive({
  oldLoginName: '',
  oldPwd: '',
  newLoginName: '',
  newPwd: ''
})
const rules = reactive({
  oldLoginName: { required: true, message: '输入原用户名', trigger: 'change' },
  oldPwd: { required: true, message: '输入原密码', trigger: 'change' },
  newLoginName: { required: true, message: '输入新用户名', trigger: 'change' },
  newPwd: { required: true, message: '输入新密码', trigger: 'change' }
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
        '修改用户名后会清除所有登录态，需重新登录',
        '修改提示',
        {
          confirmButtonText: '确定',
          cancelButtonText: '取消',
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
        $store.setUser(newLoginName)
        formData.oldLoginName = ''
        formData.oldPwd = ''
        formData.newLoginName = ''
        formData.newPwd = ''
        formRef.value.resetFields()
        if (oldLoginName !== newLoginName) {
          $message({ type: 'success', center: true, message: '用户名修改成功, 请重新登录' })
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
  if (!mfa2Token.value) return $message({ type: 'error', center: true, message: '请输入MFA2应用上的6位数字' })
  let { msg } = await $api.enableMFA2({ token: mfa2Token.value })
  $message({ type: 'success', center: true, message: msg })
  getMFA2Status()
}
const handleDisableMFA2 = async () => {
  $messageBox.prompt('请输入MFA2应用上的6位验证码来确认禁用', '禁用MFA2', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    inputPlaceholder: '请输入6位数字',
    inputType: 'text',
    inputPattern: /^\d{6}$/,
    inputErrorMessage: '请输入6位数字',
    beforeClose: (action, instance, done) => {
      if (action === 'confirm') {
        instance.confirmButtonLoading = true
        instance.confirmButtonText = '验证中...'
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
            instance.confirmButtonText = '确定'
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