<template>
  <div class="setting_container">
    <el-tabs v-model="tabKey" tab-position="top">
      <el-tab-pane :label="t('settings.changePassword')" name="user">
        <User />
      </el-tab-pane>
      <el-tab-pane :label="t('settings.loginManagement')" name="session" lazy>
        <Session />
      </el-tab-pane>
      <el-tab-pane :label="t('settings.notificationConfig')" name="notify">
        <Notify />
      </el-tab-pane>
      <el-tab-pane :label="t('settings.proxyService')" name="proxy">
        <Proxy />
      </el-tab-pane>
      <el-tab-pane :label="t('settings.plusActivation')" name="plus">
        <UserPlus />
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script setup>
import { watch, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import Session from './components/session.vue'
import User from './components/user.vue'
import Notify from './components/notify.vue'
import UserPlus from './components/user-plus.vue'
import Proxy from './components/proxy.vue'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()

const tabKey = computed({
  get() {
    return route.query.tabKey || 'user'
  },
  set(newVal) {
    router.push({ query: { tabKey: newVal } })
  }
})

watch(() => tabKey.value, (newVal) => {
  router.push({ query: { tabKey: newVal } })
})

</script>

<style lang="scss" scoped>
.setting_container {
  height: 100%;
  padding: 20px;
  overflow: auto;
}
</style>
