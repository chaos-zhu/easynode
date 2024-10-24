<template>
  <div class="login_container">
    <div class="login_box">
      <div>
        <h2>EasyNode</h2>
      </div>
      <div v-if="notKey">
        <el-alert title="Error: 用于加密的公钥获取失败，请尝试重新启动或部署服务" type="error" show-icon />
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
          <el-form-item prop="loginName" label="用户名">
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
          <el-form-item prop="pwd" label="密码">
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
          <el-form-item v-show="false" prop="pwd" label="密码">
            <el-input v-model.trim="loginForm.pwd" />
          </el-form-item>
          <el-form-item prop="mfa2Token" label="MFA2验证码">
            <el-input
              v-model.trim.number="loginForm.mfa2Token"
              type="text"
              placeholder="MFA2应用上的6位数字(未设置可忽略)"
              autocomplete="off"
              :trigger-on-focus="false"
              clearable
              autofocus
              @keyup.enter="handleLogin"
            />
          </el-form-item>
          <el-form-item prop="jwtExpires" label="有效期">
            <el-radio-group v-model="expireTime" class="login-indate">
              <el-radio :value="expireEnum.ONE_SESSION">一次性会话</el-radio>
              <el-radio :value="expireEnum.CURRENT_DAY">当天有效</el-radio>
              <el-radio :value="expireEnum.THREE_DAY">三天有效</el-radio>
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
          登录
        </el-button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance } from 'vue'
import { RSAEncrypt } from '@utils/index.js'

const { proxy: { $store, $api, $message, $messageBox, $router } } = getCurrentInstance()

const expireEnum = reactive({
  ONE_SESSION: 'one_session',
  CURRENT_DAY: 'current_day',
  THREE_DAY: 'three_day'
})
const expireTime = ref(expireEnum.CURRENT_DAY)
const loginFormRefs = ref(null)
const notKey = ref(false)
const loading = ref(false)
const loginForm = reactive({
  loginName: '',
  pwd: '',
  jwtExpires: 1,
  mfa2Token: ''
})
const rules = reactive({
  loginName: { required: true, message: '需输入用户名', trigger: 'change' },
  pwd: { required: true, message: '需输入密码', trigger: 'change' },
  mfa2Token: { required: false, message: '需输入密码', trigger: 'change' }
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
    }
    const ciphertext = RSAEncrypt(pwd)
    if (ciphertext === -1) return $message.error({ message: '公钥加载失败', center: true })
    loading.value = true
    try {
      let { data, msg } = await $api.login({ loginName, ciphertext, jwtExpires, mfa2Token })
      const { token } = data
      $store.setJwtToken(token, expireEnum.ONE_SESSION === expireTime.value)
      $store.setUser(loginName)
      $message.success({ message: msg || 'success', center: true })
      loginSuccess()
    } finally {
      loading.value = false
    }
  })
}

const loginSuccess = () => {
  let { loginName, pwd } = loginForm
  if (loginName === 'admin' && pwd === 'admin') {
    $messageBox.confirm('请立即修改初始用户名及密码！防止恶意扫描！', 'Warning', {
      confirmButtonText: '确定',
      showCancelButton: false,
      type: 'warning'
    })
      .then(async () => {
        $router.push('/setting')
      })
  } else {
    $router.push('/')
  }
}

onMounted(async () => {
  if (localStorage.getItem('jwtExpires')) loginForm.jwtExpires = Number(localStorage.getItem('jwtExpires'))
  const { data } = await $api.getPubPem()
  if (!data) return (notKey.value = true)
  localStorage.setItem('publicKey', data)
  $store.removeJwtToken()
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
