<template>
  <div class="aside_container">
    <div class="logo_wrap">
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
  $store.setMenuCollapse(!menuCollapse.value)
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
    position: relative;
    img {
      height: 30px;
      width: 30px;
    }
    h1 {
      position: absolute;
      left: 52px;
      font-size: 14px;
      color: var(--el-menu-active-color);
      font-weight: 600;
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