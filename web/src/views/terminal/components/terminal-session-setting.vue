<template>
  <el-dialog
    v-model="visible"
    width="600px"
    title="终端会话设置"
    :close-on-click-modal="false"
    @close="handleClose"
  >
    <el-form ref="formRef" :model="formData" label-width="140px">
      <el-form-item label="最大挂起时间">
        <el-input-number
          v-model="formData.maxSuspendTime"
          :min="1"
          :max="9999"
          :step="1"
        />
        <span style="margin-left: 10px">小时</span>
        <div class="form_item_tip">(超过该时间后会话将自动销毁)</div>
      </el-form-item>

      <el-form-item label="最大挂起数">
        <el-input-number
          v-model="formData.maxSuspendedPerUser"
          :min="1"
          :max="20"
          :step="1"
        />
        <span style="margin-left: 10px">个</span>
        <div class="form_item_tip">(可同时挂起的会话数量上限)</div>
      </el-form-item>

      <el-form-item label="心跳检测间隔">
        <el-input-number
          v-model="formData.heartbeatInterval"
          :min="10"
          :max="300"
          :step="10"
        />
        <span style="margin-left: 10px">秒</span>
        <div class="form_item_tip">(挂起时检测会话连接状态的间隔)</div>
      </el-form-item>

      <el-form-item label="重连尝试次数">
        <el-input-number
          v-model="formData.maxReconnectAttempts"
          :min="0"
          :max="10"
          :step="1"
        />
        <span style="margin-left: 10px">次</span>
        <div class="form_item_tip">(连接断开后自动重连的最大尝试次数)</div>
      </el-form-item>

      <el-form-item label="重连间隔">
        <el-input-number
          v-model="formData.reconnectInterval"
          :min="10"
          :max="300"
          :step="10"
        />
        <span style="margin-left: 10px">秒</span>
        <div class="form_item_tip">(两次重连尝试之间的间隔时间)</div>
      </el-form-item>

      <el-form-item label="输出缓存大小">
        <el-input-number
          v-model="formData.maxBufferSize"
          :min="10"
          :max="500"
          :step="10"
        />
        <span style="margin-left: 10px">KB</span>
        <div class="form_item_tip">(挂起期间缓存的终端输出最大大小)</div>
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
          恢复默认
        </el-button>
        <div class="btn_action">
          <el-button @click="handleClose">取消</el-button>
          <el-button type="primary" :loading="saving" @click="handleSave">保存</el-button>
        </div>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, watch, getCurrentInstance } from 'vue'

const { proxy: { $message, $api } } = getCurrentInstance()

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
    $message.success('保存成功')
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
