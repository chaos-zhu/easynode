<template>
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> Tips: 系统只保存最近10条登录记录, 检测到更换IP后需重新登录 </span>
    </template>
  </el-alert>
  <el-table v-loading="loading" :data="loginRecordList">
    <el-table-column prop="ip" label="IP" />
    <el-table-column prop="address" label="地点" show-overflow-tooltip>
      <template #default="scope">
        <span style="letter-spacing: 2px;"> {{ scope.row.country }} {{ scope.row.city }} </span>
      </template>
    </el-table-column>
    <el-table-column prop="date" label="时间" />
  </el-table>
</template>

<script>
export default {
  name: 'LoginRecord',
  data() {
    return {
      loginRecordList: [],
      loading: false
    }
  },
  created() {
    this.handleLookupLoginRecord()
  },
  methods: {
    handleLookupLoginRecord() {
      this.loading = true
      this.$api.getLoginRecord()
        .then(({ data }) => {
          this.loginRecordList = data.map((item) => {
            item.date = this.$tools.formatTimestamp(item.date)
            return item
          })
        })
        .finally(() => {
          this.loading = false
        })
    }
  }
}
</script>

<style lang="scss" scoped>

</style>
