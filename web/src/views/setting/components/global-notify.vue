<template>
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> 请确保[通知配置]中的通知方式能够正常收到测试通知 </span>
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

<script setup>
import { ref, onMounted } from 'vue'
import { getCurrentInstance } from 'vue'

const { proxy: { $api } } = getCurrentInstance()

const notifyListLoading = ref(false)
const notifyList = ref([])

const getNotifyList = (flag = true) => {
  if (flag) notifyListLoading.value = true
  $api.getNotifyList()
    .then(({ data }) => {
      notifyList.value = data.map((item) => {
        item.loading = false
        return item
      })
    })
    .finally(() => notifyListLoading.value = false)
}

const handleChangeSw = async (row) => {
  row.loading = true
  const { type, sw } = row
  try {
    await $api.updateNotifyList({ type, sw })
    // if (this.userEmailList.length === 0) $message.warning('未配置邮箱, 此开关将不会生效')
  } finally {
    row.loading = false
  }
  getNotifyList(false)
}

onMounted(() => {
  getNotifyList()
})
</script>

<style lang="scss" scoped>

</style>
