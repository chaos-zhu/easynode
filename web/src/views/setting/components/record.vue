<template>
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> 系统只保存最近10条登录记录, 目前版本只保存在内存中, 重启面板服务后会丢失 </span>
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

<script setup>
import { ref, onMounted, getCurrentInstance } from 'vue'

const { proxy: { $api, $tools } } = getCurrentInstance()

const loginRecordList = ref([])
const loading = ref(false)

const handleLookupLoginRecord = () => {
  loading.value = true
  $api.getLoginRecord()
    .then(({ data }) => {
      loginRecordList.value = data.map((item) => {
        item.date = $tools.formatTimestamp(item.date)
        return item
      })
    })
    .finally(() => {
      loading.value = false
    })
}

onMounted(() => {
  handleLookupLoginRecord()
})
</script>

<style lang="scss" scoped>
</style>
