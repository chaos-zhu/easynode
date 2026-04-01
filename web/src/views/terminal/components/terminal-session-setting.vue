<template>
  <el-dialog
    v-model="visible"
    width="600px"
    :title="t('terminal.terminalSessionSettings')"
    :close-on-click-modal="false"
    @close="handleClose"
  >
    <el-form ref="formRef" :model="formData" label-width="140px">
      <el-form-item :label="t('terminal.sessionMaxSuspendTime')">
        <el-input-number
          v-model="formData.maxSuspendTime"
          :min="1"
          :max="9999"
          :step="1"
        />
        <span style="margin-left: 10px">{{ t('terminal.hours') }}</span>
        <div class="form_item_tip">{{ t('terminal.sessionMaxSuspendTimeTip') }}</div>
      </el-form-item>

      <el-form-item :label="t('terminal.sessionMaxSuspendCount')">
        <el-input-number
          v-model="formData.maxSuspendedPerUser"
          :min="1"
          :max="20"
          :step="1"
        />
        <span style="margin-left: 10px">{{ t('terminal.countUnit') }}</span>
        <div class="form_item_tip">{{ t('terminal.sessionMaxSuspendCountTip') }}</div>
      </el-form-item>

      <el-form-item :label="t('terminal.sessionHeartbeatInterval')">
        <el-input-number
          v-model="formData.heartbeatInterval"
          :min="10"
          :max="300"
          :step="10"
        />
        <span style="margin-left: 10px">{{ t('terminal.seconds') }}</span>
        <div class="form_item_tip">{{ t('terminal.sessionHeartbeatIntervalTip') }}</div>
      </el-form-item>

      <el-form-item :label="t('terminal.sessionReconnectAttempts')">
        <el-input-number
          v-model="formData.maxReconnectAttempts"
          :min="0"
          :max="10"
          :step="1"
        />
        <span style="margin-left: 10px">{{ t('terminal.times') }}</span>
        <div class="form_item_tip">{{ t('terminal.sessionReconnectAttemptsTip') }}</div>
      </el-form-item>

      <el-form-item :label="t('terminal.sessionReconnectInterval')">
        <el-input-number
          v-model="formData.reconnectInterval"
          :min="10"
          :max="300"
          :step="10"
        />
        <span style="margin-left: 10px">{{ t('terminal.seconds') }}</span>
        <div class="form_item_tip">{{ t('terminal.sessionReconnectIntervalTip') }}</div>
      </el-form-item>

      <el-form-item :label="t('terminal.sessionBufferSize')">
        <el-input-number
          v-model="formData.maxBufferSize"
          :min="10"
          :max="500"
          :step="10"
        />
        <span style="margin-left: 10px">{{ t('terminal.kilobytes') }}</span>
        <div class="form_item_tip">{{ t('terminal.sessionBufferSizeTip') }}</div>
      </el-form-item>
    </el-form>

    <template #footer>
      <span class="footer">
        <el-button
          size="small"
          link
          type="primary"
          @click="handleRestoreDefaults"
          style="margin-right: 20px;"
        >
          {{ t('common.restoreDefault') }}
        </el-button>
        <div class="btn_action">
          <el-button @click="handleClose">{{ t('common.cancel') }}</el-button>
          <el-button type="primary" :loading="saving" @click="handleSave">{{ t('common.save') }}</el-button>
        </div>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, watch, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'

const { proxy: { $message, $api } } = getCurrentInstance()
const { t } = useI18n()

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:show',])

const visible = ref(false)
const saving = ref(false)

// 默认配置（与后端DEFAULT_SESSION_CONFIG保持一致）
const DEFAULT_CONFIG = {
  maxSuspendTime: 24,
  maxSuspendedPerUser: 10,
  heartbeatInterval: 30,
  maxReconnectAttempts: 3,
  reconnectInterval: 60,
  maxBufferSize: 50
}

// 初始配置
const formData = ref({ ...DEFAULT_CONFIG })

watch(() => props.show, (val) => {
  visible.value = val
  if (val) {
    loadSettings()
  }
})

watch(visible, (val) => {
  if (!val) {
    emit('update:show', false)
  }
})

// 加载设置
const loadSettings = async () => {
  const res = await $api.getTerminalSessionConfig()
  if (res.data && res.data.config) {
    // 后端已返回完整的配置（包含默认值）
    formData.value = { ...res.data.config }
  }
}

// 保存设置
const handleSave = async () => {
  saving.value = true
  try {
    await $api.updateTerminalSessionConfig({ config: formData.value })
    $message.success(t('terminal.saveSuccess'))
    handleClose()
  } finally {
    saving.value = false
  }
}

// 恢复默认值
const handleRestoreDefaults = () => {
  formData.value = { ...DEFAULT_CONFIG }
}

// 关闭对话框
const handleClose = () => {
  visible.value = false
}
</script>

<style lang="scss" scoped>
.form_item_tip {
  font-size: 12px;
  color: var(--el-text-color-secondary);
  margin-top: 5px;
  margin-left: 10px;
}

:deep(.el-input-number) {
  width: 150px;
}

.footer {
  display: flex;
  .btn_action {
    margin-left: auto;
  }
}
</style>
