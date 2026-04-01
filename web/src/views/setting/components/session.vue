<template>
  <el-alert type="success" :closable="false">
    <template #title>
      <span style="letter-spacing: 2px;"> {{ t('settings.session.ipWhitelistTitle') }} </span>
      <el-tooltip placement="top">
        <template #content>
          <div class="ip_tips">
            {{ t('settings.session.ipWhitelistTip') }}
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
        {{ t('common.save') }}
      </el-button>
    </template>
  </el-alert>

  <el-table v-loading="loading" :data="loginRecordList">
    <el-table-column prop="ip" label="IP" />
    <el-table-column
      prop="address"
      :label="t('settings.session.location')"
      min-width="126"
      show-overflow-tooltip
    >
      <template #default="scope">
        <span style="letter-spacing: 2px;"> {{ scope.row.country }} {{ scope.row.city }} </span>
      </template>
    </el-table-column>
    <el-table-column
      prop="agentInfo"
      :label="t('settings.session.deviceInfo')"
      min-width="126"
      show-overflow-tooltip
    >
      <template #default="scope">
        <div style="letter-spacing: 2px;"> {{ scope.row.os }} </div>
        <div style="letter-spacing: 2px;"> {{ scope.row.browser }} </div>
        <el-tag
          v-if="scope.row.deviceId === deviceId"
          type="success"
          size="small"
        >
          {{ t('settings.session.currentDevice') }}
        </el-tag>
      </template>
    </el-table-column>
    <el-table-column prop="create" :label="t('settings.session.loginTime')" min-width="126" />
    <el-table-column prop="expireAt" :label="t('settings.session.expireTime')" min-width="126">
      <template #default="{ row }">
        {{ row.expireAt }}
      </template>
    </el-table-column>
    <el-table-column :label="t('common.status')">
      <template #default="{ row }">
        <el-tag v-if="row.isExpired" type="info" size="small">{{ t('settings.session.expired') }}</el-tag>
        <el-tag v-else-if="row.revoked" type="warning" size="small">{{ t('settings.session.revoked') }}</el-tag>
        <el-tag v-else type="success" size="small">{{ t('settings.session.normal') }}</el-tag>
      </template>
    </el-table-column>
    <el-table-column :label="t('settings.session.actions')" width="200">
      <template #header>
        <el-button
          type="info"
          size="small"
          :loading="removeLogLoading"
          @click="handleRemoveLogs"
        >
          {{ t('settings.session.removeOldLogs') }}
        </el-button>
      </template>
      <template #default="{ row }">
        <el-button
          v-if="!row.isExpired && !row.revoked"
          type="warning"
          size="small"
          :loading="removeSidLoading"
          @click="handleRemoveSid(row.id)"
        >
          {{ t('settings.session.revoke') }}
        </el-button>
      </template>
    </el-table-column>
  </el-table>
</template>

<script setup>
import { ref, onMounted, getCurrentInstance, watch, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { InfoFilled } from '@element-plus/icons-vue'
import { useRoute } from 'vue-router'
import dayjs from 'dayjs'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()
const route = useRoute()
const { t } = useI18n()

const loginRecordList = ref([])
const loading = ref(false)
const btnLoading = ref(false)
const removeLogLoading = ref(false)
const removeSidLoading = ref(false)
const total = ref('')
const allowedIPs = ref([])
const deviceId = computed(() => $store.deviceId)

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
      allowedIPs.value = ipWhiteList?.filter(ip => Boolean(ip)) || []
      loginRecordList.value = list.map((item) => {
        item.create = dayjs(item.create).format('YYYY-MM-DD HH:mm:ss')
        item.expireAt = dayjs(item.expireAt).format('YYYY-MM-DD HH:mm:ss')
        item.isExpired = dayjs().isAfter(dayjs(item.expireAt))
        const { agentInfo: { os, browser } } = item
        item.browser = browser ? (browser.name + browser.version) : '--'
        item.os = os ? (os.name + os.version) : '--'
        return item
      })
    })
    .finally(() => {
      loading.value = false
    })
}

const handleSaveAllowedIPs = async () => {
  btnLoading.value = true
  const ipWhiteList = [...new Set(allowedIPs.value),].filter(item => /[\d\.]/.test(item))
  try {
    await $api.saveIpWhiteList({ ipWhiteList })
    handleLookupLoginRecord()
    $message.success(t('common.save'))
  } finally {
    btnLoading.value = false
  }
}

const handleRemoveLogs = async () => {
  $messageBox.confirm(t('settings.session.confirmRemoveOldLogs'), t('settings.common.tip'), {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
    type: 'warning'
  })
    .then(async () => {
      removeLogLoading.value = true
      try {
        const { msg } = await $api.removeSomeLoginRecords()
        handleLookupLoginRecord()
        $message.success(msg)
      } catch (error) {
        console.error(error)
        $message.error(t('settings.session.removeOldLogsFailed'))
      } finally {
        removeLogLoading.value = false
      }
    })
}

const handleRemoveSid = async (id) => {
  $messageBox.confirm(t('settings.session.confirmRevokeCredential'), t('settings.common.tip'), {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
    type: 'warning'
  })
    .then(async () => {
      removeSidLoading.value = true
      try {
        const { msg } = await $api.revokeLoginSid(id)
        handleLookupLoginRecord()
        $message.success(msg)
      } finally {
        removeSidLoading.value = false
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

