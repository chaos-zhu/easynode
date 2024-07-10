<template>
  <!-- 提示 -->
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> Tips: 请添加邮箱并确保测试邮件通过 </span>
    </template>
  </el-alert>
  <el-table v-loading="notifyListLoading" :data="notifyList">
    <el-table-column prop="desc" label="通知类型" />
    <el-table-column prop="sw" label="开关">
      <template #default="{row}">
        <el-switch
          v-model="row.sw"
          :active-value="true"
          :inactive-value="false"
          :loading="row.loading"
          @change="handleChangeSw(row, $event)"
        />
      </template>
    </el-table-column>
  </el-table>
</template>

<script>
export default {
  name: 'NotifyList',
  data() {
    return {
      notifyListLoading: false,
      notifyList: []
    }
  },
  mounted() {
    this.getNotifyList()
  },
  methods: {
    getNotifyList(flag = true) {
      if(flag) this.notifyListLoading = true
      this.$api.getNotifyList()
        .then(({ data }) => {
          this.notifyList = data.map((item) => {
            item.loading = false
            return item
          })
        })
        .finally(() => this.notifyListLoading = false)
    },
    async handleChangeSw(row) {
      row.loading = true
      const { type, sw } = row
      try {
        await this.$api.updateNotifyList({ type, sw })
        // if(this.userEmailList.length === 0) this.$message.warning('未配置邮箱, 此开关将不会生效')
      } finally {
        row.loading = true
      }
      this.getNotifyList(false)
    }
  }
}
</script>

<style lang="scss" scoped>

</style>
