<template>
  <div class="view_container">
    <AsideBox
      :discount="discount"
      :is-new="versionUpdate.isNew.value"
      @open-version="versionUpdate.visible.value = true"
    />

    <button
      class="mobile_nav_button"
      type="button"
      aria-label="打开主菜单"
      @click="mobileMenuVisible = true"
    >
      <el-icon><Menu /></el-icon>
    </button>

    <el-drawer
      v-model="mobileMenuVisible"
      :with-header="false"
      direction="ltr"
      class="mobile_menu_drawer global_mobile_menu"
    >
      <div class="mobile_menu_content">
        <div class="mobile_logo_wrap">
          <img src="/logo_v2_01.png" alt="logo">
          <h1>EasyNode</h1>
        </div>
        <MenuList force-expanded @select="mobileMenuVisible = false" />
        <div class="mobile_account">
          <AccountMenu
            :discount="discount"
            :is-new="versionUpdate.isNew.value"
            placement="top-start"
            :show-collapse="false"
            @open-version="openMobileVersionDialog"
          />
        </div>
      </div>
    </el-drawer>

    <main class="main_container">
      <router-view
        v-slot="{ Component }"
        :key="$route.fullPath"
        v-loading="loading"
        class="router_box"
      >
        <keep-alive>
          <component :is="Component" />
        </keep-alive>
      </router-view>
    </main>

    <AiEntry />
    <VersionUpdateDialog
      v-model="versionUpdate.visible.value"
      :current-version="versionUpdate.currentVersion.value"
      :latest-version="versionUpdate.latestVersion.value"
      :features="versionUpdate.features.value"
      :is-new="versionUpdate.isNew.value"
      :check-version-err="versionUpdate.checkVersionErr.value"
    />
  </div>
</template>

<script setup>
import { getCurrentInstance, onBeforeMount, onMounted, ref } from 'vue'
import { Menu } from '@element-plus/icons-vue'
import AsideBox from '@/components/aside-box.vue'
import MenuList from '@/components/menuList.vue'
import AccountMenu from '@/components/account-menu.vue'
import AiEntry from '@/components/ai-entry.vue'
import VersionUpdateDialog from '@/components/version-update-dialog.vue'
import useVersionUpdate from '@/composables/useVersionUpdate'

const { proxy: { $store, $route, $api } } = getCurrentInstance()
const loading = ref(true)
const mobileMenuVisible = ref(false)
const discount = ref(false)
const versionUpdate = useVersionUpdate()

async function getMainData() {
  try {
    loading.value = true
    await $store.getMainData()
  } finally {
    loading.value = false
  }
}

async function getPlusDiscount() {
  try {
    const { data } = await $api.getPlusDiscount()
    discount.value = data?.discount || false
  } catch (error) {
    console.warn('获取 Plus 优惠信息失败:', error.message)
  }
}

function openMobileVersionDialog() {
  mobileMenuVisible.value = false
  versionUpdate.visible.value = true
}

onBeforeMount(getMainData)

onMounted(() => {
  localStorage.removeItem('menuPosition')
  versionUpdate.checkLatestVersion()
  getPlusDiscount()
})
</script>

<style lang="scss" scoped>
.view_container {
  height: 100vh;
  display: flex;
  overflow: hidden;

  .main_container {
    min-width: 0;
    min-height: 0;
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .router_box {
    min-height: 0;
    flex: 1;
    margin: 10px;
    overflow-y: auto;
    border-radius: 6px;
    background-color: #fff;
  }
}

.mobile_nav_button {
  display: none;
}

.mobile_menu_content {
  min-height: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;

  :deep(.el-menu) {
    width: 100%;
    min-height: 0;
    flex: 1;
    overflow-y: auto;
    border-right: none;
  }

  .mobile_account {
    width: 100%;
    flex-shrink: 0;
    padding: 10px 10px calc(10px + env(safe-area-inset-bottom));
    border-top: 1px solid var(--el-border-color-lighter);
  }
}

@media screen and (max-width: 968px) {
  .mobile_nav_button {
    position: fixed;
    z-index: 1800;
    top: 14px;
    left: 14px;
    width: 42px;
    height: 42px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 1px solid var(--el-border-color);
    border-radius: 12px;
    background-color: var(--el-bg-color);
    box-shadow: var(--el-box-shadow-light);
    color: var(--el-text-color-primary);
    font-size: 20px;
    cursor: pointer;
  }
}
</style>

<style lang="scss">
@media screen and (max-width: 968px) {
  .mobile_menu_drawer.global_mobile_menu {
    width: min(220px, 82vw) !important;

    .el-drawer__body {
      height: 100%;
      display: flex;
      flex-direction: column;
      padding: 0;
      overflow: hidden;
    }

    .mobile_logo_wrap {
      flex-shrink: 0;
      justify-content: flex-start;
      padding: 0 20px;
    }
  }
}
</style>
