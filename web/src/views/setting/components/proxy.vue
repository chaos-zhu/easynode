<template>
  <div class="proxy-container">
    <div class="operation-bar">
      <PlusSupportTip>
        <el-button
          type="primary"
          :icon="Plus"
          :disabled="!isPlusActive"
          @click="handleAdd"
        >
          {{ t('settings.proxy.addProxy') }}
        </el-button>
      </PlusSupportTip>
    </div>

    <el-table
      v-loading="loading"
      :data="proxyList"
      stripe
      style="width: 100%"
      :empty-text="t('settings.proxy.empty')"
    >
      <el-table-column prop="type" :label="t('common.type')">
        <template #default="{ row }">
          <el-tag :type="row.type === 'socks5' ? 'success' : 'primary'">
            {{ row.type === 'socks5' ? 'SOCKS5' : 'HTTP' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="name" :label="t('common.name')" />
      <el-table-column prop="host" :label="t('settings.proxy.host')" />
      <el-table-column prop="port" :label="t('settings.proxy.port')" />
      <el-table-column prop="username" :label="t('settings.proxy.username')">
        <template #default="{ row }">
          <span>{{ row.username || '--' }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="password" :label="t('settings.proxy.password')">
        <template #default="{ row }">
          <span @click="handleShowPassword(row)">{{ row.displayPassword || '--' }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="createTime" :label="t('settings.proxy.createTime')">
        <template #default="{ row }">
          <span>{{ dayjs(row.createTime).format('YYYY-MM-DD HH:mm:ss') }}</span>
        </template>
      </el-table-column>
      <el-table-column :label="t('settings.session.actions')" width="250" fixed="right">
        <template #default="{ row }">
          <el-button type="primary" @click="handleEdit(row)">
            {{ t('settings.proxy.edit') }}
          </el-button>
          <el-button type="success" @click="handleClone(row)">
            {{ t('settings.proxy.clone') }}
          </el-button>
          <el-button type="danger" @click="handleDelete(row)">
            {{ t('settings.proxy.delete') }}
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog
      v-model="dialogVisible"
      :title="dialogTitle"
      width="500px"
      :close-on-click-modal="false"
      :close-on-press-escape="false"
    >
      <el-form
        ref="formRef"
        :model="formData"
        :rules="rules"
        label-width="80px"
        label-suffix="："
      >
        <el-form-item :label="t('common.type')" prop="type">
          <el-select
            v-model="formData.type"
            :placeholder="t('settings.proxy.selectProxyType')"
            style="width: 100%"
            clearable
          >
            <el-option label="HTTP" value="http" />
            <el-option label="SOCKS5" value="socks5" />
          </el-select>
        </el-form-item>

        <el-form-item :label="t('common.name')" prop="name">
          <el-input
            v-model.trim="formData.name"
            :placeholder="t('settings.proxy.enterProxyName')"
            maxlength="50"
            show-word-limit
          />
        </el-form-item>

        <el-form-item :label="t('settings.proxy.host')" prop="host">
          <el-input
            v-model.trim="formData.host"
            :placeholder="t('settings.proxy.enterHost')"
          />
        </el-form-item>

        <el-form-item :label="t('settings.proxy.port')" prop="port">
          <el-input
            v-model.number="formData.port"
            :placeholder="t('settings.proxy.enterPort')"
            type="number"
            :min="1"
            :max="65535"
          />
        </el-form-item>

        <el-form-item :label="t('settings.proxy.username')" prop="username">
          <el-input
            v-model.trim="formData.username"
            :placeholder="t('settings.proxy.enterOptionalUsername')"
            maxlength="100"
          />
        </el-form-item>

        <el-form-item :label="t('settings.proxy.password')" prop="password">
          <el-input
            v-model.trim="formData.password"
            :placeholder="t('settings.proxy.enterOptionalPassword')"
            maxlength="200"
          />
        </el-form-item>
      </el-form>

      <template #footer>
        <div class="dialog-footer">
          <el-button @click="handleCancel">{{ t('common.cancel') }}</el-button>
          <el-button type="primary" :loading="submitLoading" @click="handleSubmit">{{ t('common.confirm') }}</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, getCurrentInstance, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { Plus } from '@element-plus/icons-vue'
import dayjs from 'dayjs'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()
const { t } = useI18n()

const loading = ref(false)
const submitLoading = ref(false)
const dialogVisible = ref(false)
const dialogTitle = ref('')
const formRef = ref(null)
const currentEditId = ref(null)
const proxyList = computed(() => {
  if (Array.isArray($store.proxyList)) {
    return $store.proxyList.map(item => {
      item.displayPassword = formatPassword(item.password)
      return item
    })
  }
  return []
})
const isPlusActive = computed(() => $store.isPlusActive)

const formData = reactive({
  type: 'socks5',
  name: '',
  host: '',
  port: '',
  username: '',
  password: ''
})

const rules = reactive({
  type: [
    { required: true, message: t('settings.proxy.validation.selectProxyType'), trigger: 'change' },
  ],
  name: [
    { required: true, message: t('settings.proxy.validation.enterProxyName'), trigger: 'blur' },
    { min: 1, max: 50, message: t('settings.proxy.validation.proxyNameLength'), trigger: 'blur' },
  ],
  host: [
    { required: true, message: t('settings.proxy.validation.enterHost'), trigger: 'blur' },
  ],
  port: [
    { required: true, message: t('settings.proxy.validation.enterPort'), trigger: 'blur' },
    { type: 'number', min: 1, max: 65535, message: t('settings.proxy.validation.portRange'), trigger: 'blur' },
  ]
})

const formatPassword = (password) => {
  if (!password) return '-'
  if (password.length <= 6) {
    return '*'.repeat(password.length)
  }
  const start = password.slice(0, 3)
  const end = password.slice(-3)
  const middle = '*'.repeat(password.length - 6)
  return start + middle + end
}

const resetForm = () => {
  Object.assign(formData, {
    type: 'socks5',
    name: '',
    host: '',
    port: '',
    username: '',
    password: ''
  })
  currentEditId.value = null
  formRef.value?.clearValidate()
}

const handleAdd = () => {
  resetForm()
  dialogTitle.value = t('settings.proxy.addProxy')
  dialogVisible.value = true
}

const handleEdit = (row) => {
  resetForm()
  Object.assign(formData, {
    type: row.type,
    name: row.name,
    host: row.host,
    port: row.port,
    username: row.username || '',
    password: row.password || ''
  })
  currentEditId.value = row.id
  dialogTitle.value = t('settings.proxy.editProxy')
  dialogVisible.value = true
}

const handleDelete = async (row) => {
  try {
    await $messageBox.confirm(
      t('settings.proxy.confirmDelete', { name: row.name }),
      t('settings.proxy.deleteConfirmTitle'),
      {
        confirmButtonText: t('common.confirm'),
        cancelButtonText: t('common.cancel'),
        type: 'warning'
      }
    )

    await $api.removeProxy(row.id)
    $message.success(t('settings.proxy.deleteSuccess'))
    await $store.getProxyList()
    await $store.getHostList()
  } catch (error) {
    if (error === 'cancel') {
      return
    }
    console.error('删除代理失败:', error)
    $message.error(t('settings.proxy.deleteFailed'))
  }
}

const handleClone = async (row) => {
  try {
    const cloneData = {
      type: row.type,
      name: `${ row.name }_${ t('settings.proxy.cloneSuffix') }`,
      host: row.host,
      port: row.port,
      username: row.username || '',
      password: row.password || ''
    }

    await $api.addProxy(cloneData)
    $message.success(t('settings.proxy.cloneSuccess'))
    await $store.getProxyList()
  } catch (error) {
    console.error('克隆代理失败:', error)
    $message.error(t('settings.proxy.cloneFailed'))
  }
}

const handleCancel = () => {
  dialogVisible.value = false
  resetForm()
}

const handleSubmit = async () => {
  try {
    const valid = await formRef.value.validate()
    if (!valid) return

    submitLoading.value = true

    if (currentEditId.value) {
      await $api.updateProxy(currentEditId.value, formData)
      $message.success(t('settings.proxy.updateSuccess'))
    } else {
      await $api.addProxy(formData)
      $message.success(t('settings.proxy.addSuccess'))
    }

    dialogVisible.value = false
    resetForm()
    await $store.getProxyList()
  } catch (error) {
    console.error('操作失败:', error)
    $message.error(t('settings.proxy.operationFailed'))
  } finally {
    submitLoading.value = false
  }
}

const handleShowPassword = (row) => {
  row.displayPassword = row.password
}
</script>

<style lang="scss" scoped>
.proxy-container {
  .operation-bar {
    margin-bottom: 20px;
    display: flex;
    justify-content: flex-end;
  }
}

.dialog-footer {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}
</style>

