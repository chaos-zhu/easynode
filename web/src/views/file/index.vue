<template>
  <div class="file_container">
    <div class="file_header">
      <div class="file_header_left">
        <el-button type="primary">上传</el-button>
        <el-button type="primary">下载</el-button>
      </div>
      <div class="file_header_right">
        <el-input v-model="search" placeholder="搜索" />
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'

const search = ref('')
</script>

<style lang="scss" scoped>
.file_container {
  height: 100%;
}
</style>
