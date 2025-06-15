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
        placeholder=""
        autocomplete="off"
        class="input"
        @keyup.enter.prevent="handleUpdate"
      />
    </el-form-item>
    <el-form-item>
      <div class="form_footer">
        <el-button type="success" :loading="loading" @click="handleUpdate">立即激活</el-button>
        <el-button type="primary" @click="handlePlusSupport">
          获取 Plus Key
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
  <!-- Plus 激活状态信息 -->
  <div v-if="isPlusActive" class="plus_status">
    <div class="status_header">
      <span>Plus专属功能已激活</span>
    </div>
    <div class="status_info">
      <div class="info_item">
        <span class="label">到期时间:</span>
        <span class="value holder">{{ plusInfo.expiryDate }}</span>
      </div>
      <div class="info_item">
        <span class="label">授权IP数:</span>
        <span class="value">{{ plusInfo.maxIPs }}</span>
      </div>
      <div class="info_item">
        <span class="label">已授权IP数:</span>
        <span class="value">{{ plusInfo.usedIPCount }}</span>
      </div>
      <div class="info_item ip_list">
        <span class="label">已授权IP:</span>
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
            查看所有({{ totalIPCount }})
          </el-button>
          <el-button
            type="success"
            size="small"
            link
            :loading="whitelistLoading"
            @click="handleSetToWhitelist"
          >
            [追加所有IP到登录白名单]
          </el-button>
        </div>
      </div>
    </div>
  </div>
  <PlusTable />

  <el-dialog
    v-model="showAllIPsDialog"
    title="所有已授权IP"
    width="600px"
    :before-close="() => showAllIPsDialog = false"
  >
    <div class="all_ips_container">
      <div class="ip_count_info">
        共 {{ totalIPCount }} 个已授权IP
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
      <el-button @click="showAllIPsDialog = false">关闭</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance, computed } from 'vue'
import { ElMessageBox } from 'element-plus'
import { TopRight } from '@element-plus/icons-vue'
import { handlePlusSupport } from '@/utils'
import PlusTable from '@/components/plus-table.vue'
import { useRouter } from 'vue-router'

const { proxy: { $api, $message, $store } } = getCurrentInstance()
const router = useRouter()

const errCount = ref(Number(localStorage.getItem('plusErrCount') || 0))
const loading = ref(false)
const formRef = ref(null)
const showAllIPsDialog = ref(false)
const whitelistLoading = ref(false)
const formData = reactive({
  key: ''
})
const rules = reactive({
  key: { required: true, message: '输入Plus Key', trigger: 'change' }
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
          $message({ type: 'warning', center: true, message: '请输入正确的Plus Key' })
          return
        }
        await $api.updatePlusKey({ key })
        $message({ type: 'success', center: true, message: '激活成功，感谢支持' })
        localStorage.setItem('plusErrCount', 0)
      } catch (error) {
        localStorage.setItem('plusErrCount', ++errCount.value)
        if (errCount.value > 3) {
          ElMessageBox.confirm(
            '激活失败，请确认key正确，有疑问请tg联系作者@chaoszhu',
            'Warning',
            {
              showCancelButton : false,
              confirmButtonText: '确认',
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
      `确定要将 ${ allAuthorizedIPs.length } 个PLUS授权IP追加到登录白名单吗？<br/><span style="color: #ff4806;">注意！</span>设置后非白名单IP将无法访问面板`,
      '确认操作',
      {
        confirmButtonText: '确认追加',
        cancelButtonText: '取消',
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
      message: `成功将 ${ allAuthorizedIPs.length } 个IP添加到登录白名单`
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
      message: error.message || '设置白名单失败'
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

