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
          label-suffix="："
          label-width="90px"
          :show-message="false"
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
          <el-form-item prop="jwtExpires" label="有效期">
            <el-radio-group v-model="isSession" class="login-indate">
              <el-radio :value="true">一次性会话</el-radio>
              <el-radio :value="false">自定义(小时)</el-radio>
              <el-input-number
                v-model="loginForm.jwtExpires"
                :disabled="isSession"
                placeholder="单位：小时"
                class="input"
                :min="1"
                :max="72"
                value-on-clear="min"
                size="small"
                controls-position="right"
              />
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
// import { useRouter } from 'vue-router'
// import useStore from '@store/index'

// const router = useRouter()
const { proxy: { $store, $api, $message, $messageBox, $router } } = getCurrentInstance()

const loginFormRefs = ref(null)
const isSession = ref(true)
const notKey = ref(false)
const loading = ref(false)
const loginForm = reactive({
  loginName: '',
  pwd: '',
  jwtExpires: 8
})
const rules = reactive({
  loginName: { required: true, message: '需输入用户名', trigger: 'change' },
  pwd: { required: true, message: '需输入密码', trigger: 'change' }
})

const handleLogin = () => {
  loginFormRefs.value.validate().then(() => {
    let { jwtExpires, loginName, pwd } = loginForm
    jwtExpires = isSession.value ? '12h' : `${ jwtExpires }h`
    if (!isSession.value) {
      localStorage.setItem('jwtExpires', jwtExpires)
    }
    const ciphertext = RSAEncrypt(pwd)
    if (ciphertext === -1) return $message.error({ message: '公钥加载失败', center: true })
    loading.value = true
    $api.login({ loginName, ciphertext, jwtExpires })
      .then(({ data, msg }) => {
        const { token } = data
        $store.setJwtToken(token, isSession.value)
        $store.setUser(loginName)
        $message.success({ message: msg || 'success', center: true })
        if (loginName === 'admin' && pwd === 'admin') {
          $messageBox.confirm('请立即修改初始用户名及密码！防止恶意扫描！', '警告', {
            confirmButtonText: '确定',
            showCancelButton: false,
            type: 'warning'
          })
            .then(async () => {
              $router.push('/setting')
            })
        } else{
          $router.push('/')
        }
      })
      .finally(() => {
        loading.value = false
      })
  })
}

onMounted(async () => {
  if (localStorage.getItem('jwtExpires')) loginForm.jwtExpires = Number(localStorage.getItem('jwtExpires'))
  const { data } = await $api.getPubPem()
  if (!data) return (notKey.value = true)
  localStorage.setItem('publicKey', data)
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
    width: 500px;
    min-height: 250px;
    padding: 20px;
    border-radius: 6px;
    background-color: #ffffff;
    border: 1px solid #ebedef;

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
  flex-wrap: nowrap;

  .input {
    margin-left: -25px;
    // width: auto;
  }
}
</style>
