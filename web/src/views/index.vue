<template>
  <div class="view_container">
    <AsideBox />
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
import { ref, onBeforeMount, getCurrentInstance } from 'vue'
import AsideBox from '@/components/aside-box.vue'
import TopBar from '@/components/top-bar.vue'

const { proxy: { $store, $route } } = getCurrentInstance()
const loading = ref(true)

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
  .main_container {
    flex: 1;
    height: 100%;
    overflow: auto;
    .router_box {
      height: calc(100% - 60px - 20px);
      background-color: #fff;
      border-radius: 6px;
      margin: 10px;
    }
  }
}
</style>
