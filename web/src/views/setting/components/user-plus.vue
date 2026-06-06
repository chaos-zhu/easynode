<template>
  <el-form
    ref="formRef"
    class="plus_form"
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
        show-password
        type="password"
        placeholder=""
        autocomplete="off"
        class="input"
        @keyup.enter.prevent="handleUpdate"
      />
      <el-button
        type="success"
        :loading="loading"
        style="margin-left: 15px;"
        @click="handleUpdate"
      >
        {{ isPlusActive ? '已激活' : '立即激活' }}
      </el-button>
      <el-button type="primary" @click="handlePlusSupport">
        获取 Plus Key
        <el-icon class="el-icon--right"><TopRight /></el-icon>
      </el-button>
    </el-form-item>
    <el-form-item>
      <div class="form_footer">
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
  </div>
  <div v-else-if="needRestart" class="plus_status is_danger">
    <div class="status_header">
      <span>授权已在其它实例被占用，请重启面板服务后重试</span>
    </div>
  </div>
  <div v-else-if="plusError" class="plus_status is_warning">
    <div class="status_header">
      <span>Plus状态错误：{{ plusError }}</span>
    </div>
  </div>
  <PlusDevices v-if="isPlusActive" />
  <PlusTable />
</template>

<script setup>
import { ref, reactive, onMounted, getCurrentInstance, computed, watch } from 'vue'
import { ElMessageBox } from 'element-plus'
import { TopRight } from '@element-plus/icons-vue'
import { handlePlusSupport } from '@/utils'
import PlusTable from '@/components/plus-table.vue'
import PlusDevices from '@/views/setting/components/plus-devices.vue'

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

const isPlusActive = computed(() => $store.isPlusActive)
const plusInfo = computed(() => $store.plusInfo)
const plusError = computed(() => $store.plusInfo?.error)
const needRestart = computed(() => $store.plusInfo?.needRestart === true)

watch(() => plusInfo.value, (newVal) => {
  formData.key = newVal?.key || ''
}, { immediate: true, deep: true })

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
            '激活失败，请确认key正确并重启服务重试，有疑问请tg联系作者@chaoszhu',
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

const getPlusDiscount = async () => {
  const { data } = await $api.getPlusDiscount()
  if (data?.discount) {
    discount.value = data.discount
    discountContent.value = data.content
  }
}

onMounted(() => {
  getPlusDiscount()
})
</script>

<style lang="scss" scoped>
.plus_form {
  margin-bottom: -15px;
}
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

  &.is_danger .status_header {
    color: #f56c6c;
  }

  &.is_warning .status_header {
    color: #e6a23c;
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

