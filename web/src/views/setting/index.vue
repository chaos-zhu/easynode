<template>
  <div class="setting_container">
    <el-tabs tab-position="top">
      <el-tab-pane label="修改密码" lazy>
        <User />
      </el-tab-pane>
      <!-- <el-tab-pane label="分组管理">
        <Group />
      </el-tab-pane> -->
      <el-tab-pane label="登录日志">
        <Record />
      </el-tab-pane>
      <!-- <el-tab-pane label="实例排序" lazy>
        <Sort @update-list="emitUpdateList" />
      </el-tab-pane> -->
      <el-tab-pane label="全局通知" lazy>
        <NotifyList />
      </el-tab-pane>
      <el-tab-pane label="邮箱配置" lazy>
        <EmailList />
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script setup>
import NotifyList from './components/notify-list.vue'
import EmailList from './components/email-list.vue'
import Record from './components/record.vue'
import User from './components/user.vue'

</script>

<style lang="scss" scoped>
.setting_container {
  padding: 20px;
}
</style>
