<template>
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> 登录白名单IP设置: </span>
      <el-tooltip placement="top">
        <template #content>
          <div class="ip_tips">
            IP地址为包含匹配, 如输入: 192.168则匹配IP地址包含192.168的所有IP
          </div>
        </template>
        <el-icon >
          <InfoFilled />
        </el-icon>
      </el-tooltip>
      <el-input-tag v-model="allowedIPs" tag-type="success" tag-effect="plain">
      </el-input-tag>
      <el-button style="margin-top: 6px;" type="success" :loading="btnLoading"
        @click="handleSaveAllowedIPs">保存</el-button>
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
import { InfoFilled } from '@element-plus/icons-vue'

const { proxy: { $api, $tools, $message } } = getCurrentInstance()

const loginRecordList = ref([])
const loading = ref(false)
const btnLoading = ref(false)
const total = ref('')
const allowedIPs = ref([])

const handleLookupLoginRecord = () => {
  loading.value = true
  $api.getLoginRecord()
    .then(({ data }) => {
      const { list, ipWhiteList } = data
      total.value = list.length
      allowedIPs.value = ipWhiteList || []
      loginRecordList.value = list.map((item) => {
        item.date = $tools.formatTimestamp(item.date)
        return item
      })
    })
    .finally(() => {
      loading.value = false
    })
}

const handleSaveAllowedIPs = async () => {
  btnLoading.value = true
  const ipWhiteList = [...new Set(allowedIPs.value)].filter(item => item)
  try {
    await $api.saveIpWhiteList({ ipWhiteList })
    handleLookupLoginRecord()
    $message.success('success')
  } finally {
    btnLoading.value = false
  }
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
