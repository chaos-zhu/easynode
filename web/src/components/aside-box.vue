<template>
  <div class="aside_container">
    <div class="logo_wrap">
      <img src="@/assets/logo.png" alt="logo">
      <h1>EasyNode</h1>
    </div>
    <el-menu
      :default-active="defaultActiveMenu"
      class="menu"
      @select="handleSelect"
    >
      <el-menu-item v-for="(item, index) in menuList" :key="index" :index="item.index">
        <template #title>
          <el-icon>
            <component :is="item.icon" />
          </el-icon>
          <span>{{ item.name }}</span>
        </template>
      </el-menu-item>
    </el-menu>
    <!-- <div class="logout_wrap">
      <el-button type="info" link @click="handleLogout">退出登录</el-button>
    </div> -->
  </div>
</template>

<script setup>
import { reactive, markRaw, getCurrentInstance, computed, watchEffect } from 'vue'
import {
  Menu as IconMenu,
  Key,
  Setting,
  ScaleToOriginal,
  ArrowRight,
  Pointer,
  FolderOpened
} from '@element-plus/icons-vue'
import { useRoute } from 'vue-router'

const route = useRoute()

const { proxy: { $router, $route, $store, $message } } = getCurrentInstance()

let menuList = reactive([
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
    name: '一键指令',
    icon: markRaw(Pointer),
    index: '/onekey'
  },
  {
    name: '脚本库',
    icon: markRaw(ArrowRight),
    index: '/scripts'
  },
  {
    name: '系统设置',
    icon: markRaw(Setting),
    index: '/setting'
  },
])

// eslint-disable-next-line no-useless-escape
const regex = /^\/([^\/]+)/
let defaultActiveMenu = computed(() => {
  const match = route.path.match(regex)
  return match[0]
})

watchEffect(() => {
  let idx = route.path.match(regex)[0]
  let targetRoute = menuList.find(item => item.index === idx)
  $store.setTitle(targetRoute?.name || '')
})

const handleSelect = (path) => {
  // console.log(path)
  $router.push(path)
}
</script>

<style lang="scss" scoped>
.aside_container {
  background-color: #fff;
  border-right: 1px solid var(--el-menu-border-color);
  width: 180px;
  display: flex;
  flex-direction: column;
  :deep(.el-menu) {
    border-right: none;
  }
  .logo_wrap {
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 15px 0;
    img {
      height: 30px;
      width: 30px;
    }
    h1 {
      color: #1890ff;
      font-size: 16px;
      margin: 0 5px;
      font-weight: 600;
      font-size: 16px;
      vertical-align: middle;
    }
  }
  .logout_wrap {
    margin-top: auto;
    display: flex;
    // justify-content: center;
    align-items: center;
    padding: 15px 0;
    margin-left: 20px;
  }
}
</style>