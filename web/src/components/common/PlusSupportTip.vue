<template>
  <el-tooltip
    :disabled="isPlusActive"
    placement="top"
  >
    <template #content>
      <div class="plus_support_tip">
        {{ t('common.plusActivationRequired') }}
        <el-button
          size="small"
          type="primary"
          link
          @click="gotoPlusPage"
        >
          {{ t('common.goActivate') }}
        </el-button>
      </div>
    </template>
    <slot />
  </el-tooltip>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'

const { proxy: { $store } } = getCurrentInstance()
const router = useRouter()
const { t } = useI18n()

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

