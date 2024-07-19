<template>
  <div class="terminal_container">
    <div v-if="showLinkTips" class="terminal_link_tips">
      <h2 class="quick_link_text">快速连接</h2>
      <el-table
        :data="hostList"
        :show-header="false"
      >
        <el-table-column prop="name" label="name" width="180" />
        <el-table-column prop="host" label="host" width="180" />
        <el-table-column prop="address" label="Address" />
      </el-table>
      <!-- <ul v-for="item in hostList" :key="item._id">
        {{ item.name }}
        {{ item.host }}
        {{ item.name }}
      </ul> -->
    </div>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'

const { proxy: { $store } } = getCurrentInstance()

let showLinkTips = ref(true)

let hostList = computed(() => $store.hostList)

</script>

<style lang="scss" scoped>
.terminal_container {
  .terminal_link_tips {
    width: 50%;
    // margin: 0 auto;
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    padding: 20px;
    .quick_link_text {
      align-self: self-start;
      margin: 0 10px;
      font-size: 14px;
      font-weight: 600;
      line-height: 22px;
      margin-bottom: 15px;
    }
  }
}
</style>
