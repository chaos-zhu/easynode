<template>
  <el-config-provider :locale="elementLocale">
    <router-view />
  </el-config-provider>
</template>

<script setup>
import { computed, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import en from 'element-plus/es/locale/lang/en'

const { proxy: { $store } } = getCurrentInstance()
const { locale } = useI18n()

const elementLocaleMap = {
  'zh-CN': zhCn,
  en
}

const elementLocale = computed(() => elementLocaleMap[locale.value] || zhCn)

$store.setDefaultTheme()
</script>

<style lang="scss" scoped>

</style>
