<template>
  <el-form
    ref="formRef"
    class="password-form"
    :model="formData"
    :rules="rules"
    :hide-required-asterisk="true"
    label-suffix="："
    label-width="90px"
    :show-message="false"
  >
    <el-form-item label="原用户名" prop="oldLoginName">
      <el-input
        v-model.trim="formData.oldLoginName"
        clearable
        placeholder=""
        autocomplete="off"
      />
    </el-form-item>
    <el-form-item label="原密码" prop="oldPwd">
      <el-input
        v-model.trim="formData.oldPwd"
        type="password"
        clearable
        show-password
        placeholder=""
        autocomplete="off"
      />
    </el-form-item>
    <el-form-item label="新用户名" prop="oldPwd">
      <el-input
        v-model.trim="formData.newLoginName"
        clearable
        placeholder=""
        autocomplete="off"
      />
    </el-form-item>
    <el-form-item label="新密码" prop="newPwd">
      <el-input
        v-model.trim="formData.newPwd"
        type="password"
        show-password
        clearable
        placeholder=""
        autocomplete="off"
        @keyup.enter="handleUpdate"
      />
    </el-form-item>
    <el-form-item>
      <el-button type="primary" :loading="loading" @click="handleUpdate">确认</el-button>
    </el-form-item>
  </el-form>
</template>

<script setup>
import { ref, reactive, getCurrentInstance } from 'vue'
import { RSAEncrypt } from '@utils/index.js'

const { proxy: { $api, $message, $store } } = getCurrentInstance()

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

const handleUpdate = () => {
  formRef.value.validate()
    .then(async () => {
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
    })
}
</script>

<style lang="scss" scoped>
.password-form {
  width: 500px;
}
</style>