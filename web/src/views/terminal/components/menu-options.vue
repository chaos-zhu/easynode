<template>
  <el-drawer
    v-model="visible"
    :title="t('terminal.menuOptions')"
    :direction="isMobileScreen ? 'ttb' : 'ltr'"
    :close-on-click-modal="true"
    :close-on-press-escape="true"
    :modal="true"
    modal-class="menu_options_drawer"
    :size="isMobileScreen ? '80%' : '30%'"
  >
    <el-form
      ref="formRef"
      label-suffix="："
      label-width="100px"
      :show-message="false"
    >
      <el-form-item :label="t('menu.serverList')" prop="instanceGroup">
        <el-radio-group
          v-model="hostGroupCascader"
          size="small"
          text-color="#fff"
          fill="#13ce66"
        >
          <el-radio-button :value="true">{{ t('terminal.groupCascader') }}</el-radio-button>
          <el-radio-button :value="false">{{ t('terminal.flatList') }}</el-radio-button>
        </el-radio-group>
      </el-form-item>
      <el-form-item :label="t('menu.scripts')" prop="scriptLibrary">
        <el-radio-group
          v-model="scriptLibraryCascader"
          size="small"
          text-color="#fff"
          :fill="scriptLibrary ? '#13ce66' : '#999'"
          :disabled="!scriptLibrary"
        >
          <el-radio-button :value="true">{{ t('terminal.groupCascader') }}</el-radio-button>
          <el-radio-button :value="false">{{ t('terminal.flatList') }}</el-radio-button>
        </el-radio-group>
        <span class="script_library_switch">
          <el-switch
            v-model="scriptLibrary"
            class="switch"
            inline-prompt
            style="--el-switch-on-color: #13ce66; --el-switch-off-color: #999"
            :active-text="t('terminal.show')"
            :inactive-text="t('terminal.hide')"
          />
        </span>
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

const emit = defineEmits(['update:show'])

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

const scriptLibrary = computed({
  get: () => $store.menuSetting.scriptLibrary,
  set: (newVal) => $store.setMenuSetting({ scriptLibrary: newVal })
})

const scriptLibraryCascader = computed({
  get: () => $store.menuSetting.scriptLibraryCascader,
  set: (newVal) => $store.setMenuSetting({ scriptLibraryCascader: newVal })
})

const hostGroupCascader = computed({
  get: () => $store.menuSetting.hostGroupCascader,
  set: (newVal) => $store.setMenuSetting({ hostGroupCascader: newVal })
})
</script>

<style lang="scss" scoped>
.dialog_footer {
  display: flex;
  justify-content: center;
}
.script_library_switch {
  margin-left: 20px;
}
</style>

<style lang="scss">
.menu_options_drawer {
  .el-drawer__header {
    margin-bottom: 0 !important;
  }
}
</style>
