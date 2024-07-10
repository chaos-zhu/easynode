<template>
  <el-dialog
    v-model="visible"
    width="1100px"
    :title="'功能设置'"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
  >
    <el-tabs
      style="height: 500px;"
      tab-position="left"
    >
      <el-tab-pane label="分组管理">
        <Group />
      </el-tab-pane>
      <el-tab-pane label="登录记录">
        <Record />
      </el-tab-pane>
      <el-tab-pane label="主机排序" lazy>
        <Sort @update-list="$emit('update-list')" />
      </el-tab-pane>
      <el-tab-pane label="全局通知" lazy>
        <NotifyList />
      </el-tab-pane>
      <el-tab-pane label="邮箱配置" lazy>
        <EmailList />
      </el-tab-pane>
      <el-tab-pane label="修改密码" lazy>
        <Password />
      </el-tab-pane>
    </el-tabs>
  </el-dialog>
</template>

<script>

import NotifyList from './setting-tab/notify-list.vue'
import EmailList from './setting-tab/email-list.vue'
import Sort from './setting-tab/sort.vue'
import Record from './setting-tab/record.vue'
import Group from './setting-tab/group.vue'
import Password from './setting-tab/password.vue'

export default {
  name: 'Setting',
  components: {
    NotifyList,
    EmailList,
    Sort,
    Record,
    Group,
    Password
  },
  props: {
    show: {
      required: true,
      type: Boolean
    }
  },
  emits: ['update:show', 'update-list',],
  data() {
    return {
    }
  },
  computed: {
    visible: {
      get() {
        return this.show
      },
      set(newVal) {
        this.$emit('update:show', newVal)
      }
    }
  }
}
</script>

<style lang="scss" scoped>
.table {
  max-height: 400px;
  overflow: auto;
}
.dialog-footer {
  display: flex;
  justify-content: center;
}
</style>
