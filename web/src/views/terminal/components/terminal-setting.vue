<template>
  <el-drawer
    v-model="visible"
    title="本地设置"
    :direction="isMobileScreen ? 'ttb' : 'ltr'"
    :close-on-click-modal="true"
    :close-on-press-escape="true"
    :modal="true"
    modal-class="local_setting_drawer"
    :size="isMobileScreen ? '80%' : '30%'"
  >
    <el-tabs tab-position="top">
      <el-tab-pane label="终端设置" lazy>
        <el-form
          ref="formRef"
          label-suffix="："
          label-width="100px"
          :show-message="false"
        >
          <el-form-item label="终端主题" prop="theme">
            <el-select v-model="theme" placeholder="" style="width: 100%;">
              <el-option
                v-for="(value, key) in themeList"
                :key="key"
                :label="key"
                :value="key"
              />
            </el-select>
          </el-form-item>
          <el-form-item label="终端字体" prop="fontSize">
            <el-input-number v-model="fontSize" :min="6" :max="30" />
          </el-form-item>
          <el-form-item label="终端背景" prop="backgroundImage">
            <ul class="background_list">
              <li :class="background ? '' : 'active'" @click="changeBackground('')">
                <el-image class="image">
                  <template #error>
                    <div class="theme_background_text">
                      主题背景
                    </div>
                  </template>
                </el-image>
              </li>
              <li
                v-for="item in defaultBackgroundImages"
                :key="item"
                :class="background === item ? 'active' : ''"
                :style="`background: ${item};`"
                @click="changeBackground(item)"
              />
            </ul>
            <div class="custom_background">
              <el-input
                v-model="background"
                clearable
                placeholder="自定义背景图片url"
                autocomplete="on"
              />
            </div>
          </el-form-item>
        </el-form>
      </el-tab-pane>
      <el-tab-pane label="快捷操作">
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
                  class="swtich"
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
                class="swtich"
                inline-prompt
                style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
                active-text="自动"
                inactive-text="手动"
              />
            </el-tooltip>
          </el-form-item>
        </el-form>
      </el-tab-pane>
      <el-tab-pane label="菜单选项">
        <el-form
          ref="formRef"
          label-suffix="："
          label-width="100px"
          :show-message="false"
        >
          <el-form-item label="脚本库" prop="scriptLibrary">
            <span class="script_library_switch">
              <el-switch
                v-model="scriptLibrary"
                class="swtich"
                inline-prompt
                style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
                active-text="开启"
                inactive-text="关闭"
              />
            </span>
            <el-radio-group
              v-model="scriptLibraryCascader"
              size="small"
              text-color="#fff"
              fill="#13ce66"
            >
              <el-radio-button :value="true">分组级联展示</el-radio-button>
              <el-radio-button :value="false">不分组单列展示</el-radio-button>
            </el-radio-group>
          </el-form-item>
        </el-form>
      </el-tab-pane>
    </el-tabs>
    <template #footer>
      <span class="dialog_footer">
        <el-button @click="visible = false">关闭</el-button>
      </span>
    </template>
  </el-drawer>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import themeList from 'xterm-theme'
import useMobileWidth from '@/composables/useMobileWidth'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'
const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})
const emit = defineEmits(['update:show',])

const { isMobileScreen } = useMobileWidth()
const defaultBackgroundImages = computed(() => $store.defaultBackgroundImages)

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})
const theme = computed({
  get: () => $store.terminalConfig.themeName,
  set: (newVal) => $store.setTerminalSetting({ themeName: newVal })
})
const background = computed({
  get: () => $store.terminalConfig.background,
  set: (newVal) => $store.setTerminalSetting({ background: newVal })
})
const fontSize = computed({
  get: () => $store.terminalConfig.fontSize,
  set: (newVal) => $store.setTerminalSetting({ fontSize: newVal })
})
const autoReconnect = computed({
  get: () => $store.terminalConfig.autoReconnect,
  set: (newVal) => $store.setTerminalSetting({ autoReconnect: newVal })
})
const autoExecuteScript = computed({
  get: () => $store.terminalConfig.autoExecuteScript,
  set: (newVal) => $store.setTerminalSetting({ autoExecuteScript: newVal })
})
const scriptLibrary = computed({
  get: () => $store.menuSetting.scriptLibrary,
  set: (newVal) => $store.setMenuSetting({ scriptLibrary: newVal })
})
const scriptLibraryCascader = computed({
  get: () => $store.menuSetting.scriptLibraryCascader,
  set: (newVal) => $store.setMenuSetting({ scriptLibraryCascader: newVal })
})
const isPlusActive = computed(() => $store.isPlusActive)

const changeBackground = (item) => {
  background.value = item || ''
}
</script>

<style lang="scss" scoped>
.background_list {
  display: flex;
  flex-wrap: wrap;
  li {
    width: 126px;
    height: 75px;
    box-sizing: border-box;
    border-radius: 3px;
    margin: 0 5px 5px 0;
    display: flex;
    align-items: center;
    background: var(--el-fill-color-light);
    color: var(--el-text-color-placeholder);
    &:hover {
      cursor: pointer;
      box-shadow: 0 0 5px #1890ff;
    }
    &.active {
      box-shadow: 0 0 5px #1890ff;
      border: 1px solid #1890ff;
    }
    .image {
      width: 100%;
      height: 100%;
    }
    .theme_background_text {
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
    }
  }
}
.custom_background {
  width: 90%;
}
.dialog_footer {
  display: flex;
  justify-content: center;
}
.script_library_switch {
  margin-right: 20px;
}
</style>

<style lang="scss">
.local_setting_drawer {
  .el-drawer__header {
    margin-bottom: 0 !important;
  }
}
.plus_support_tip_text {
  margin-left: 5px;
  color: var(--el-text-color-placeholder);
}
</style>