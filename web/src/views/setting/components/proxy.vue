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
          添加代理
        </el-button>
      </PlusSupportTip>
    </div>

    <el-table
      v-loading="loading"
      :data="proxyList"
      stripe
      style="width: 100%"
      empty-text="暂无代理数据"
    >
      <el-table-column prop="type" label="类型">
        <template #default="{ row }">
          <el-tag :type="row.type === 'socks5' ? 'success' : 'primary'">
            {{ row.type === 'socks5' ? 'SOCKS5' : 'HTTP' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="name" label="名称" />
      <el-table-column prop="host" label="主机" />
      <el-table-column prop="port" label="端口" />
      <el-table-column prop="username" label="用户名">
        <template #default="{ row }">
          <span>{{ row.username || '--' }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="password" label="密码">
        <template #default="{ row }">
          <span @click="handleShowPassword(row)">{{ row.displayPassword || '--' }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="createTime" label="创建时间">
        <template #default="{ row }">
          <span>{{ dayjs(row.createTime).format('YYYY-MM-DD HH:mm:ss') }}</span>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="250" fixed="right">
        <template #default="{ row }">
          <el-button type="primary" @click="handleEdit(row)">
            编辑
          </el-button>
          <el-button type="success" @click="handleClone(row)">
            克隆
          </el-button>
          <el-button type="danger" @click="handleDelete(row)">
            删除
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
        <el-form-item label="类型" prop="type">
          <el-select
            v-model="formData.type"
            placeholder="请选择代理类型"
            style="width: 100%"
            clearable
          >
            <el-option label="HTTP" value="http" />
            <el-option label="SOCKS5" value="socks5" />
          </el-select>
        </el-form-item>

        <el-form-item label="名称" prop="name">
          <el-input
            v-model.trim="formData.name"
            placeholder="请输入代理名称"
            maxlength="50"
            show-word-limit
          />
        </el-form-item>

        <el-form-item label="主机" prop="host">
          <el-input
            v-model.trim="formData.host"
            placeholder="请输入主机地址"
          />
        </el-form-item>

        <el-form-item label="端口" prop="port">
          <el-input
            v-model.number="formData.port"
            placeholder="请输入端口号"
            type="number"
            :min="1"
            :max="65535"
          />
        </el-form-item>

        <el-form-item label="用户名" prop="username">
          <el-input
            v-model.trim="formData.username"
            placeholder="可选，请输入用户名"
            maxlength="100"
          />
        </el-form-item>

        <el-form-item label="密码" prop="password">
          <el-input
            v-model.trim="formData.password"
            placeholder="可选，请输入密码"
            maxlength="200"
          />
        </el-form-item>
      </el-form>

      <template #footer>
        <div class="dialog-footer">
          <el-button @click="handleCancel">取消</el-button>
          <el-button type="primary" :loading="submitLoading" @click="handleSubmit">确定</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, getCurrentInstance, computed } from 'vue'
import { Plus } from '@element-plus/icons-vue'
import dayjs from 'dayjs'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()

const loading = ref(false)
const submitLoading = ref(false)
const dialogVisible = ref(false)
const dialogTitle = ref('添加代理')
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

// 表单数据
const formData = reactive({
  type: 'socks5',
  name: '',
  host: '',
  port: '',
  username: '',
  password: ''
})

// 表单验证规则
const rules = reactive({
  type: [
    { required: true, message: '请选择代理类型', trigger: 'change' },
  ],
  name: [
    { required: true, message: '请输入代理名称', trigger: 'blur' },
    { min: 1, max: 50, message: '名称长度应在 1 到 50 个字符之间', trigger: 'blur' },
  ],
  host: [
    { required: true, message: '请输入主机地址', trigger: 'blur' },
  ],
  port: [
    { required: true, message: '请输入端口号', trigger: 'blur' },
    { type: 'number', min: 1, max: 65535, message: '端口号必须是1-65535之间的整数', trigger: 'blur' },
  ]
})

// 格式化密码显示
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
  dialogTitle.value = '添加代理'
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
  dialogTitle.value = '编辑代理'
  dialogVisible.value = true
}

const handleDelete = async (row) => {
  try {
    await $messageBox.confirm(
      `确定要删除代理"${ row.name }"吗？`,
      '删除确认',
      {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      }
    )

    await $api.removeProxy(row.id)
    $message.success('删除成功')
    await $store.getProxyList()
    await $store.getHostList() // 后台会移除所有使用该代理的实例的proxyServer字段
  } catch (error) {
    // 如果是用户取消操作，不显示错误
    if (error === 'cancel') {
      return
    }
    console.error('删除代理失败:', error)
    $message.error('删除代理失败')
  }
}

const handleClone = async (row) => {
  try {
    // 构造克隆数据
    const cloneData = {
      type: row.type,
      name: `${ row.name }_克隆`,
      host: row.host,
      port: row.port,
      username: row.username || '',
      password: row.password || ''
    }

    // 直接调用新增接口
    await $api.addProxy(cloneData)
    $message.success('克隆成功')

    // 刷新代理列表
    await $store.getProxyList()
  } catch (error) {
    console.error('克隆代理失败:', error)
    $message.error('克隆代理失败')
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
      // 编辑
      await $api.updateProxy(currentEditId.value, formData)
      $message.success('修改成功')
    } else {
      // 新增
      await $api.addProxy(formData)
      $message.success('添加成功')
    }

    dialogVisible.value = false
    resetForm()
    await $store.getProxyList()
  } catch (error) {
    console.error('操作失败:', error)
    $message.error('操作失败')
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
