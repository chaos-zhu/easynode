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
      <el-select v-model="noticeConfig.type" placeholder="" class="input">
        <el-option
          v-for="item in noticeTypeList"
          :key="item.type"
          :label="item.desc"
          :value="item.type"
        />
      </el-select>
    </el-form-item>
    <!-- server酱 -->
    <template v-if="noticeConfig.type === 'sct'">
      <el-form-item label="SendKey" prop="sct.sendKey" class="form_item">
        <el-input
          v-model.trim="noticeConfig.sct.sendKey"
          clearable
          placeholder="SCT******"
          autocomplete="off"
          class="input"
        />
        <p class="tips">普通用户每日最多支持5条，有条件建议开通会员服务防止丢失重要通知。<a class="link" href="https://sct.ftqq.com/r/9338" target="_blank">Server酱官网</a> </p>
      </el-form-item>
    </template>
    <!-- 邮箱 -->
    <template v-if="noticeConfig.type === 'email'">
      <el-form-item label="服务商" prop="email.service" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.service"
          clearable
          placeholder=""
          autocomplete="off"
          class="input"
        />
        <span class="tips">邮箱服务商, 例如: QQ、126、163、Gmial, 支持列表: <a class="link" href="https://github.com/nodemailer/nodemailer/blob/master/lib/well-known/services.json" target="_blank">点击查询</a> </span>
      </el-form-item>
      <el-form-item label="邮箱地址" prop="email.user" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.user"
          clearable
          placeholder="邮箱地址"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
      <el-form-item label="SMTP" prop="auth.pass" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.pass"
          clearable
          placeholder="SMTP授权码/密码"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
    </template>
    <!-- Telegram -->
    <template v-if="noticeConfig.type === 'tg'">
      <el-form-item label="Token" prop="tg.token" class="form_item">
        <el-input
          v-model.trim="noticeConfig.tg.token"
          clearable
          placeholder="Telegram Token"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
      <el-form-item label="ChatId" prop="tg.chatId" class="form_item">
        <el-input
          v-model="noticeConfig.tg.chatId"
          clearable
          placeholder="Telegram ChatId"
          autocomplete="off"
          class="input"
        />
        <span class="tips">Telegram Token/ChatId 获取: <a class="link" href="https://easynode.chaoszhu.com/zh/guide/get-tg-token" target="_blank">查看教程</a> </span>
      </el-form-item>
    </template>
    <el-form-item label="" class="form_item">
      <el-button
        type="primary"
        :loading="loading"
        @click="handleSave"
      >
        测试并保存
      </el-button>
    </el-form-item>
  </el-form>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance, computed } from 'vue'
// import PlusSupportTip from '@/components/common/PlusSupportTip.vue'

const { proxy: { $api, $notification, $store } } = getCurrentInstance()

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
  {
    type: 'tg',
    desc: 'Telegram'
  },
])
const formRef = ref(null)
const isPlusActive = computed(() => $store.isPlusActive)

const rules = reactive({
  'sct.sendKey': { required: true, message: '需输入sendKey', trigger: 'change' },
  'email.service': { required: true, message: '需输入邮箱提供商', trigger: 'change' },
  'email.user': { required: true, type: 'email', message: '需输入邮箱', trigger: 'change' },
  'email.pass': { required: true, message: '需输入邮箱SMTP授权码', trigger: 'change' },
  'tg.token': { required: true, message: '需输入Telegram Token', trigger: 'change' },
  'tg.chatId': [
    { required: true, message: '需输入Telegram ChatId', trigger: 'change' },
    {
      pattern: /^-?\d+$/,
      message: 'ChatId必须为数字',
      trigger: ['blur', 'change',]
    },
  ]
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
  // width: 350px;
  .input {
    width: 450px;
  }
  .tips {
    width: 100%;
    font-size: 14px;
    color: #999;
  }
}
</style>
