<template>
  <el-menu
    :default-active="defaultActiveMenu"
    :collapse="menuCollapse"
    class="menu"
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
import { reactive, markRaw, getCurrentInstance, computed, watchEffect } from 'vue'
import { useRoute } from 'vue-router'
import {
  Menu as IconMenu,
  Key,
  Setting,
  ScaleToOriginal,
  ArrowRight,
  Pointer,
  FolderOpened
} from '@element-plus/icons-vue'
const { proxy: { $router, $store } } = getCurrentInstance()

const emit = defineEmits(['select',])

const route = useRoute()

const list = reactive([
  {
    name: '实例配置',
    icon: markRaw(IconMenu),
    index: '/server'
  },
  {
    name: '连接终端',
    icon: markRaw(ScaleToOriginal),
    index: '/terminal'
  },
  {
    name: '凭据管理',
    icon: markRaw(Key),
    index: '/credentials'
  },
  {
    name: '分组管理',
    icon: markRaw(FolderOpened),
    index: '/group'
  },
  {
    name: '脚本库',
    icon: markRaw(ArrowRight),
    index: '/scripts'
  },
  {
    name: '批量指令',
    icon: markRaw(Pointer),
    index: '/onekey'
  },
  {
    name: '系统设置',
    icon: markRaw(Setting),
    index: '/setting'
  },
])

const menuCollapse = computed(() => $store.menuCollapse)

// eslint-disable-next-line no-useless-escape
const regex = /^\/([^\/]+)/
const defaultActiveMenu = computed(() => {
  const match = route.path.match(regex)
  return match[0]
})

watchEffect(() => {
  const idx = route.path.match(regex)[0]
  const targetRoute = list.find(item => item.index === idx)
  $store.setTitle(targetRoute?.name || '')
})

const handleSelect = (path) => {
  // console.log(path)
  $router.push(path)
  emit('select', path)
}
</script>