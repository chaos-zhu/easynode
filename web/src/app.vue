<template>
  <el-config-provider :locale="locale">
    <router-view />
  </el-config-provider>
</template>

<script setup>
import { ref, getCurrentInstance } from 'vue'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
const { proxy: { $store } } = getCurrentInstance()

const locale = ref(zhCn)
$store.setDefaultTheme()
</script>

<style lang="scss" scoped>

</style>
