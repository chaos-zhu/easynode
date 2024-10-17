<template>
  <div class="setting_container">
    <el-tabs tab-position="top">
      <el-tab-pane label="修改密码" lazy>
        <User />
      </el-tab-pane>
      <el-tab-pane label="登录日志">
        <Record />
      </el-tab-pane>
      <el-tab-pane label="全局通知" lazy>
        <GlobalNotify />
      </el-tab-pane>
      <el-tab-pane label="通知配置" lazy>
        <NotifyConfig />
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script setup>
import GlobalNotify from './components/global-notify.vue'
// import EmailList from './components/email-list.vue'
import Record from './components/record.vue'
import User from './components/user.vue'
import NotifyConfig from './components/notify-config.vue'

</script>

<style lang="scss" scoped>
.setting_container {
  padding: 20px;
}
</style>
