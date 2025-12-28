<template>
  <el-form
    ref="formRef"
    :model="noticeConfig"
    :rules="rules"
    :inline="false"
    :hide-required-asterisk="true"
    :show-message="false"
    label-width="120px"
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
    <!-- Webhook -->
    <template v-if="noticeConfig.type === 'webhook'">
      <el-form-item label="URL" prop="webhook.url" class="form_item">
        <el-input
          v-model.trim="noticeConfig.webhook.url"
          clearable
          placeholder="https://example.com/webhook"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
      <el-form-item label="请求方法" class="form_item">
        <el-select v-model="noticeConfig.webhook.method" placeholder="" class="input">
          <el-option label="POST" value="POST" />
          <el-option label="GET" value="GET" />
          <el-option label="PUT" value="PUT" />
        </el-select>
      </el-form-item>
      <el-form-item label="Content-Type" class="form_item">
        <el-select v-model="noticeConfig.webhook.contentType" placeholder="" class="input">
          <el-option label="application/json" value="application/json" />
          <el-option label="application/x-www-form-urlencoded" value="application/x-www-form-urlencoded" />
          <el-option label="multipart/form-data" value="multipart/form-data" />
          <el-option label="text/plain" value="text/plain" />
        </el-select>
      </el-form-item>
      <el-form-item label="Header" class="form_item">
        <el-input
          v-model="noticeConfig.webhook.headers"
          type="textarea"
          :rows="2"
          placeholder="JSON 格式，可选。例如：{&quot;Authorization&quot;: &quot;Bearer xxx&quot;}"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
      <el-form-item label="自定义模板" class="form_item">
        <div class="template-wrapper">
          <el-input
            v-model="noticeConfig.webhook.template"
            type="textarea"
            :rows="6"
            placeholder="{
  &quot;msgtype&quot;: &quot;text&quot;,
  &quot;text&quot;: {
    &quot;content&quot;: &quot;{{title}}\n{{content}}&quot;
  }
}"
            autocomplete="off"
            class="input"
          />
          <el-button size="small" class="format-btn" @click="formatTemplate">格式化</el-button>
        </div>
        <span class="tips">支持变量: <code v-pre>{{title}}</code>, <code v-pre>{{content}}</code>, <code v-pre>{{timestamp}}</code>, <code v-pre>{{datetime}}</code>。留空则使用默认格式</span>
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
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> 请确保通知方式能够正常收到测试通知 </span>
    </template>
  </el-alert>
  <el-table v-loading="notifyListLoading" :data="notifyList">
    <el-table-column prop="desc" label="通知类型" />
    <el-table-column prop="sw" label="开关">
      <template #default="{row}">
        <el-switch
          v-model="row.sw"
          :active-value="true"
          :inactive-value="false"
          :loading="row.loading"
          @change="handleChangeSw(row, $event)"
        />
      </template>
    </el-table-column>
  </el-table>
</template>

<script setup>
import { ref, onMounted, computed, reactive } from 'vue'
import { getCurrentInstance } from 'vue'

const { proxy: { $api, $store, $notification, $message } } = getCurrentInstance()

const notifyListLoading = ref(false)
const notifyList = ref([])
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
  {
    type: 'webhook',
    desc: 'Webhook'
  },
])
const formRef = ref(null)
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
  ],
  'webhook.url': [
    { required: true, message: '需输入Webhook URL', trigger: 'change' },
    { type: 'url', message: '请输入有效的URL', trigger: 'change' },
  ]
})

const isPlusActive = computed(() => $store.isPlusActive)

const handleSave = () => {
  formRef.value.validate(async (valid) => {
    if (!valid) return

    // Webhook 类型时校验 JSON 格式
    if (noticeConfig.value.type === 'webhook') {
      const { template, headers } = noticeConfig.value.webhook || {}

      // 校验自定义模板
      if (template) {
        try {
          JSON.parse(template)
        } catch (e) {
          $message.error('自定义模板不是有效的 JSON 格式，请检查后重试')
          return
        }
      }

      // 校验自定义请求头
      if (headers) {
        try {
          JSON.parse(headers)
        } catch (e) {
          $message.error('自定义请求头不是有效的 JSON 格式，请检查后重试')
          return
        }
      }
    }

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

const getNotifyList = (flag = true) => {
  if (flag) notifyListLoading.value = true
  $api.getNotifyList()
    .then(({ data }) => {
      notifyList.value = data.map((item) => {
        item.loading = false
        return item
      })
    })
    .finally(() => notifyListLoading.value = false)
}

const handleChangeSw = async (row) => {
  row.loading = true
  const { type, sw } = row
  try {
    await $api.updateNotifyList({ type, sw })
    // if (this.userEmailList.length === 0) $message.warning('未配置邮箱, 此开关将不会生效')
  } finally {
    row.loading = false
  }
  getNotifyList(false)
}

const formatTemplate = () => {
  if (!noticeConfig.value.webhook?.template) return
  try {
    const parsed = JSON.parse(noticeConfig.value.webhook.template)
    noticeConfig.value.webhook.template = JSON.stringify(parsed, null, 2)
    $message.success('格式化成功')
  } catch (e) {
    $message.warning('格式化失败：模板不是有效的 JSON 格式')
  }
}

onMounted(() => {
  getNotifyList()
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
  .template-wrapper {
    display: flex;
    flex-direction: column;
    gap: 8px;
    .format-btn {
      align-self: flex-start;
    }
  }
}
</style>
