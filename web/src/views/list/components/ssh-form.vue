<template>
  <el-dialog
    v-model="visible"
    title="SSH连接"
    :close-on-click-modal="false"
    @closed="$nextTick(() => formRef.resetFields())"
  >
    <el-form
      ref="form"
      :model="sshForm"
      :rules="rules"
      :hide-required-asterisk="true"
      label-suffix="："
      label-width="90px"
    >
      <el-form-item label="主机" prop="host">
        <el-input
          v-model.trim="sshForm.host"
          disabled
          clearable
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item label="端口" prop="port">
        <el-input v-model.trim="sshForm.port" clearable autocomplete="off" />
      </el-form-item>
      <el-form-item label="用户名" prop="username">
        <el-autocomplete
          v-model.trim="sshForm.username"
          :fetch-suggestions="userSearch"
          style="width: 100%;"
          clearable
        >
          <template #default="{item}">
            <div class="value">{{ item.value }}</div>
          </template>
        </el-autocomplete>
      </el-form-item>
      <el-form-item label="认证方式" prop="type">
        <el-radio v-model.trim="sshForm.type" label="privateKey">密钥</el-radio>
        <el-radio v-model.trim="sshForm.type" label="password">密码</el-radio>
      </el-form-item>
      <el-form-item v-if="sshForm.type === 'password'" prop="password" label="密码">
        <el-input
          v-model.trim="sshForm.password"
          type="password"
          placeholder="Please input password"
          autocomplete="off"
          clearable
          show-password
        />
      </el-form-item>
      <el-form-item v-if="sshForm.type === 'privateKey'" prop="privateKey" label="密钥">
        <el-button type="primary" size="small" @click="handleClickUploadBtn">
          选择私钥...
        </el-button>
        <input
          ref="privateKey"
          type="file"
          name="privateKey"
          style="display: none;"
          @change="handleSelectPrivateKeyFile"
        >
        <el-input
          v-model.trim="sshForm.privateKey"
          type="textarea"
          :rows="5"
          clearable
          autocomplete="off"
          style="margin-top: 5px;"
          placeholder="-----BEGIN RSA PRIVATE KEY-----"
        />
      </el-form-item>
      <el-form-item prop="command" label="执行指令">
        <el-input
          v-model="sshForm.command"
          type="textarea"
          :rows="5"
          clearable
          autocomplete="off"
          placeholder="连接服务器后自动执行的指令(例如: sudo -i)"
        />
      </el-form-item>
    </el-form>
    <template #footer>
      <span class="dialog-footer">
        <el-button @click="visible = false">取消</el-button>
        <el-button type="primary" @click="handleSaveSSH">保存</el-button>
        <!-- <el-button type="primary" @click="handleSaveSSH">保存并连接</el-button> -->
      </span>
    </template>
  </el-dialog>
</template>

<script>
import $api from '@/api'
import { randomStr, AESEncrypt, RSAEncrypt } from '@utils/index.js'

export default {
  name: 'SSHForm',
  props: {
    show: {
      required: true,
      type: Boolean
    },
    tempHost: {
      required: true,
      type: String
    },
    name: {
      required: true,
      type: String
    }
  },
  emits: ['update:show',],
  data() {
    return {
      sshForm: {
        host: '',
        port: 22,
        username: '',
        type: 'privateKey',
        password: '',
        privateKey: '',
        command: ''
      },
      defaultUsers: [
        { value: 'root' },
        { value: 'ubuntu' },
      ],
      rules: {
        host: { required: true, message: '需输入主机', trigger: 'change' },
        port: { required: true, message: '需输入端口', trigger: 'change' },
        username: { required: true, message: '需输入用户名', trigger: 'change' },
        type: { required: true },
        password: { required: true, message: '需输入密码', trigger: 'change' },
        privateKey: { required: true, message: '需输入密钥', trigger: 'change' },
        command: { required: false }
      }
    }
  },
  computed: {
    visible: {
      get() {
        return this.show
      },
      set(newVal) {
        this.$emit('update:show', newVal)
      }
    },
    formRef() {
      return this.$refs['form']
    }
  },
  watch: {
    tempHost: {
      handler(newVal) {
        this.sshForm.host = newVal
      }
    }
  },
  methods: {
    handleClickUploadBtn() {
      this.$refs['privateKey'].click()
    },
    handleSelectPrivateKeyFile(event) {
      let file = event.target.files[0]
      let reader = new FileReader()
      reader.onload = (e) => {
        this.sshForm.privateKey = e.target.result
        this.$refs['privateKey'].value = ''
      }
      reader.readAsText(file)
    },
    handleSaveSSH() {
      this.formRef.validate()
        .then(async () => {
          let randomKey = randomStr(16)
          let formData = JSON.parse(JSON.stringify(this.sshForm))
          // 加密传输
          if(formData.password) formData.password = AESEncrypt(formData.password, randomKey)
          if(formData.privateKey) formData.privateKey = AESEncrypt(formData.privateKey, randomKey)
          formData.randomKey = RSAEncrypt(randomKey)
          await $api.updateSSH(formData)
          this.$notification({
            title: '保存成功',
            message: '下次点击 [Web SSH] 可直接登录终端\n如无法登录请 [移除凭证] 后重新添加',
            type: 'success'
          })
          this.visible = false
          // this.$message({ type: 'success', center: true, message: data })
          // setTimeout(() => {
          //   window.open(`/terminal?host=${ this.tempHost }&name=${ this.name }`)
          // }, 1000)
        })
    },
    userSearch(keyword, cb) {
      let res = keyword
        ? this.defaultUsers.filter((item) => item.value.includes(keyword))
        : this.defaultUsers
      cb(res)
    }
  }
}
</script>

<style lang="scss" scoped>

</style>
