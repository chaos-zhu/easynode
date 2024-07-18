<template>
  <div class="view_container">
    <AsideBox />
    <div class="main_container">
      <TopBar />
      <router-view v-slot="{ Component }" class="router_box">
        <keep-alive>
          <component :is="Component" />
        </keep-alive>
      </router-view>
    </div>
  </div>
</template>

<script setup>
import AsideBox from '@/components/aside-box.vue'
import TopBar from '@/components/top-bar.vue'
</script>

<style lang="scss" scoped>
.view_container {
  display: flex;
  height: 100vh;
  .main_container {
    flex: 1;
    height: 100vh;
    overflow: auto;
    .router_box {
      min-height: calc(100vh - 60px - 20px);
      background-color: #fff;
      margin: 10px;
    }
  }
}
</style>
