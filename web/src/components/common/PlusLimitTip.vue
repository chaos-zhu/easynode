<template>
  <div v-show="!isPlusActive" class="plus_limit_container">
    <div class="plus_limit_content">
      <el-icon class="lock-icon"><Lock /></el-icon>
      <div class="plus_label">PLUS</div>
      <p>此功能仅限PLUS版使用, <span class="to_active" @click="gotoPlusPage">去激活</span></p>
    </div>
  </div>
  <slot />
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import { useRouter } from 'vue-router'
import { Lock } from '@element-plus/icons-vue'

const { proxy: { $store } } = getCurrentInstance()
const router = useRouter()

const isPlusActive = computed(() => $store.isPlusActive)

const gotoPlusPage = () => {
  router.push('/setting?tabKey=plus')
}
</script>

<style lang="scss" scoped>
.plus_limit_container {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.7);
  z-index: 10;
  display: flex;
  align-items: center;
  justify-content: center;

  .plus_limit_content {
    text-align: center;
    color: #fff;

    .lock-icon {
      font-size: 32px;
      margin-bottom: 12px;
    }

    .plus_label {
      font-size: 20px;
      font-weight: bold;
      color: #ffd700;
      margin-bottom: 8px;
    }

    p {
      font-size: 14px;
      margin: 0;
      opacity: 0.9;
      .to_active {
        color: #ffd700;
        text-decoration: underline;
        cursor: pointer;
      }
    }
  }
}
</style>
