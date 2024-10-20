<template>
  <el-alert v-if="allowedIPs" type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> 登录白名单IP: </span>
      <el-tag
        v-for="(item, index) in allowedIPs"
        :key="index"
        class="allowed_ip_tag"
        type="warning"
      >
        {{ item }}
      </el-tag>
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
const total = ref('')
const allowedIPs = ref('')

const handleLookupLoginRecord = () => {
  loading.value = true
  $api.getLoginRecord()
    .then(({ data }) => {
      const { list, whiteList } = data
      total.value = list.length
      allowedIPs.value = whiteList || []
      loginRecordList.value = list.map((item) => {
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
.allowed_ip_tag {
  margin: 0 5px;
}
</style>
