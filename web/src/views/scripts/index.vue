<template>
  <div class="scripts_container">
    <div class="header">
      <el-input
        v-model="searchKeyword"
        placeholder="搜索名称、描述或指令内容"
        class="search_input"
        clearable
        @input="handleSearch"
      >
        <template #prefix>
          <el-icon><Search /></el-icon>
        </template>
      </el-input>
      <el-button
        v-show="selectScripts.length"
        type="danger"
        class="batch_remove_btn"
        @click="handleBatchRemove"
      >
        批量删除
      </el-button>
      <el-button type="primary" class="add_script_btn" @click="addScript">添加脚本</el-button>
      <PlusSupportTip>
        <el-dropdown trigger="click" :disabled="!isPlusActive">
          <el-button type="primary" class="group_action_btn" :disabled="!isPlusActive">
            导入导出<el-icon class="el-icon--right"><arrow-down /></el-icon>
          </el-button>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="importVisible = true">导入脚本</el-dropdown-item>
              <el-dropdown-item @click="handleExport">导出脚本</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </PlusSupportTip>
    </div>
    <el-table
      v-loading="loading"
      :data="paginatedFilteredList"
      @selection-change="handleSelectionChange"
    >
      <el-table-column
        type="selection"
        width="55"
        :selectable="(row) => {
          return row.index !== '--' && row.index !== '-' && row.index !== undefined && row.index !== null
        }"
      />
      <el-table-column prop="index" label="序号" width="100px" />
      <el-table-column prop="name" label="名称" />
      <el-table-column prop="description" label="描述" />
      <el-table-column prop="command" label="指令内容" show-overflow-tooltip />
      <el-table-column label="操作" fixed="right" width="160px">
        <template #default="{ row }">
          <template v-if="row.index !== '--'">
            <el-button type="primary" @click="handleChange(row)">修改</el-button>
            <el-button v-show="row.id !== 'own'" type="danger" @click="handleRemove(row)">删除</el-button>
          </template>
          <span v-else>--</span>
        </template>
      </el-table-column>
    </el-table>

    <div class="pagination-container">
      <el-pagination
        v-model:current-page="currentPage"
        v-model:page-size="pageSize"
        :page-sizes="[20, 50, 100]"
        :total="scriptList.length"
        layout="total, sizes, prev, pager, next"
        @size-change="handleSizeChange"
        @current-change="handleCurrentChange"
      />
    </div>

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
            v-model="formData.name"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item label="描述" prop="description">
          <el-input
            v-model="formData.description"
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
        <el-form-item prop="command" label="内容">
          <el-input
            v-model="formData.command"
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

    <ImportScript
      v-model:show="importVisible"
      @update-list="() => $store.getScriptList()"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, nextTick, getCurrentInstance, h } from 'vue'
import ImportScript from './components/import-script.vue'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'
import { ArrowDown, Search } from '@element-plus/icons-vue'
import { exportFile } from '@/utils'

const { proxy: { $api, $message, $messageBox, $store, $tools } } = getCurrentInstance()

const loading = ref(false)
const formVisible = ref(false)
let isModify = ref(false)
const selectScripts = ref([])
const handleSelectionChange = (val) => {
  selectScripts.value = val
}
const handleBatchRemove = () => {
  if (!selectScripts.value.length) return $message.warning('请选择要批量删除的脚本')
  let ids = selectScripts.value.map(item => item.id)
  let names = selectScripts.value.map(item => item.name)
  $messageBox.confirm(() => h('p', { style: 'line-height: 18px;' }, `确认删除\n${ names.join(', ') }吗?`), 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(async () => {
    await $api.batchRemoveScript({ ids })
    await $store.getScriptList()
    $message.success('success')
  })
}

let formData = reactive({
  name: '',
  description: '',
  index: 0,
  command: ''
})

const rules = computed(() => {
  return {
    name: { required: true, trigger: 'change' },
    description: { required: false, trigger: 'change' },
    index: { required: false, type: 'number', trigger: 'change' },
    command: { required: true, trigger: 'change' }
  }
})

const updateFormRef = ref(null)

const scriptList = computed(() => $store.scriptList)
const isPlusActive = computed(() => $store.isPlusActive)

let addScript = () => {
  formData.id = null
  formData.index = scriptList.value.reduce((acc, cur) => Math.max(acc, Number(cur.index) || 0), 0) + 1
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

const importVisible = ref(false)

const handleExport = () => {
  if (!scriptList.value.length) return $message.warning('暂无可导出的脚本')
  const fileName = `easynode-scripts-${ $tools.formatTimestamp(Date.now(), 'time', '.') }.json`
  exportFile(scriptList.value, fileName, 'application/json')
}

const currentPage = ref(1)
const pageSize = ref(20)

const searchKeyword = ref('')

const filteredScriptList = computed(() => {
  if (!searchKeyword.value) return scriptList.value

  const keyword = searchKeyword.value.toLowerCase()
  return scriptList.value.filter(item =>
    (item.name && item.name.toLowerCase().includes(keyword)) ||
    (item.description && item.description.toLowerCase().includes(keyword)) ||
    (item.command && item.command.toLowerCase().includes(keyword))
  )
})

const paginatedFilteredList = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  const end = start + pageSize.value
  return filteredScriptList.value.slice(start, end)
})

const handleSizeChange = (val) => {
  pageSize.value = val
  currentPage.value = 1
}

const handleCurrentChange = (val) => {
  currentPage.value = val
}

const handleSearch = () => {
  currentPage.value = 1
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
    .add_script_btn {
      margin: 0 10px;
    }
    .search_input {
      width: 300px;
      margin-right: auto;
    }
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

.pagination-container {
  margin-top: 20px;
  display: flex;
  justify-content: flex-end;
}
</style>