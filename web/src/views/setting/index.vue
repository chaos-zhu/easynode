<template>
  <div class="setting_container">
    <el-tabs v-model="tabKey" tab-position="top">
      <el-tab-pane label="修改密码" name="user">
        <User />
      </el-tab-pane>
      <el-tab-pane label="登录日志" name="record" lazy>
        <Record />
      </el-tab-pane>
      <el-tab-pane label="全局通知" name="notify">
        <GlobalNotify />
      </el-tab-pane>
      <el-tab-pane label="通知配置" name="notify-config">
        <NotifyConfig />
      </el-tab-pane>
      <el-tab-pane label="Plus激活" name="plus">
        <UserPlus />
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script setup>
import { watch, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import GlobalNotify from './components/global-notify.vue'
import Record from './components/record.vue'
import User from './components/user.vue'
import NotifyConfig from './components/notify-config.vue'
import UserPlus from './components/user-plus.vue'

const route = useRoute()
const router = useRouter()

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
