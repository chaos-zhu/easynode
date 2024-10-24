<template>
  <el-config-provider :locale="locale">
    <router-view />
  </el-config-provider>
</template>

<script setup>
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import { ref, getCurrentInstance } from 'vue'
const { proxy: { $store } } = getCurrentInstance()

const locale = ref(zhCn)
$store.setDefaultTheme()
</script>

<style lang="scss" scoped>

</style>
