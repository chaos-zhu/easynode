<template>
  <div v-loading="loading">
    <el-form
      ref="emailFormRef"
      :model="emailForm"
      :rules="rules"
      :inline="true"
      :hide-required-asterisk="true"
      label-suffix="："
    >
      <el-form-item label="" prop="target" style="width: 200px;">
        <el-select
          v-model="emailForm.target"
          placeholder="邮件服务商"
        >
          <el-option
            v-for="item in supportEmailList"
            :key="item.target"
            :label="item.name"
            :value="item.target"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="" prop="auth.user" style="width: 200px;">
        <el-input
          v-model.trim="emailForm.auth.user"
          clearable
          placeholder="邮箱"
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item label="" prop="auth.pass" style="width: 200px;">
        <el-input
          v-model.trim="emailForm.auth.pass"
          clearable
          placeholder="SMTP授权码"
          autocomplete="off"
          @keyup.enter="addEmail"
        />
      </el-form-item>
      <el-form-item label="">
        <el-tooltip
          effect="dark"
          content="重复添加的邮箱将会被覆盖"
          placement="right"
        >
          <el-button type="primary" @click="addEmail">
            添加
          </el-button>
        </el-tooltip>
      </el-form-item>
    </el-form>
    <!-- 提示 -->
    <el-alert type="success" :closable="false">
      <template #title>
        <span style="letter-spacing: 2px;"> Tips: 系统所有通知邮件将会下发到所有已经配置成功的邮箱中 </span>
      </template>
    </el-alert>
    <!-- 表格 -->
    <el-table :data="userEmailList" class="table">
      <el-table-column prop="email" label="Email" />
      <el-table-column prop="name" label="服务商" />
      <el-table-column label="操作">
        <template #default="{ row }">
          <el-button
            type="primary"
            :loading="row.loading"
            @click="pushTestEmail(row)"
          >
            测试
          </el-button>
          <el-button
            type="danger"
            @click="deleteUserEmail(row)"
          >
            删除
          </el-button>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance } from 'vue'

const { proxy: { $api, $message, $messageBox, $notification } } = getCurrentInstance()

const loading = ref(false)
const userEmailList = ref([])
const supportEmailList = ref([])
const emailFormRef = ref(null)

const emailForm = reactive({
  target: 'qq',
  auth: {
    user: '',
    pass: ''
  }
})

const rules = reactive({
  'auth.user': { required: true, type: 'email', message: '需输入邮箱', trigger: 'change' },
  'auth.pass': { required: true, message: '需输入SMTP授权码', trigger: 'change' }
})

const getUserEmailList = () => {
  loading.value = true
  $api.getUserEmailList()
    .then(({ data }) => {
      userEmailList.value = data.map(item => {
        item.loading = false
        return item
      })
    })
    .finally(() => loading.value = false)
}

const getSupportEmailList = () => {
  $api.getSupportEmailList()
    .then(({ data }) => {
      supportEmailList.value = data
    })
}

const addEmail = () => {
  emailFormRef.value.validate()
    .then(() => {
      $api.updateUserEmailList({ ...emailForm })
        .then(() => {
          $message.success('添加成功, 点击[测试]按钮发送测试邮件')
          let { target } = emailForm
          emailForm.target = target
          emailForm.auth.user = ''
          emailForm.auth.pass = ''
          getUserEmailList()
        })
    })
}

const pushTestEmail = (row) => {
  row.loading = true
  const { email: toEmail } = row
  $api.pushTestEmail({ isTest: true, toEmail })
    .then(() => {
      $message.success(`发送成功, 请检查邮箱: ${ toEmail }`)
    })
    .catch((error) => {
      $notification({
        title: '发送测试邮件失败, 请检查邮箱SMTP配置',
        message: error.response?.data.msg,
        type: 'error'
      })
    })
    .finally(() => {
      row.loading = false
    })
}

const deleteUserEmail = ({ email }) => {
  $messageBox.confirm(
    `确认删除邮箱：${ email }`,
    'Warning',
    {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning'
    }
  )
    .then(async () => {
      await $api.deleteUserEmail(email)
      $message.success('success')
      getUserEmailList()
    })
}

onMounted(() => {
  getUserEmailList()
  getSupportEmailList()
})
</script>

<style lang="scss" scoped>

</style>
