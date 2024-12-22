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
        <el-button type="primary" :loading="loading" @click="handleUpdate">立即激活</el-button>
        <el-button type="success" @click="handlePlusSupport">
          购买Plus
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
            v-for="ip in plusInfo.usedIPs"
            :key="ip"
            size="small"
            class="ip_tag"
          >
            {{ ip }}
          </el-tag>
        </div>
      </div>
    </div>
  </div>
  <PlusTable />
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance, computed } from 'vue'
import { ElMessageBox } from 'element-plus'
import { TopRight } from '@element-plus/icons-vue'
import { handlePlusSupport } from '@/utils'
import PlusTable from '@/components/plus-table.vue'

const { proxy: { $api, $message, $store } } = getCurrentInstance()

const errCount = ref(Number(localStorage.getItem('plusErrCount') || 0))
const loading = ref(false)
const formRef = ref(null)
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

const handleUpdate = () => {
  formRef.value.validate()
    .then(async () => {
      try {
        loading.value = true
        let { key } = formData
        await $api.updatePlusKey({ key })
        $message({ type: 'success', center: true, message: '激活成功，感谢支持' })
        localStorage.setItem('plusErrCount', 0)
      } catch (error) {
        localStorage.setItem('plusErrCount', ++errCount.value)
        if (errCount.value > 3) {
          ElMessageBox.confirm(
            '激活失败，请确认key正确(20位不规则字符串)，有疑问请tg联系@chaoszhu。',
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
        }
      }
    }
  }
}
</style>

