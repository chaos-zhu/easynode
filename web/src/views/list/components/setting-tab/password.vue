<template>
  <el-form
    ref="form"
    class="password-form"
    :model="formData"
    :rules="rules"
    :hide-required-asterisk="true"
    label-suffix="："
    label-width="90px"
  >
    <el-form-item label="旧密码" prop="oldPwd">
      <el-input
        v-model.trim="formData.oldPwd"
        clearable
        placeholder="旧密码"
        autocomplete="off"
      />
    </el-form-item>
    <el-form-item label="新密码" prop="newPwd">
      <el-input
        v-model.trim="formData.newPwd"
        clearable
        placeholder="新密码"
        autocomplete="off"
        @keyup.enter="handleUpdate"
      />
    </el-form-item>
    <el-form-item label="确认密码" prop="confirmPwd">
      <el-input
        v-model.trim="formData.confirmPwd"
        clearable
        placeholder="确认密码"
        autocomplete="off"
        @keyup.enter="handleUpdate"
      />
    </el-form-item>
    <el-form-item>
      <el-button type="primary" :loading="loading" @click="handleUpdate">确认</el-button>
    </el-form-item>
  </el-form>
</template>

<script>
import { RSAEncrypt } from '@utils/index.js'

export default {
  name: 'UpdatePassword',
  data() {
    return {
      loading: false,
      formData: {
        oldPwd: '',
        newPwd: '',
        confirmPwd: ''
      },
      rules: {
        oldPwd: { required: true, message: '输入旧密码', trigger: 'change' },
        newPwd: { required: true, message: '输入新密码', trigger: 'change' },
        confirmPwd: { required: true, message: '输入确认密码', trigger: 'change' }
      }
    }
  },
  computed: {
    formRef() {
      return this.$refs['form']
    }
  },
  methods: {
    handleUpdate() {
      this.formRef.validate()
        .then(async () => {
          let { oldPwd, newPwd, confirmPwd } = this.formData
          if(newPwd !== confirmPwd) return this.$message.error({ center: true, message: '两次密码输入不一致' })
          oldPwd = RSAEncrypt(oldPwd)
          newPwd = RSAEncrypt(newPwd)
          let { msg } = await this.$api.updatePwd({ oldPwd, newPwd })
          this.$message({ type: 'success', center: true, message: msg })
          this.formData = { oldPwd: '', newPwd: '', confirmPwd: '' }
          this.formRef.resetFields()
        })
    }
  }
}
</script>

<style lang="scss" scoped>
.password-form {
  width: 500px;
}
</style>
