<template>
  <div class="aside_container">
    <div class="logo_wrap" @click="toggleMenuPosition">
      <img src="/logo_v2_01.png" alt="logo">
      <Transition name="el-fade-in-linear">
        <h1 v-show="!menuCollapse">EasyNode</h1>
      </Transition>
    </div>
    <MenuList />

    <div class="aside_footer">
      <div class="theme_switch">
        <el-switch
          v-model="isDark"
          inline-prompt
          :active-icon="Moon"
          :inactive-icon="Sunny"
          class="dark_switch"
        />
      </div>
      <div class="collapse" @click="handleCollapse">
        <el-icon v-if="menuCollapse"><Expand /></el-icon>
        <el-icon v-else><Fold /></el-icon>
      </div>
    </div>
  </div>
</template>

<script setup>
import { getCurrentInstance, computed } from 'vue'
import { Expand, Fold, Moon, Sunny } from '@element-plus/icons-vue'
import MenuList from './menuList.vue'

const { proxy: { $store } } = getCurrentInstance()

let menuCollapse = computed(() => $store.menuCollapse)
const isDark = computed({
  get: () => $store.isDark,
  set: (isDark) => {
    $store.setTheme(isDark)
  }
})

const handleCollapse = () => {
  $store.setMenuCollapse()
}

const toggleMenuPosition = () => {
  const newPosition = 'top' // 从左侧模式切换到顶部模式
  $store.setMenuPosition(newPosition)
}
</script>

<style lang="scss" scoped>
.aside_container {
  overflow-x: auto;
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
    cursor: pointer;

    img {
      height: 30px;
      width: 30px;
    }

    h1 {
      font-size: 14px;
      background: linear-gradient(to right, #ffc021, #e4d1a1);
      background-clip: text;
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      font-weight: 600;
      user-select: none;
    }
  }
  .aside_footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-top: auto;
    .theme_switch {
      margin-top: auto;
      margin-left: auto;
      margin-bottom: 10px;
      margin-right: 10px;
    }
    .collapse {
      margin-left: auto;
      margin-bottom: 10px;
      margin-right: 10px;
      cursor: pointer;
      &:hover {
        color: #1890ff;
      }
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