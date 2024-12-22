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
          @click="gotoPlusPage"
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
import { useRouter } from 'vue-router'

const { proxy: { $store } } = getCurrentInstance()
const router = useRouter()

const isPlusActive = computed(() => $store.isPlusActive)

const gotoPlusPage = () => {
  router.push('/setting?tabKey=plus')
}
</script>

<style lang="scss">
.plus_support_tip {
  display: flex;
  align-items: center;
}

</style>

