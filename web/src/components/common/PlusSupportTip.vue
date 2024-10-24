<template>
  <el-tooltip
    :disabled="isPlusActive"
    placement="top"
  >
    <template #content>
      <div class="plus_support_tip">
        此功能需要激活Plus后使用,
        <el-button
          size="small"
          type="primary"
          link
          @click="handlePlusSupport"
        >
          去激活
        </el-button>
      </div>
    </template>
    <slot />
  </el-tooltip>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'

const { proxy: { $store } } = getCurrentInstance()

const isPlusActive = computed(() => $store.isPlusActive)

const handlePlusSupport = () => {
  window.open('https://en.221022.xyz/buy-plus', '_blank')
}
</script>

<style lang="scss">
.plus_support_tip {
  display: flex;
  align-items: center;
}

</style>

