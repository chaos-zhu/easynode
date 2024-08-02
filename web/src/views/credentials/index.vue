<template>
  <div class="credentials_container">
    <div class="header">
      <el-button type="primary" @click="addCredentials">添加凭证</el-button>
    </div>
    <el-table v-loading="loading" :data="sshList">
      <el-table-column prop="name" label="名称" />
      <el-table-column prop="authType" label="类型">
        <template #default="{ row }">
          {{ row.authType === 'privateKey' ? '密钥' : '密码' }}
        </template>
      </el-table-column>
      <el-table-column label="操作">
        <template #default="{ row }">
          <el-button type="primary" @click="handleChange(row)">修改</el-button>
          <el-button v-show="row.id !== 'default'" type="danger" @click="removeSSH(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog
      v-model="sshFormVisible"
      width="600px"
      top="150px"
      :title="isModify ? '修改凭证' : '添加凭证'"
      :close-on-click-modal="false"
      @close="clearFormInfo"
    >
      <el-form
        ref="updateFormRef"
        :model="sshForm"
        :rules="rules"
        :hide-required-asterisk="true"
        label-suffix="："
        label-width="100px"
        :show-message="false"
      >
        <el-form-item label="凭证名称" prop="name">
          <el-input
            v-model="sshForm.name"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item label="认证方式" prop="type">
          <el-radio v-model="sshForm.authType" value="privateKey">密钥</el-radio>
          <el-radio v-model="sshForm.authType" value="password">密码</el-radio>
        </el-form-item>
        <el-form-item v-if="sshForm.authType === 'privateKey'" prop="privateKey" label="密钥">
          <el-button type="primary" size="small" @click="handleClickUploadBtn">
            本地私钥...
          </el-button>
          <input
            ref="privateKeyRef"
            type="file"
            name="privateKey"
            style="display: none;"
            @change="handleSelectPrivateKeyFile"
          >
          <el-input
            v-model="sshForm.privateKey"
            type="textarea"
            :rows="5"
            clearable
            autocomplete="off"
            style="margin-top: 5px;"
            placeholder="-----BEGIN RSA PRIVATE KEY-----"
          />
        </el-form-item>
        <el-form-item v-if="sshForm.authType === 'password'" prop="password" label="密码">
          <el-input
            v-model.trim="sshForm.password"
            type="text"
            placeholder=""
            autocomplete="off"
            clearable
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <span>
          <el-button @click="sshFormVisible = false">关闭</el-button>
          <el-button type="primary" @click="updateForm">{{ isModify ? '修改' : '添加' }}</el-button>
        </span>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, computed, nextTick, getCurrentInstance } from 'vue'
import { randomStr, AESEncrypt, RSAEncrypt } from '@utils/index.js'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()

const loading = ref(false)
const sshFormVisible = ref(false)
let isModify = ref(false)
const sshForm = reactive({
  name: '',
  authType: 'privateKey',
  privateKey: '',
  password: ''
})

const rules = computed(() => {
  return {
    name: { required: true, message: '需输入凭证名称', trigger: 'change' },
    password: [{ required: !isModify.value && sshForm.authType === 'password', trigger: 'change' },],
    privateKey: [{ required: !isModify.value && sshForm.authType === 'privateKey', trigger: 'change' },]
  }
})

const updateFormRef = ref(null)
const privateKeyRef = ref(null)

let sshList = computed(() => $store.sshList)

let addCredentials = () => {
  sshForm.id = null
  sshFormVisible.value = true
  isModify.value = false
}
const handleChange = (row) => {
  Object.assign(sshForm, { ...row })
  sshFormVisible.value = true
  isModify.value = true
}

const updateForm = () => {
  updateFormRef.value.validate()
    .then(async () => {
      let formData = { ...sshForm }
      let tempKey = randomStr(16)
      // 加密传输
      if (formData.password) formData.password = AESEncrypt(formData.password, tempKey)
      if (formData.privateKey) formData.privateKey = AESEncrypt(formData.privateKey, tempKey)
      formData.tempKey = RSAEncrypt(tempKey)
      // 加密传输
      if (isModify.value) {
        await $api.updateSSH(formData)
      } else {
        await $api.addSSH(formData)
      }
      sshFormVisible.value = false
      await $store.getSSHList()
      $message.success('success')
    })
}

const clearFormInfo = () => {
  nextTick(() => updateFormRef.value.resetFields())
}

const removeSSH = ({ id, name }) => {
  $messageBox.confirm(`确认删除该凭证：${ name }`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  })
    .then(async () => {
      await $api.removeSSH(id) // 后台会同步删除关联此凭证的credential字段
      await $store.getSSHList()
      await $store.getHostList() // 刷新主机字段 isConfig
      $message.success('success')
    })
}

const handleClickUploadBtn = () => {
  privateKeyRef.value.click()
}

const handleSelectPrivateKeyFile = (event) => {
  let file = event.target.files[0]
  let reader = new FileReader()
  reader.onload = (e) => {
    sshForm.privateKey = e.target.result
    privateKeyRef.value.value = ''
  }
  reader.readAsText(file)
}

</script>

<style lang="scss" scoped>
.credentials_container {
  padding: 20px;
  .header {
    padding: 15px;
    display: flex;
    align-items: center;
    justify-content: end;
  }
}

.host_count {
  display: block;
  width: 100px;
  text-align: center;
  font-size: 15px;
  color: #87cf63;
  cursor: pointer;
}
</style>