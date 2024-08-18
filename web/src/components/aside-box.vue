<template>
  <div class="aside_container">
    <div class="logo_wrap">
      <img src="@/assets/logo.png" alt="logo">
      <Transition name="el-fade-in-linear">
        <h1 v-show="!menuCollapse">EasyNode</h1>
      </Transition>
    </div>
    <el-menu
      :default-active="defaultActiveMenu"
      :collapse="menuCollapse"
      class="menu"
      :collapse-transition="true"
      @select="handleSelect"
    >
      <el-menu-item v-for="(item, index) in menuList" :key="index" :index="item.index">
        <el-icon>
          <component :is="item.icon" />
        </el-icon>
        <template #title>
          <span>{{ item.name }}</span>
        </template>
      </el-menu-item>
    </el-menu>
    <!-- <div class="logout_wrap">
      <el-button type="info" link @click="handleLogout">退出登录</el-button>
    </div> -->
    <div class="collapse" @click="handleCollapse">
      <el-icon v-if="menuCollapse"><Expand /></el-icon>
      <el-icon v-else><Fold /></el-icon>
    </div>
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
  FolderOpened,
  Expand,
  Fold
} from '@element-plus/icons-vue'
import { useRoute } from 'vue-router'

const route = useRoute()

const { proxy: { $router, $store } } = getCurrentInstance()

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

let menuCollapse = computed(() => $store.menuCollapse)

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

const handleCollapse = () => {
  $store.setMenuCollapse(!menuCollapse.value)
}
</script>

<style lang="scss" scoped>
.aside_container {
  background-color: #fff;
  // width: 180px;
  display: flex;
  flex-direction: column;
  :deep(.el-menu) {
    border-right: none;
  }
  .logo_wrap {
    display: flex;
    align-items: center;
    padding: 15px 0 15px 20px;
    position: relative;
    img {
      height: 30px;
      width: 30px;
    }
    h1 {
      position: absolute;
      left: 52px;
      font-size: 14px;
      // color: #1890ff;
    }
  }
  .collapse {
    margin-top: auto;
    margin-left: auto;
    margin-bottom: 10px;
    margin-right: 10px;
    cursor: pointer;
    &:hover {
      color: #1890ff;
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