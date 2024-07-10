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
    <template #title>
      <h2 v-if="notKey" style="color: #f56c6c;"> Error </h2>
      <h2 v-else style="color: #409eff;"> LOGIN </h2>
    </template>
    <div v-if="notKey">
      <el-alert
        title="Error: 用于加密的公钥获取失败，请尝试重新启动或部署服务"
        type="error"
        show-icon
      />
    </div>
    <div v-else>
      <el-form
        ref="login-form"
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
        <el-form-item
          v-show="false"
          prop="pwd"
          label="密码"
        >
          <el-input v-model.trim="loginForm.pwd" />
        </el-form-item>
        <el-form-item
          prop="jwtExpires"
          label="有效期"
        >
          <el-radio-group v-model="isSession" class="login-indate">
            <el-radio :label="true">一次性会话</el-radio>
            <el-radio :label="false">自定义(小时)</el-radio>
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
        <el-button
          type="primary"
          :loading="loading"
          @click="handleLogin"
        >登录</el-button>
      </span>
    </template>
  </el-dialog>
</template>

<script>
import { RSAEncrypt } from '@utils/index.js'

export default {
  name: 'App',
  data() {
    return {
      isSession: true,
      visible: true,
      notKey: false,
      loading: false,
      loginForm: {
        pwd: '',
        jwtExpires: 8
      },
      rules: {
        pwd: { required: true, message: '需输入密码', trigger: 'change' }
      }
    }
  },
  async created() {
    if(localStorage.getItem('jwtExpires')) this.loginForm.jwtExpires = Number(localStorage.getItem('jwtExpires'))
    // console.log(localStorage.getItem('jwtExpires'))
    // 获取公钥
    let { data } = await this.$api.getPubPem()
    if (!data) return (this.notKey = true)
    localStorage.setItem('publicKey', data)
  },
  methods: {
    handleLogin() {
      this.$refs['login-form'].validate().then(() => {
        let { isSession, loginForm: { pwd, jwtExpires } } = this
        if(isSession) jwtExpires = '12h' // 一次性token有效期12h，存储sessionStroage
        else {
          localStorage.setItem('jwtExpires', jwtExpires)
          jwtExpires = `${ jwtExpires }h`
        }
        const ciphertext = RSAEncrypt(pwd)
        if(ciphertext === -1) return this.$message.error({ message: '公钥加载失败', center: true })
        this.loading = true
        // console.log('加密后：', ciphertext)
        this.$api.login({ ciphertext, jwtExpires })
          .then(({ data, msg }) => {
            let { token } = data
            this.$store.setJwtToken(token, isSession)
            this.$message.success({ message: msg || 'success', center: true })
            this.$router.push('/')
          })
          .finally(() => {
            this.loading = false
          })
      })
    }
  }
}
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
