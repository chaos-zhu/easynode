<template>
  <el-dialog
    v-model="visible"
    width="600px"
    top="120px"
    title="终端设置"
    :append-to-body="false"
    :close-on-click-modal="false"
  >
    <el-form
      ref="formRef"
      label-suffix="："
      label-width="60px"
      :show-message="false"
    >
      <el-form-item label="主题" prop="theme">
        <el-select v-model="theme" placeholder="" style="width: 100%;">
          <el-option
            v-for="(value, key) in themeList"
            :key="key"
            :label="key"
            :value="key"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="背景" prop="backgroundImage">
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
            v-for="url in backgroundImages"
            :key="url"
            :class="background === url ? 'active' : ''"
            @click="changeBackground(url)"
          >
            <el-image class="image" :src="url" />
          </li>
        </ul>
        <div class="custom_background">
          <el-input
            v-model="backgroundUrl"
            clearable
            placeholder="自定义背景图片url"
            autocomplete="on"
          />
        </div>
      </el-form-item>
      <el-form-item label="字体" prop="fontSize">
        <el-input-number v-model="fontSize" :min="12" :max="30" />
      </el-form-item>
    </el-form>
    <template #footer>
      <span class="dialog_footer">
        <el-button @click="visible = false">关闭</el-button>
      </span>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, computed } from 'vue'
import themeList from 'xterm-theme'

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  },
  themeName: {
    required: true,
    type: String
  },
  background: {
    required: true,
    type: [String, null,]
  },
  fontSize: {
    required: true,
    type: Number
  }
})
const emit = defineEmits(['update:show', 'update:themeName', 'update:background', 'update:fontSize',])

const backgroundImages = ref([
  '/terminal/03.png',
  '/terminal/04.png',
  '/terminal/01.png',
  '/terminal/02.png',
  '/terminal/05.png',
  '/terminal/06.png',
  '/terminal/07.jpg',
  '/terminal/08.jpg',
  '/terminal/09.png',
])

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})
const theme = computed({
  get: () => props.themeName,
  set: (newVal) => emit('update:themeName', newVal)
})
const backgroundUrl = computed({
  get: () => props.background,
  set: (newVal) => emit('update:background', newVal)
})
const fontSize = computed({
  get: () => props.fontSize,
  set: (newVal) => emit('update:fontSize', newVal)
})

const changeBackground = (url) => {
  backgroundUrl.value = url || ''
}
</script>

<style lang="scss" scoped>
.background_list {
  display: flex;
  flex-wrap: wrap;
  li {
    width: 130px;
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
</style>
