<template>
  <el-form
    ref="formRef"
    class="plus-form"
    :model="formData"
    :rules="rules"
    :hide-required-asterisk="true"
    label-suffix="："
    label-width="86px"
    :show-message="false"
    @submit.prevent
  >
    <el-form-item label="Plus Key" prop="key" class="form_item">
      <el-input
        v-model.trim="formData.key"
        clearable
        :placeholder="t('settings.plus.plusKey')"
        autocomplete="off"
        class="input"
        @keyup.enter.prevent="handleUpdate"
      />
    </el-form-item>
    <el-form-item>
      <div class="form_footer">
        <el-button type="success" :loading="loading" @click="handleUpdate">{{ t('settings.plus.activateNow') }}</el-button>
        <el-button type="primary" @click="handlePlusSupport">
          {{ t('settings.plus.getPlusKey') }}
          <el-icon class="el-icon--right"><TopRight /></el-icon>
        </el-button>
        <span v-if="!isPlusActive && discount" class="discount_wrapper" @click="handlePlusSupport">
          <img
            class="discount_badge"
            src="@/assets/discount.png"
            alt="Discount"
          >
          <span class="discount_content">{{ discountContent }}</span>
        </span>
      </div>
    </el-form-item>
  </el-form>
  <div v-if="isPlusActive" class="plus_status">
    <div class="status_header">
      <span>{{ t('settings.plus.activated') }}</span>
    </div>
    <div class="status_info">
      <div class="info_item">
        <span class="label">{{ t('settings.plus.expiryDate') }}</span>
        <span class="value holder">{{ plusInfo.expiryDate }}</span>
      </div>
      <div class="info_item">
        <span class="label">{{ t('settings.plus.maxAuthorizedIps') }}</span>
        <span class="value">{{ plusInfo.maxIPs }}</span>
      </div>
      <div class="info_item">
        <span class="label">{{ t('settings.plus.usedAuthorizedIps') }}</span>
        <span class="value">{{ plusInfo.usedIPCount }}</span>
      </div>
      <div class="info_item ip_list">
        <span class="label">{{ t('settings.plus.authorizedIps') }}</span>
        <div class="ip_tags">
          <el-tag
            v-for="ip in displayedIPs"
            :key="ip"
            size="small"
            class="ip_tag"
          >
            {{ ip }}
          </el-tag>
          <el-button
            v-if="hasMoreIPs"
            type="primary"
            link
            size="small"
            class="view_all_btn"
            @click="showAllIPsDialog = true"
          >
            {{ t('settings.plus.viewAll', { count: totalIPCount }) }}
          </el-button>
          <el-button
            type="success"
            size="small"
            link
            :loading="whitelistLoading"
            @click="handleSetToWhitelist"
          >
            {{ t('settings.plus.appendAllToWhitelist') }}
          </el-button>
        </div>
      </div>
    </div>
  </div>
  <PlusTable />

  <el-dialog
    v-model="showAllIPsDialog"
    :title="t('settings.plus.allAuthorizedIps')"
    width="600px"
    :before-close="() => showAllIPsDialog = false"
  >
    <div class="all_ips_container">
      <div class="ip_count_info">
        {{ t('settings.plus.totalAuthorizedIps', { count: totalIPCount }) }}
      </div>
      <div class="all_ip_tags">
        <el-tag
          v-for="ip in plusInfo.usedIPs"
          :key="ip"
          size="small"
          class="ip_tag"
        >
          {{ ip }}
        </el-tag>
      </div>
    </div>
    <template #footer>
      <el-button @click="showAllIPsDialog = false">{{ t('common.close') }}</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessageBox } from 'element-plus'
import { TopRight } from '@element-plus/icons-vue'
import { handlePlusSupport } from '@/utils'
import PlusTable from '@/components/plus-table.vue'
import { useRouter } from 'vue-router'

const { proxy: { $api, $message, $store } } = getCurrentInstance()
const router = useRouter()
const { t } = useI18n()

const errCount = ref(Number(localStorage.getItem('plusErrCount') || 0))
const loading = ref(false)
const formRef = ref(null)
const showAllIPsDialog = ref(false)
const whitelistLoading = ref(false)
const formData = reactive({
  key: ''
})
const rules = reactive({
  key: { required: true, message: t('settings.plus.validation.enterPlusKey'), trigger: 'change' }
})
const discount = ref(false)
const discountContent = ref('')

const plusInfo = computed(() => $store.plusInfo)
const isPlusActive = computed(() => $store.isPlusActive)

const displayedIPs = computed(() => {
  const ips = plusInfo.value?.usedIPs || []
  return ips.slice(0, 5)
})

const hasMoreIPs = computed(() => {
  const ips = plusInfo.value?.usedIPs || []
  return ips.length > 5
})

const totalIPCount = computed(() => {
  return plusInfo.value?.usedIPs?.length || 0
})

const handleUpdate = () => {
  formRef.value.validate()
    .then(async () => {
      try {
        loading.value = true
        let { key } = formData
        if (key.length < 15) {
          $message({ type: 'warning', center: true, message: t('settings.plus.invalidPlusKey') })
          return
        }
        await $api.updatePlusKey({ key })
        $message({ type: 'success', center: true, message: t('settings.plus.activateSuccess') })
        localStorage.setItem('plusErrCount', 0)
      } catch (error) {
        localStorage.setItem('plusErrCount', ++errCount.value)
        if (errCount.value > 3) {
          ElMessageBox.confirm(
            t('settings.plus.activateFailedHelp'),
            'Warning',
            {
              showCancelButton : false,
              confirmButtonText: t('common.confirm'),
              type: 'warning'
            }
          )
        }
      }
    })
    .finally(() => {
      loading.value = false
      $store.getPlusInfo()
    })
}

const getPlusConf = async () => {
  try {
    loading.value = true
    let { data } = await $api.getPlusConf()
    formData.key = data
  } catch (error) {
    $message({ type: 'error', center: true, message: error.message })
  } finally {
    loading.value = false
  }
}

const getPlusDiscount = async () => {
  const { data } = await $api.getPlusDiscount()
  if (data?.discount) {
    discount.value = data.discount
    discountContent.value = data.content
  }
}

const handleSetToWhitelist = async () => {
  try {
    const allAuthorizedIPs = plusInfo.value?.usedIPs || []
    await ElMessageBox.confirm(
      t('settings.plus.appendWhitelistConfirm', { count: allAuthorizedIPs.length }),
      t('settings.plus.confirmAction'),
      {
        confirmButtonText: t('settings.plus.confirmAppend'),
        cancelButtonText: t('common.cancel'),
        type: 'warning',
        dangerouslyUseHTMLString: true
      }
    )

    whitelistLoading.value = true
    const { data: recordData } = await $api.getLoginRecord()
    const currentWhiteList = recordData.ipWhiteList || []
    const mergedIPs = [...new Set([...currentWhiteList, ...allAuthorizedIPs,]),]
    await $api.saveIpWhiteList({ ipWhiteList: mergedIPs })
    $message({
      type: 'success',
      center: true,
      message: t('settings.plus.appendWhitelistSuccess', { count: allAuthorizedIPs.length })
    })

    setTimeout(() => {
      router.push({
        path: '/setting',
        query: {
          tabKey: 'record',
          refresh: Date.now()
        }
      })
    }, 1000)

  } catch (error) {
    if (error === 'cancel') return
    $message({
      type: 'error',
      center: true,
      message: error.message || t('settings.plus.appendWhitelistFailed')
    })
  } finally {
    whitelistLoading.value = false
  }
}

onMounted(() => {
  getPlusConf()
  getPlusDiscount()
})
</script>

<style lang="scss" scoped>
.form_item {
  .input {
    width: 450px;
  }
}

.form_footer {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: start;
  margin-bottom: 15px;
  .discount_wrapper {
    height: 100%;
    display: flex;
    align-items: center;
    cursor: pointer;
    .discount_badge {
      margin: 0 5px 0 10px;
      width: 22px;
      color: white;
      font-size: 12px;
    }
    .discount_content {
      font-size: 12px;
      line-height: 1.3;
      color: #ff4806;
      text-decoration: underline;
    }
  }
}

.plus_status {
  margin-bottom: 15px;

  .status_header {
    display: flex;
    align-items: center;
    color: #67c23a;
    margin-bottom: 10px;

    .el-icon {
      margin-right: 5px;
    }
  }

  .status_info {
    .info_item {
      display: flex;
      margin: 5px 0;
      font-size: 13px;

      .label {
        color: #909399;
        width: 80px;
      }

      .holder {
        color: #EED183;
      }

      &.ip_list {
        flex-direction: column;

        .ip_tags {
          margin-top: 5px;

          .ip_tag {
            margin: 2px;
          }

          .view_all_btn {
            margin-left: 8px;
            padding: 2px 4px;
            font-size: 12px;
            height: auto;
          }
        }

        .ip_actions {
          margin-top: 10px;

          .el-button {
            font-size: 12px;
          }
        }
      }
    }
  }
}

.all_ips_container {
  .ip_count_info {
    margin-bottom: 15px;
    color: #606266;
    font-size: 14px;
    font-weight: 500;
  }

  .all_ip_tags {
    max-height: 400px;
    overflow-y: auto;

    .ip_tag {
      margin: 4px;
    }
  }
}
</style>


