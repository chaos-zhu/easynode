<template>
  <!-- <el-alert type="success" :closable="false">
      <template #title>
        <span style="letter-spacing: 2px;"> 保存并测试通过后才会收到通知 </span>
      </template>
    </el-alert> -->
  <!-- <br> -->
  <el-form
    ref="formRef"
    :model="noticeConfig"
    :rules="rules"
    :inline="false"
    :hide-required-asterisk="true"
    :show-message="false"
    label-width="100px"
    label-suffix="："
  >
    <el-form-item label="通知方式" prop="type" class="form_item">
      <el-select v-model="noticeConfig.type" placeholder="">
        <el-option
          v-for="item in noticeTypeList"
          :key="item.type"
          :label="item.desc"
          :value="item.type"
        />
      </el-select>
    </el-form-item>
    <template v-if="noticeConfig.type === 'sct'">
      <el-form-item label="SendKey" prop="sct.sendKey" class="form_item">
        <el-input
          v-model.trim="noticeConfig.sct.sendKey"
          clearable
          placeholder="SCT******"
          autocomplete="off"
        />
      </el-form-item>
    </template>
    <template v-if="noticeConfig.type === 'email'">
      <el-form-item label="服务商" prop="email.service" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.service"
          clearable
          placeholder=""
          autocomplete="off"
        />
        <span class="tips">邮箱服务商, 例如: Gmial、qq、126、163, 支持列表: <a class="link" href="https://github.com/nodemailer/nodemailer/blob/master/lib/well-known/services.json" target="_blank">点击查询</a> </span>
      </el-form-item>
      <el-form-item label="邮箱地址" prop="email.user" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.user"
          clearable
          placeholder="邮箱地址"
          autocomplete="off"
        />
      </el-form-item>
      <el-form-item label="SMTP" prop="auth.pass" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.pass"
          clearable
          placeholder="SMTP授权码/密码"
          autocomplete="off"
        />
      </el-form-item>
    </template>
    <el-form-item label="" class="form_item">
      <el-button type="primary" :loading="loading" @click="handleSave">
        测试并保存
      </el-button>
      <!-- <el-tooltip effect="dark" content="重复添加的邮箱将会被覆盖" placement="right">
        </el-tooltip> -->
    </el-form-item>
  </el-form>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance } from 'vue'

const { proxy: { $api, $message, $messageBox, $notification } } = getCurrentInstance()

const loading = ref(false)
const noticeConfig = ref({})
const noticeTypeList = ref([
  {
    type: 'email',
    desc: '邮箱'
  },
  {
    type: 'sct',
    desc: 'Server酱'
  },
])
const formRef = ref(null)

const rules = reactive({
  'sct.sendKey': { required: true, message: '需输入sendKey', trigger: 'change' },
  'email.service': { required: true, message: '需输入邮箱提供商', trigger: 'change' },
  'email.user': { required: true, type: 'email', message: '需输入邮箱', trigger: 'change' },
  'email.pass': { required: true, message: '需输入邮箱SMTP授权码', trigger: 'change' }
})

const handleSave = () => {
  formRef.value.validate(async (valid) => {
    if (!valid) return
    try {
      loading.value = true
      await $api.updateNotifyConfig({ noticeConfig: { ...noticeConfig.value } })
      // $message.success('保存成功')
      $notification.success({
        title: '测试通过 | 保存成功',
        message: '请确认通知方式是否已收到通知'
      })
    } catch (error) {
      console.error(error)
    } finally {
      loading.value = false
    }
  })
}

const getNotifyConfig = async () => {
  try {
    let { data } = await $api.getNotifyConfig()
    noticeConfig.value = data || {}
  } catch (error) {
    console.error(error)
  }
}

onMounted(() => {
  getNotifyConfig()
})

</script>

<style lang="scss" scoped>
.form_item {
  width: 350px;

  .tips {
    font-size: 12px;
    color: #999;
  }
}
</style>
