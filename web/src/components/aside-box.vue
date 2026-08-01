<template>
  <aside class="aside_container">
    <MenuList />

    <div class="aside_footer">
      <AccountMenu
        :collapsed="menuCollapse"
        :discount="discount"
        :is-new="isNew"
        @open-version="emit('open-version')"
      />
    </div>
  </aside>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import MenuList from './menuList.vue'
import AccountMenu from './account-menu.vue'

defineProps({
  discount: { type: [Boolean, Number, String,], default: false },
  isNew: { type: Boolean, default: false }
})

const emit = defineEmits(['open-version',])
const { proxy: { $store } } = getCurrentInstance()
const menuCollapse = computed(() => $store.menuCollapse)

</script>

<style lang="scss" scoped>
.aside_container {
  min-width: 64px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background-color: #fff;

  :deep(.el-menu) {
    padding-top: 8px;
    border-right: none;
  }

  .aside_footer {
    margin-top: auto;
    padding: 8px 10px 16px;
    border-top: 1px solid var(--el-border-color-lighter);
  }
}
</style>
