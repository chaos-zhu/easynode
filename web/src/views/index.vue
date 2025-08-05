<template>
  <div class="view_container" :class="{ 'top_menu': menuPosition === 'top' }">
    <AsideBox v-if="menuPosition === 'left'" />
    <div class="main_container">
      <TopBar />
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
    </div>
  </div>
</template>

<script setup>
import { ref, onBeforeMount, getCurrentInstance, computed } from 'vue'
import AsideBox from '@/components/aside-box.vue'
import TopBar from '@/components/top-bar.vue'

const { proxy: { $store, $route } } = getCurrentInstance()
const loading = ref(true)
const menuPosition = computed(() => $store.menuPosition)

const getMainData = async () => {
  try {
    loading.value = true
    await $store.getMainData()
  } finally {
    loading.value = false
  }
}

onBeforeMount(async () => {
  await getMainData()
})

</script>

<style lang="scss" scoped>
.view_container {
  display: flex;
  height: 100vh;

  &.top_menu {
    flex-direction: column;

    .main_container {
      flex: 1;
      width: 100%;
    }
  }

  .main_container {
    flex: 1;
    height: 100%;
    overflow: auto;
    .router_box {
      height: calc(100% - 60px - 20px);
      overflow-y: auto;
      background-color: #fff;
      border-radius: 6px;
      margin: 10px;
    }
  }
}
</style>
