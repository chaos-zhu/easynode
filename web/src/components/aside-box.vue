<template>
  <aside class="aside_container">
    <div class="logo_wrap">
      <img src="/logo_v2_01.png" alt="logo">
      <Transition name="el-fade-in-linear">
        <h1 v-show="!menuCollapse">EasyNode</h1>
      </Transition>
    </div>

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
    border-right: none;
  }

  .logo_wrap {
    height: 60px;
    display: flex;
    align-items: center;
    justify-content: flex-start;
    padding: 15px 17px;
    overflow: hidden;

    img {
      width: 30px;
      height: 30px;
      flex-shrink: 0;
    }

    h1 {
      margin-left: 2px;
      font-size: 14px;
      background: linear-gradient(to right, #ffc021, #e4d1a1);
      background-clip: text;
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      font-weight: 600;
      white-space: nowrap;
      user-select: none;
    }

  }

  .aside_footer {
    margin-top: auto;
    padding: 8px 10px 10px;
    border-top: 1px solid var(--el-border-color-lighter);
  }
}
</style>
