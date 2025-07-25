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
        <el-icon>
          <InfoFilled />
        </el-icon>
      </el-tooltip>
      <el-input-tag v-model="allowedIPs" tag-type="success" tag-effect="plain" />
      <el-button
        style="margin-top: 6px;"
        type="success"
        :loading="btnLoading"
        @click="handleSaveAllowedIPs"
      >
        保存
      </el-button>
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
    <el-table-column label="操作" width="200">
      <template #header>
        <el-button
          type="danger"
          size="small"
          :loading="removeLoading"
          @click="handleRemoveLogs"
        >
          移除一周前的登录日志
        </el-button>
      </template>
    </el-table-column>
  </el-table>
</template>

<script setup>
import { ref, onMounted, getCurrentInstance, watch } from 'vue'
import { InfoFilled } from '@element-plus/icons-vue'
import { useRoute } from 'vue-router'

const { proxy: { $api, $tools, $message, $messageBox } } = getCurrentInstance()
const route = useRoute()

const loginRecordList = ref([])
const loading = ref(false)
const btnLoading = ref(false)
const removeLoading = ref(false)
const total = ref('')
const allowedIPs = ref([])

watch(() => route.query.refresh, (newVal) => {
  if (newVal) {
    handleLookupLoginRecord()
  }
})

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
  const ipWhiteList = [...new Set(allowedIPs.value),].filter(item => item)
  try {
    await $api.saveIpWhiteList({ ipWhiteList })
    handleLookupLoginRecord()
    $message.success('success')
  } finally {
    btnLoading.value = false
  }
}

const handleRemoveLogs = async () => {
  $messageBox.confirm('确定要移除一周前的登录日志吗？', '提示', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  })
    .then(async () => {
      removeLoading.value = true
      try {
        const { msg } = await $api.removeSomeLoginRecords()
        handleLookupLoginRecord()
        $message.success(msg)
      } catch (error) {
        console.error(error)
        $message.error('移除一周前的登录日志失败')
      } finally {
        removeLoading.value = false
      }
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
