<template>
  <el-drawer
    v-model="visible"
    title="其他设置"
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
      <el-form-item label="自动重连" prop="autoReconnect">
        <PlusSupportTip>
          <span>
            <el-switch
              v-model="autoReconnect"
              class="switch"
              inline-prompt
              :disabled="!isPlusActive"
              style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
              active-text="开启"
              inactive-text="关闭"
            />
            <span class="plus_support_tip_text">(Plus专属功能)</span>
          </span>
        </PlusSupportTip>
      </el-form-item>
      <el-form-item label="脚本执行" prop="autoExecuteScript">
        <el-tooltip
          effect="dark"
          content="启用后从脚本库选中脚本后自动执行(回车操作)"
          placement="right"
        >
          <el-switch
            v-model="autoExecuteScript"
            class="switch"
            inline-prompt
            style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
            active-text="自动"
            inactive-text="手动"
          />
        </el-tooltip>
      </el-form-item>
    </el-form>
    <template #footer>
      <span class="dialog_footer">
        <el-button @click="visible = false">关闭</el-button>
      </span>
    </template>
  </el-drawer>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import useMobileWidth from '@/composables/useMobileWidth'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'

const { proxy: { $store } } = getCurrentInstance()
const { isMobileScreen } = useMobileWidth()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show'])

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

const isPlusActive = computed(() => $store.isPlusActive)
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
.plus_support_tip_text {
  margin-left: 5px;
  color: var(--el-text-color-placeholder);
}
</style>
