<template>
  <el-menu
    :default-active="defaultActiveMenu"
    :collapse="menuCollapse"
    :mode="mode"
    class="menu"
    :class="{ 'horizontal_menu': mode === 'horizontal' }"
    :collapse-transition="true"
    @select="handleSelect"
  >
    <el-menu-item v-for="(item, index) in list" :key="index" :index="item.index">
      <el-icon>
        <component :is="item.icon" />
      </el-icon>
      <template #title>
        <span>{{ item.name }}</span>
      </template>
    </el-menu-item>
  </el-menu>
</template>

<script setup>
import { computed, markRaw, getCurrentInstance, watchEffect } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import {
  Menu as IconMenu,
  Key,
  Setting,
  ScaleToOriginal,
  ArrowRight,
  Pointer,
  FolderOpened
} from '@element-plus/icons-vue'

const props = defineProps({
  mode: {
    type: String,
    default: 'vertical'
  }
})

const { proxy: { $router, $store } } = getCurrentInstance()
const { t } = useI18n()

const emit = defineEmits(['select',])

const route = useRoute()

const list = computed(() => ([
  {
    name: t('menu.serverList'),
    icon: markRaw(IconMenu),
    index: '/server'
  },
  {
    name: t('menu.terminal'),
    icon: markRaw(ScaleToOriginal),
    index: '/terminal'
  },
  {
    name: t('menu.rdp'),
    icon: markRaw(ScaleToOriginal),
    index: '/rdp'
  },
  {
    name: t('menu.fileTransfer'),
    icon: markRaw(FolderOpened),
    index: '/file'
  },
  {
    name: t('menu.credentials'),
    icon: markRaw(Key),
    index: '/credentials'
  },
  {
    name: t('menu.scripts'),
    icon: markRaw(ArrowRight),
    index: '/scripts'
  },
  {
    name: t('menu.onekey'),
    icon: markRaw(Pointer),
    index: '/onekey'
  },
  {
    name: t('menu.settings'),
    icon: markRaw(Setting),
    index: '/setting'
  },
]))

const menuCollapse = computed(() => props.mode === 'horizontal' ? false : $store.menuCollapse)

// eslint-disable-next-line no-useless-escape
const regex = /^\/([^\/]+)/
const defaultActiveMenu = computed(() => {
  const match = route.path.match(regex)
  return match[0]
})

watchEffect(() => {
  const idx = route.path.match(regex)[0]
  const targetRoute = list.value.find(item => item.index === idx)
  $store.setTitle(targetRoute?.name || '')
})

const handleSelect = (path) => {
  $router.push(path)
  emit('select', path)
}
</script>

<style lang="scss" scoped>
.horizontal_menu {
  :deep(.el-menu-item) {
    .el-icon {
      margin-right: 8px;
    }
  }
}
</style>
