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
    <el-form-item :label="t('settings.notify.notifyMethod')" prop="type" class="form_item">
      <el-select v-model="noticeConfig.type" placeholder="" class="input">
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
          class="input"
        />
        <p class="tips">{{ t('settings.notify.sctTip') }}<a class="link" href="https://sct.ftqq.com/r/9338" target="_blank">{{ t('settings.notify.serverChanOfficial') }}</a></p>
      </el-form-item>
    </template>
    <template v-if="noticeConfig.type === 'email'">
      <el-form-item :label="t('settings.notify.configMode')" class="form_item">
        <el-radio-group v-model="noticeConfig.email.useCustom" @change="handleEmailModeChange">
          <el-radio-button :value="false">{{ t('settings.notify.serviceProvider') }}</el-radio-button>
          <el-radio-button :value="true">{{ t('settings.notify.customSmtp') }}</el-radio-button>
        </el-radio-group>
      </el-form-item>
      <template v-if="!noticeConfig.email.useCustom">
        <el-form-item :label="t('settings.notify.serviceProvider')" prop="email.service" class="form_item">
          <el-input
            v-model.trim="noticeConfig.email.service"
            clearable
            :placeholder="t('settings.notify.emailProviderPlaceholder')"
            autocomplete="off"
            class="input"
          />
          <span class="tips">{{ t('settings.notify.emailProviderTipPrefix') }}<a class="link" href="https://github.com/nodemailer/nodemailer/blob/master/lib/well-known/services.json" target="_blank">{{ t('settings.notify.clickToView') }}</a> </span>
        </el-form-item>
      </template>
      <template v-else>
        <el-form-item :label="t('settings.notify.smtpServer')" prop="email.host" class="form_item">
          <el-input
            v-model.trim="noticeConfig.email.host"
            clearable
            placeholder="smtp.gmail.com"
            autocomplete="off"
            class="input"
          />
          <span class="tips">{{ t('settings.notify.smtpServerTip') }}</span>
        </el-form-item>
        <el-form-item :label="t('settings.notify.port')" class="form_item">
          <el-select
            v-model="noticeConfig.email.port"
            placeholder=""
            class="input"
            @change="handlePortChange"
          >
            <el-option label="465 (SSL)" :value="465" />
            <el-option label="587 (STARTTLS)" :value="587" />
            <el-option :label="t('settings.notify.port25NoEncryption')" :value="25" />
          </el-select>
        </el-form-item>
        <el-form-item :label="t('settings.notify.secureConnection')" class="form_item">
          <el-radio-group v-model="noticeConfig.email.secure">
            <el-radio-button :value="true">SSL/TLS</el-radio-button>
            <el-radio-button :value="false">{{ t('settings.notify.starttlsOrNone') }}</el-radio-button>
          </el-radio-group>
          <span class="tips">{{ t('settings.notify.secureConnectionTip') }}</span>
        </el-form-item>
      </template>
      <el-form-item :label="t('settings.notify.emailAddress')" prop="email.user" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.user"
          clearable
          placeholder="your@email.com"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
      <el-form-item :label="t('settings.notify.smtpPassword')" prop="email.pass" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.pass"
          clearable
          type="password"
          show-password
          :placeholder="t('settings.notify.smtpPasswordPlaceholder')"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
      <el-form-item :label="t('settings.notify.recipient')" class="form_item">
        <el-input
          v-model.trim="noticeConfig.email.to"
          clearable
          :placeholder="t('settings.notify.recipientPlaceholder')"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
    </template>
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
        <span class="tips">{{ t('settings.notify.telegramTipPrefix') }}<a class="link" href="https://easynode.chaoszhu.com/zh/guide/get-tg-token" target="_blank">{{ t('settings.notify.viewTutorial') }}</a> </span>
      </el-form-item>
    </template>
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
      <el-form-item :label="t('settings.notify.requestMethod')" class="form_item">
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
          :placeholder="t('settings.notify.headersPlaceholder')"
          autocomplete="off"
          class="input"
        />
      </el-form-item>
      <el-form-item :label="t('settings.notify.customTemplate')" class="form_item">
        <div class="template-wrapper">
          <el-input
            v-model="noticeConfig.webhook.template"
            type="textarea"
            :rows="6"
            :placeholder="t('settings.notify.templatePlaceholder')"
            autocomplete="off"
            class="input"
          />
          <el-button size="small" class="format-btn" @click="formatTemplate">{{ t('settings.notify.format') }}</el-button>
        </div>
        <span class="tips">{{ t('settings.notify.templateVariablesTip') }}</span>
      </el-form-item>
    </template>
    <el-form-item label="" class="form_item">
      <el-button
        type="primary"
        :loading="loading"
        @click="handleSave"
      >
        {{ t('settings.notify.testAndSave') }}
      </el-button>
    </el-form-item>
  </el-form>
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> {{ t('settings.notify.testNoticeHint') }} </span>
    </template>
  </el-alert>
  <el-table v-loading="notifyListLoading" :data="notifyList">
    <el-table-column prop="desc" :label="t('settings.notify.notificationType')" />
    <el-table-column prop="sw" :label="t('settings.notify.switch')">
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
import { useI18n } from 'vue-i18n'

const { proxy: { $api, $store, $notification, $message } } = getCurrentInstance()
const { t } = useI18n()

const notifyListLoading = ref(false)
const notifyList = ref([])
const loading = ref(false)
const noticeConfig = ref({})
const noticeTypeList = ref([
  {
    type: 'email',
    desc: t('settings.notify.email')
  },
  {
    type: 'sct',
    desc: t('settings.notify.serverChan')
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
  'sct.sendKey': { required: true, message: t('settings.notify.validation.enterSendKey'), trigger: 'change' },
  'email.service': { required: true, message: t('settings.notify.validation.enterEmailProvider'), trigger: 'change' },
  'email.host': { required: true, message: t('settings.notify.validation.enterSmtpHost'), trigger: 'change' },
  'email.user': { required: true, type: 'email', message: t('settings.notify.validation.enterEmail'), trigger: 'change' },
  'email.pass': { required: true, message: t('settings.notify.validation.enterSmtpPassword'), trigger: 'change' },
  'tg.token': { required: true, message: t('settings.notify.validation.enterTelegramToken'), trigger: 'change' },
  'tg.chatId': [
    { required: true, message: t('settings.notify.validation.enterTelegramChatId'), trigger: 'change' },
    {
      pattern: /^-?\d+$/,
      message: t('settings.notify.validation.chatIdMustBeNumber'),
      trigger: ['blur', 'change',]
    },
  ],
  'webhook.url': [
    { required: true, message: t('settings.notify.validation.enterWebhookUrl'), trigger: 'change' },
    { type: 'url', message: t('settings.notify.validation.enterValidUrl'), trigger: 'change' },
  ]
})

const handleEmailModeChange = (useCustom) => {
  if (useCustom) {
    if (!noticeConfig.value.email.port) {
      noticeConfig.value.email.port = 465
    }
    if (noticeConfig.value.email.secure === undefined) {
      noticeConfig.value.email.secure = true
    }
  }
}

const handlePortChange = (port) => {
  if (port === 465) {
    noticeConfig.value.email.secure = true
  } else {
    noticeConfig.value.email.secure = false
  }
}

const isPlusActive = computed(() => $store.isPlusActive)

const handleSave = () => {
  formRef.value.validate(async (valid) => {
    if (!valid) return

    if (noticeConfig.value.type === 'webhook') {
      const { template, headers } = noticeConfig.value.webhook || {}

      if (template) {
        try {
          JSON.parse(template)
        } catch (e) {
          $message.error(t('settings.notify.invalidTemplateJson'))
          return
        }
      }

      if (headers) {
        try {
          JSON.parse(headers)
        } catch (e) {
          $message.error(t('settings.notify.invalidHeadersJson'))
          return
        }
      }
    }

    try {
      loading.value = true
      await $api.updateNotifyConfig({ noticeConfig: { ...noticeConfig.value } })
      $notification.success({
        title: t('settings.notify.testPassedSaveSuccess'),
        message: t('settings.notify.confirmReceiveTest')
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
    $message.success(t('settings.notify.formatSuccess'))
  } catch (e) {
    $message.warning(t('settings.notify.formatFailed'))
  }
}

onMounted(() => {
  getNotifyList()
  getNotifyConfig()
})
</script>

<style lang="scss" scoped>
.form_item {
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

