<template>
  <div class="top_bar_container">
    <div class="bar_wrap">
      <h2>{{ title }}</h2>
      <!-- <el-icon><UserFilled /></el-icon> -->

      <el-popover placement="bottom" trigger="hover">
        <template #reference>
          <div class="right_wrap">
            <el-icon><User /></el-icon>
            <span>{{ user }}</span>
          </div>
        </template>
        <el-button
          type="primary"
          class="logout_btn"
          link
          @click="handleLogout"
        >
          安全退出
        </el-button>
      </el-popover>
    </div>
  </div>
</template>

<script setup>
import { getCurrentInstance, computed } from 'vue'
import { User } from '@element-plus/icons-vue'

const { proxy: { $router, $store, $message } } = getCurrentInstance()

let user = computed(() => {
  return $store.user
})

let title = computed(() => {
  return $store.title
})

const handleLogout = () => {
  $store.clearJwtToken()
  $message({ type: 'success', message: '已安全退出', center: true })
  $router.push('/login')
}
</script>

<style lang="scss" scoped>
.top_bar_container {
  height: 60px;
  background-color: #fff;
  box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.1);
  position: sticky;
  top: 0;
  z-index: 999;
  .bar_wrap {
    height: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 20px;
    h2 {
      font-size: 18px;
    }
    .right_wrap {
      display: flex;
      align-items: center;
      // color: red;
      color: var(--el-menu-text-color);
      span {
        margin-left: 3px;
      }
      .logout_btn {
        margin: 0 10px 0 15px;
      }
      // color: var(--el-button-text-color);
    }
  }
}
</style>