<template>
  <el-drawer
    v-model="visible"
    :title="t('terminal.otherSettings')"
    :direction="isMobileScreen ? 'ttb' : 'ltr'"
    :close-on-click-modal="true"
    :close-on-press-escape="true"
    :modal="true"
    modal-class="other_setting_drawer"
    :size="isMobileScreen ? '80%' : '30%'"
  >
    <el-form
      ref="formRef"
      label-suffix="："
      label-width="100px"
      :show-message="false"
    >
      <el-form-item :label="t('terminal.autoReconnect')" prop="autoReconnect">
        <span>
          <el-switch
            v-model="autoReconnect"
            class="switch"
            inline-prompt
            style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
            :active-text="t('terminal.enabled')"
            :inactive-text="t('terminal.disabled')"
          />
        </span>
      </el-form-item>
      <el-form-item :label="t('terminal.scriptExecution')" prop="autoExecuteScript">
        <el-tooltip
          effect="dark"
          :content="t('terminal.scriptExecutionTip')"
          placement="right"
        >
          <el-switch
            v-model="autoExecuteScript"
            class="switch"
            inline-prompt
            style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
            :active-text="t('terminal.auto')"
            :inactive-text="t('terminal.manual')"
          />
        </el-tooltip>
      </el-form-item>
      <el-form-item :label="t('terminal.contextMenu')" prop="autoShowContextMenu">
        <el-tooltip
          effect="dark"
          :content="t('terminal.contextMenuTip')"
          placement="right"
        >
          <el-switch
            v-model="autoShowContextMenu"
            class="switch"
            inline-prompt
            style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
            :active-text="t('terminal.auto')"
            :inactive-text="t('terminal.manual')"
          />
        </el-tooltip>
      </el-form-item>
    </el-form>
    <template #footer>
      <span class="dialog_footer">
        <el-button @click="visible = false">{{ t('common.close') }}</el-button>
      </span>
    </template>
  </el-drawer>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'
import useMobileWidth from '@/composables/useMobileWidth'

const { proxy: { $store } } = getCurrentInstance()
const { isMobileScreen } = useMobileWidth()
const { t } = useI18n()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show',])

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

const autoReconnect = computed({
  get: () => $store.terminalConfig.autoReconnect,
  set: (newVal) => $store.setTerminalSetting({ autoReconnect: newVal })
})

const autoExecuteScript = computed({
  get: () => $store.terminalConfig.autoExecuteScript,
  set: (newVal) => $store.setTerminalSetting({ autoExecuteScript: newVal })
})

const autoShowContextMenu = computed({
  get: () => $store.terminalConfig.autoShowContextMenu,
  set: (newVal) => $store.setTerminalSetting({ autoShowContextMenu: newVal })
})

</script>

<style lang="scss" scoped>
.dialog_footer {
  display: flex;
  justify-content: center;
}
</style>

<style lang="scss">
.other_setting_drawer {
  .el-drawer__header {
    margin-bottom: 0 !important;
  }
}
</style>
