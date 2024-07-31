<template>
  <div class="scripts_container">
    <div class="header">
      <el-button type="primary" @click="addScript">添加脚本</el-button>
    </div>
    <el-table v-loading="loading" :data="scriptList">
      <el-table-column prop="index" label="序号" width="100px" />
      <el-table-column prop="name" label="名称" />
      <el-table-column prop="remark" label="备注" />
      <el-table-column prop="content" label="脚本内容" show-overflow-tooltip />
      <el-table-column label="操作">
        <template #default="{ row }">
          <el-button type="primary" @click="handleChange(row)">修改</el-button>
          <el-button v-show="row.id !== 'own'" type="danger" @click="handleRemove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog
      v-model="formVisible"
      width="600px"
      top="150px"
      :title="isModify ? '修改脚本' : '添加脚本'"
      :close-on-click-modal="false"
      @close="clearFormInfo"
    >
      <el-form
        ref="updateFormRef"
        :model="formData"
        :rules="rules"
        :hide-required-asterisk="true"
        label-suffix="："
        label-width="100px"
        :show-message="false"
      >
        <el-form-item label="名称" prop="name">
          <el-input
            v-model.trim="formData.name"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item label="备注" prop="remark">
          <el-input
            v-model.trim="formData.remark"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item label="序号" prop="index">
          <el-input
            v-model.trim.number="formData.index"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item prop="content" label="内容">
          <el-input
            v-model.trim="formData.content"
            type="textarea"
            :rows="5"
            clearable
            autocomplete="off"
            style="margin-top: 5px;"
            placeholder="shell script"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <span>
          <el-button @click="formVisible = false">关闭</el-button>
          <el-button type="primary" @click="updateForm">{{ isModify ? '修改' : '添加' }}</el-button>
        </span>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, computed, nextTick, getCurrentInstance } from 'vue'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()

const loading = ref(false)
const formVisible = ref(false)
let isModify = ref(false)

let formData = reactive({
  name: '',
  remark: '',
  index: 0,
  content: ''
})

const rules = computed(() => {
  return {
    name: { required: true, trigger: 'change' },
    remark: { required: false, trigger: 'change' },
    index: { required: false, type: 'number', trigger: 'change' },
    content: { required: true, trigger: 'change' }
  }
})

const updateFormRef = ref(null)

let scriptList = computed(() => $store.scriptList)

let addScript = () => {
  formData.id = null
  isModify.value = false
  formVisible.value = true
}

const handleChange = (row) => {
  Object.assign(formData, { ...row })
  formVisible.value = true
  isModify.value = true
}

function updateForm() {
  updateFormRef.value.validate()
    .then(async () => {
      let data = { ...formData }
      if (isModify.value) {
        await $api.updateScript(data.id, data)
      } else {
        await $api.addScript(data)
      }
      formVisible.value = false
      await $store.getScriptList()
      $message.success('success')
    })
}

const clearFormInfo = () => {
  nextTick(() => updateFormRef.value.resetFields())
}

const handleRemove = ({ id, name }) => {
  $messageBox.confirm(`确认删除该脚本：${ name }`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  })
    .then(async () => {
      await $api.deleteScript(id)
      await $store.getScriptList()
      $message.success('success')
    })
}

</script>

<style lang="scss" scoped>
.scripts_container {
  padding: 20px;
  .header {
    padding: 15px;
    display: flex;
    align-items: center;
    justify-content: end;
  }
}

.host_count {
  display: block;
  width: 100px;
  text-align: center;
  font-size: 15px;
  color: #87cf63;
  cursor: pointer;
}
</style>