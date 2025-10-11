<template>
  <el-drawer
    v-model="visible"
    title="基础设置"
    :direction="isMobileScreen ? 'ttb' : 'ltr'"
    :close-on-click-modal="true"
    :close-on-press-escape="true"
    :modal="true"
    modal-class="terminal_setting_drawer"
    :size="isMobileScreen ? '80%' : '30%'"
  >
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
      <el-form-item label="终端字体" prop="fontFamily">
        <el-select v-model="fontFamily" placeholder="选择字体" style="width: 100%;">
          <el-option
            v-for="font in commonFonts"
            :key="font.value"
            :label="font.label"
            :value="font.value"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="字体大小" prop="fontSize">
        <el-input-number v-model="fontSize" :min="6" :max="30" />
      </el-form-item>
      <el-form-item label="字体颜色" prop="fontColor">
        <div class="font_color_list">
          <div :class="['color_item', 'theme_color', { 'active': !fontColor }]" @click="setThemeColor">
            <span class="color_text">主题颜色</span>
          </div>
          <div :class="['color_item', 'color_picker_wrapper', { 'active': !!fontColor }]">
            <el-color-picker
              v-model="customFontColor"
              show-alpha
              :predefine="predefineColors"
              @change="handleColorChange"
            />
          </div>
        </div>
      </el-form-item>
      <el-form-item label="光标颜色" prop="cursorColor">
        <div class="font_color_list">
          <div :class="['color_item', 'theme_color', { 'active': !cursorColor }]" @click="setThemeCursorColor">
            <span class="color_text">主题颜色</span>
          </div>
          <div :class="['color_item', 'color_picker_wrapper', { 'active': !!cursorColor }]">
            <el-color-picker
              v-model="customCursorColor"
              show-alpha
              :predefine="predefineColors"
              @change="handleCursorColorChange"
            />
          </div>
        </div>
      </el-form-item>
      <el-form-item label="选中颜色" prop="selectionColor">
        <div class="font_color_list">
          <div class="color_item color_picker_wrapper active">
            <el-color-picker
              v-model="selectionColor"
              show-alpha
              :predefine="predefineColors"
            />
          </div>
        </div>
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
    <template #footer>
      <span class="dialog_footer">
        <el-button @click="visible = false">关闭</el-button>
      </span>
    </template>
  </el-drawer>
</template>

<script setup>
import { computed, getCurrentInstance, ref } from 'vue'
import themeList from 'xterm-theme'
import useMobileWidth from '@/composables/useMobileWidth'

const { proxy: { $store } } = getCurrentInstance()
const { isMobileScreen } = useMobileWidth()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show'])

// 全平台通用字体列表
const commonFonts = [
  { label: 'monospace', value: 'monospace' },
  { label: 'Courier New', value: 'Courier New, Courier, monospace' },
  { label: 'Courier', value: 'Courier, monospace' },
  { label: 'Consolas', value: 'Consolas, monospace' },
  { label: 'Monaco', value: 'Monaco, monospace' },
  { label: 'Menlo', value: 'Menlo, monospace' },
  { label: 'Cascadia Code', value: 'Cascadia Code, monospace' }
]

// 预定义颜色
const predefineColors = [
  '#ffffff',
  '#00ff41',
  '#00ffff',
  '#ff00ff',
  '#ffff00',
  '#ff0000',
  '#00ff00',
  '#0000ff',
  '#000000'
]

// 保存最后选择的自定义颜色
const lastCustomColor = ref('#ffffff')
const lastCustomCursorColor = ref('#00ff41')

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

const fontFamily = computed({
  get: () => $store.terminalConfig.fontFamily || 'monospace',
  set: (newVal) => $store.setTerminalSetting({ fontFamily: newVal })
})

const fontColor = computed({
  get: () => $store.terminalConfig.fontColor,
  set: (newVal) => $store.setTerminalSetting({ fontColor: newVal })
})

const customFontColor = computed({
  get: () => {
    // 如果有自定义颜色，显示自定义颜色；否则显示上次选择的颜色
    if (fontColor.value) {
      lastCustomColor.value = fontColor.value
      return fontColor.value
    }
    return lastCustomColor.value
  },
  set: (newVal) => {
    lastCustomColor.value = newVal
    fontColor.value = newVal
  }
})

const setThemeColor = () => {
  fontColor.value = ''
}

const setCustomColor = (color) => {
  fontColor.value = color
}

const handleColorChange = (color) => {
  if (color) {
    fontColor.value = color
  }
}

const cursorColor = computed({
  get: () => $store.terminalConfig.cursorColor,
  set: (newVal) => $store.setTerminalSetting({ cursorColor: newVal })
})

const customCursorColor = computed({
  get: () => {
    if (cursorColor.value) {
      lastCustomCursorColor.value = cursorColor.value
      return cursorColor.value
    }
    return lastCustomCursorColor.value
  },
  set: (newVal) => {
    lastCustomCursorColor.value = newVal
    cursorColor.value = newVal
  }
})

const setThemeCursorColor = () => {
  cursorColor.value = ''
}

const handleCursorColorChange = (color) => {
  if (color) {
    cursorColor.value = color
  }
}

const selectionColor = computed({
  get: () => $store.terminalConfig.selectionColor,
  set: (newVal) => $store.setTerminalSetting({ selectionColor: newVal })
})

const changeBackground = (item) => {
  background.value = item || ''
}
</script>

<style lang="scss" scoped>
.font_color_list {
  display: flex;
  align-items: center;
  gap: 8px;

  .color_item {
    height: 30px;
    border-radius: 3px;
    box-sizing: border-box;
    cursor: pointer;
    border: 1px solid var(--el-border-color);
    display: flex;
    align-items: center;
    justify-content: center;

    &:hover {
      box-shadow: 0 0 5px #1890ff;
    }

    &.active {
      box-shadow: 0 0 5px #1890ff;
      border: 1px solid #1890ff;
    }

    &.theme_color {
      width: 90px;
      background: var(--el-fill-color-light);
      color: var(--el-text-color-placeholder);

      .color_text {
        font-size: 11px;
      }
    }

    &.color_picker_wrapper {
      width: 30px;
      padding: 0;
      border: none;
      box-shadow: none;
      background: transparent;

      &:hover {
        box-shadow: none;
      }

      :deep(.el-color-picker__trigger) {
        width: 30px;
        height: 30px;
        border-radius: 3px;
        border: 1px solid var(--el-border-color);
        padding: 0;

        &:hover {
          box-shadow: 0 0 5px #1890ff;
        }
      }

      &.active :deep(.el-color-picker__trigger) {
        box-shadow: 0 0 5px #1890ff;
        border: 1px solid #1890ff;
      }
    }
  }
}

.background_list {
  display: flex;
  flex-wrap: wrap;
  li {
    width: 90px;
    height: 55px;
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
      font-size: 11px;
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
</style>

<style lang="scss">
.terminal_setting_drawer {
  .el-drawer__header {
    margin-bottom: 0 !important;
  }
}
</style>