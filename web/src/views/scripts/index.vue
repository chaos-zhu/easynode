<template>
  <div class="scripts_container">
    <div class="header">
      <el-input
        v-model="searchKeyword"
        :placeholder="t('scripts.searchPlaceholder')"
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
        @click="handleBatchRemove"
      >
        {{ t('scripts.batchDelete') }}
      </el-button>
      <el-button type="primary" @click="addScript">{{ t('scripts.addScript') }}</el-button>
      <PlusSupportTip>
        <el-dropdown trigger="click" :disabled="!isPlusActive">
          <el-button type="primary" class="group_action_btn" :disabled="!isPlusActive">
            {{ t('scripts.importExport') }}<el-icon class="el-icon--right"><arrow-down /></el-icon>
          </el-button>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="importVisible = true">{{ t('scripts.importScript') }}</el-dropdown-item>
              <el-dropdown-item @click="handleExport">{{ t('scripts.exportScript') }}</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </PlusSupportTip>
      <PlusSupportTip>
        <el-button
          type="primary"
          class="group_action_btn"
          :disabled="!isPlusActive"
          @click="ScriptGroupVisible = true"
        >
          {{ t('scripts.groupManagement') }}
        </el-button>
      </PlusSupportTip>
    </div>

    <el-tabs v-model="activeTab" type="border-card" class="script-tabs">
      <el-tab-pane
        v-for="group in groupList"
        :key="group.id"
        :label="group.name"
        :name="group.id"
      >
        <el-table
          v-loading="loading"
          :data="getFilteredScriptsByGroup(group.id)"
          @selection-change="handleSelectionChange"
        >
          <el-table-column
            type="selection"
            width="55"
            :selectable="(row) => {
              return row.index !== '--' && row.index !== '-' && row.index !== undefined && row.index !== null
            }"
          />
          <el-table-column prop="index" :label="t('scripts.index')" width="100px" />
          <el-table-column prop="name" :label="t('scripts.name')" />
          <el-table-column prop="description" :label="t('scripts.description')" />
          <el-table-column prop="command" :label="t('scripts.commandContent')" show-overflow-tooltip />
          <el-table-column
            prop="useBase64"
            :label="t('scripts.encodingMode')"
            width="140px"
            :formatter="formatExecutionMode"
          />
          <el-table-column :label="t('scripts.actions')" fixed="right" width="160px">
            <template #default="{ row }">
              <template v-if="row.index !== '--'">
                <el-button type="primary" @click="handleChange(row)">{{ t('scripts.edit') }}</el-button>
                <el-button v-show="row.id !== 'own'" type="danger" @click="handleRemove(row)">{{ t('scripts.delete') }}</el-button>
              </template>
              <span v-else>{{ t('scripts.noAction') }}</span>
            </template>
          </el-table-column>
        </el-table>

        <div class="pagination-container">
          <el-pagination
            v-model:current-page="currentPage"
            v-model:page-size="pageSize"
            :page-sizes="[20, 50, 100]"
            :total="getFilteredScriptsByGroup(group.id).length"
            layout="total, sizes, prev, pager, next"
            @size-change="handleSizeChange"
            @current-change="handleCurrentChange"
          />
        </div>
      </el-tab-pane>
    </el-tabs>

    <ScriptEdit
      v-model:show="formVisible"
      :default-data="currentScript"
      :default-group="activeTab"
      @success="handleEditSuccess"
    />

    <ImportScript
      v-model:show="importVisible"
      @update-list="() => $store.getScriptList()"
    />

    <ScriptGroup
      v-model:show="ScriptGroupVisible"
      @group-deleted="handleGroupDeleted"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, nextTick, getCurrentInstance, h, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import ImportScript from './components/import-script.vue'
import PlusSupportTip from '@/components/common/PlusSupportTip.vue'
import { ArrowDown, Search } from '@element-plus/icons-vue'
import { exportFile } from '@/utils'
import ScriptGroup from './components/script-group.vue'
import ScriptEdit from './components/script-edit.vue'

const { proxy: { $api, $message, $messageBox, $store, $tools } } = getCurrentInstance()
const { t } = useI18n()

const loading = ref(false)
const formVisible = ref(false)
const selectScripts = ref([])
const handleSelectionChange = (val) => {
  selectScripts.value = val
}
const handleBatchRemove = () => {
  if (!selectScripts.value.length) return $message.warning(t('scripts.selectScriptsFirst'))
  let ids = selectScripts.value.map(item => item.id)
  let names = selectScripts.value.map(item => item.name)
  $messageBox.confirm(() => h('p', { style: 'line-height: 18px;' }, t('scripts.deleteBatchConfirm', { names: names.join(', ') })), 'Warning', {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
    type: 'warning'
  }).then(async () => {
    await $api.batchRemoveScript({ ids })
    await $store.getScriptList()
    $message.success('success')
  })
}

const currentScript = ref({})

const scriptList = computed(() => $store.scriptList)
const isPlusActive = computed(() => $store.isPlusActive)

const groupList = computed(() => $store.scriptGroupList || [])

const addScript = () => {
  currentScript.value = {}
  formVisible.value = true
}

const handleChange = (row) => {
  currentScript.value = { ...row }
  formVisible.value = true
}

const handleRemove = ({ id, name }) => {
  $messageBox.confirm(t('scripts.deleteConfirm', { name }), 'Warning', {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
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
  if (!scriptList.value.length) return $message.warning(t('scripts.noExportableScripts'))
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

const activeTab = ref(computed(() => groupList.value?.[0]?.id || 'default').value)

const getFilteredScriptsByGroup = (groupId) => {
  const groupScripts = filteredScriptList.value.filter(script => script.group === groupId)
  const start = (currentPage.value - 1) * pageSize.value
  const end = start + pageSize.value
  return groupScripts.slice(start, end)
}

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

const ScriptGroupVisible = ref(false)

const handleGroupDeleted = (deletedGroupId) => {
  if (deletedGroupId === activeTab.value) {
    nextTick(() => {
      activeTab.value = groupList.value?.[0]?.id || 'default'
    })
  }
}

watch(activeTab, () => {
  currentPage.value = 1
})

const handleEditSuccess = () => {
  currentScript.value = {}
}

// 格式化编码方式显示
const formatExecutionMode = (row, column, cellValue) => {
  if (cellValue === true) {
    return t('scripts.base64Encoding')
  }
  return t('scripts.sendDirectly')
}

</script>

<style lang="scss" scoped>
.scripts_container {
  padding: 0 20px 20px 20px;
  .header {
    padding: 10px;
    display: flex;
    align-items: center;
    justify-content: end;
    .group_action_btn {
      margin-left: 10px;
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