<template>
  <el-dialog
    v-model="visible"
    width="500px"
    :top="'30vh'"
    destroy-on-close
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :show-close="false"
    center
  >
    <template #header>
      <h2 v-if="notKey" style="color: #f56c6c;"> Error </h2>
      <h2 v-else style="color: #409eff;"> LOGIN </h2>
    </template>
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
      >
        <el-form-item prop="pwd" label="密码">
          <el-input
            v-model.trim="loginForm.pwd"
            type="password"
            placeholder="Please input password"
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
    <template #footer>
      <span class="dialog-footer">
        <el-button type="primary" :loading="loading" @click="handleLogin">登录</el-button>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance } from 'vue'
import { RSAEncrypt } from '@utils/index.js'
// import { useRouter } from 'vue-router'
// import useStore from '@store/index'

// const router = useRouter()
const { proxy: { $store, $api, $message, $router } } = getCurrentInstance()

const loginFormRefs = ref(null)
const isSession = ref(true)
const visible = ref(true)
const notKey = ref(false)
const loading = ref(false)
const loginForm = reactive({
  pwd: '',
  jwtExpires: 8
})
const rules = reactive({
  pwd: { required: true, message: '需输入密码', trigger: 'change' }
})

const handleLogin = () => {
  loginFormRefs.value.validate().then(() => {
    let jwtExpires = isSession.value ? '12h' : `${ loginForm.jwtExpires }h`
    if (!isSession.value) {
      localStorage.setItem('jwtExpires', loginForm.jwtExpires)
    }
    const ciphertext = RSAEncrypt(loginForm.pwd)
    if (ciphertext === -1) return $message.error({ message: '公钥加载失败', center: true })
    loading.value = true
    $api.login({ ciphertext, jwtExpires })
      .then(({ data, msg }) => {
        const { token } = data
        $store.setJwtToken(token, isSession.value)
        $message.success({ message: msg || 'success', center: true })
        $router.push('/')
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
.login-indate {
  display: flex;
  flex-wrap: nowrap;

  .input {
    margin-left: -25px;
    // width: auto;
  }
}
</style>
