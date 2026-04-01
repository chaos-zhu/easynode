<template>
  <div class="login_container">
    <div class="login_box">
      <div>
        <h2>EasyNode-{{ version }}</h2>
      </div>
      <div v-if="notKey">
        <el-alert :title="t('login.publicKeyFetchFailed')" type="error" show-icon />
      </div>
      <div v-else>
        <el-form
          ref="loginFormRefs"
          :model="loginForm"
          :rules="rules"
          :hide-required-asterisk="true"
          :show-message="false"
          label-suffix="："
          label-width="90px"
          label-position="top"
        >
          <el-form-item prop="loginName" :label="t('login.username')">
            <el-input
              v-model.trim="loginForm.loginName"
              type="text"
              placeholder=""
              autocomplete="off"
              :trigger-on-focus="false"
              clearable
              autofocus
            />
          </el-form-item>
          <el-form-item prop="pwd" :label="t('login.password')">
            <el-input
              v-model.trim="loginForm.pwd"
              type="password"
              placeholder=""
              autocomplete="off"
              :trigger-on-focus="false"
              clearable
              show-password
              @keyup.enter="handleLogin"
            />
          </el-form-item>
          <el-form-item v-show="false" prop="pwd" :label="t('login.password')">
            <el-input v-model.trim="loginForm.pwd" />
          </el-form-item>
          <el-form-item prop="mfa2Token" :label="t('login.mfa2Code')">
            <el-input
              v-model="loginForm.mfa2Token"
              type="text"
              :placeholder="t('login.mfa2Placeholder')"
              autocomplete="off"
              :trigger-on-focus="false"
              clearable
              autofocus
              @keyup.enter="handleLogin"
            />
          </el-form-item>
          <el-form-item prop="jwtExpires" :label="t('login.loginValidPeriod')">
            <el-radio-group v-model="expireTime" class="login-indate">
              <el-radio :value="expireEnum.ONE_SESSION">{{ t('login.temporary') }}</el-radio>
              <el-radio :value="expireEnum.CURRENT_DAY">{{ t('login.today') }}</el-radio>
              <el-radio :value="expireEnum.THREE_DAY">{{ t('login.threeDays') }}</el-radio>
              <el-radio :value="expireEnum.SEVEN_DAY">{{ t('login.sevenDays') }}</el-radio>
            </el-radio-group>
          </el-form-item>
        </el-form>
      </div>
      <div class="footer_btns">
        <el-button
          type="primary"
          class="login_btn"
          :loading="loading"
          @click="handleLogin"
        >
          {{ t('login.login') }}
        </el-button>
      </div>
    </div>
    <Warn />
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'
import { RSAEncrypt, jwtExpireToTimestamp } from '@utils/index.js'
import Warn from './warn.vue'
import { version } from '../../../package.json'

const { proxy: { $store, $api, $message, $router, $messageBox } } = getCurrentInstance()
const { t } = useI18n()

const expireEnum = reactive({
  ONE_SESSION: 'one_session',
  CURRENT_DAY: 'current_day',
  THREE_DAY: 'three_day',
  SEVEN_DAY: 'seven_day'
})
const expireTime = ref(expireEnum.CURRENT_DAY)
const loginFormRefs = ref(null)
const notKey = ref(false)
const loading = ref(false)
const isHttps = location.protocol.includes('https')
const notHttpsTips = localStorage.getItem('notHttpsTips') === 'true'
const loginForm = reactive({
  loginName: '',
  pwd: '',
  jwtExpires: 1,
  mfa2Token: ''
})
const rules = reactive({
  loginName: { required: true, message: t('login.validation.usernameRequired'), trigger: 'change' },
  pwd: { required: true, message: t('login.validation.passwordRequired'), trigger: 'change' },
  mfa2Token: { required: false, message: t('login.validation.mfa2Required'), trigger: 'change' }
})

const handleLogin = () => {
  loginFormRefs.value.validate().then(async () => {
    let { jwtExpires, loginName, pwd, mfa2Token } = loginForm
    switch (expireTime.value) {
      case expireEnum.ONE_SESSION:
        jwtExpires = '1h' // 会话登录token1小时有效期，浏览器窗口关闭则立即失效
        break
      case expireEnum.CURRENT_DAY:
        jwtExpires = `${ Math.floor((new Date().setHours(24,0,0,0) - Date.now()) / 1000) }s`
        break
      case expireEnum.THREE_DAY:
        jwtExpires = '3d'
        break
      case expireEnum.SEVEN_DAY:
        jwtExpires = '7d'
        break
    }
    const jwtExpireAt = jwtExpireToTimestamp(jwtExpires)
    const ciphertext = RSAEncrypt(pwd)
    if (ciphertext === -1) return $message.error({ message: t('login.publicKeyLoadFailed'), center: true })
    loading.value = true
    try {
      let { data, msg } = await $api.login({ loginName, ciphertext, jwtExpires, jwtExpireAt, mfa2Token })
      const { token, deviceId } = data
      $store.setJwtToken(token, expireEnum.ONE_SESSION === expireTime.value)
      $store.setUser(loginName, deviceId)
      $message.success({ message: msg || t('login.messages.success'), center: true })
      if (isHttps) return $router.push('/')
      if (notHttpsTips) return $router.push('/')
      $messageBox.confirm(
        t('login.securityRiskMessage'),
        t('login.securityTipTitle'),
        {
          confirmButtonText: t('login.understood'),
          cancelButtonText: t('login.doNotShowAgain'),
          type: 'warning',
          showCancelButton: true,
          cancelButtonClass: 'el-button--info',
          confirmButtonClass: 'el-button--warning'
        }
      )
        .catch(() => {
          localStorage.setItem('notHttpsTips', 'true')
        })
        .finally(async () => {
          $router.push('/')
        })
    } finally {
      loading.value = false
    }
  })
}

onMounted(async () => {
  const { data } = await $api.getPubPem()
  if (!data) {
    notKey.value = true
    return
  }
  localStorage.setItem('publicKey', data)
  $store.removeLoginInfo()
})
</script>

<style lang="scss" scoped>
.login_container {
  // min-height: 600px;
  height: 100vh;
  width: 100vw;
  overflow-y: auto;
  display: flex;
  justify-content: center;
  align-items: center;
  background: rgba(171, 181, 196, 0.3); // #f0f2f5;
  padding-top: 1px;

  .login_box {
    margin-top: -80px;
    width: 450px;
    min-height: 250px;
    padding: 20px;
    border-radius: 6px;
    background-color: #ffffff;

    h2 {
      text-align: center;
      margin: 25px;
      color: #409eff;
      font-size: 25px;
      background: linear-gradient(to right, #ffc021, #e4d1a1);
      background-clip: text;
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      font-weight: 600;
    }

    .footer_btns {
      display: flex;
      justify-content: center;
      align-items: center;
      .login_btn {
        width: 88px;
      }
    }
  }
}

.login-indate {
  display: flex;
  // flex-wrap: nowrap;

  .input {
    margin-left: -25px;
    // width: auto;
  }
}
</style>
