<template>
  <el-dialog
    v-model="visible"
    width="600px"
    :top="isMobile() ? '45px' : '15vh'"
    :append-to-body="false"
    :title="t('scripts.scriptGroupManagement')"
    :close-on-click-modal="false"
  >
    <div class="group_container">
      <div class="header">
        <el-button type="primary" @click="addGroup">{{ t('scripts.addGroup') }}</el-button>
      </div>
      <el-table v-loading="loading" :data="list">
        <el-table-column prop="index" :label="t('scripts.index')" />
        <el-table-column prop="name" :label="t('scripts.groupName')" />
        <el-table-column :label="t('scripts.relatedScriptCount')" min-width="115px">
          <template #default="{ row }">
            <el-popover
              v-if="row.scripts.list.length !== 0"
              placement="left"
              :width="350"
              trigger="hover"
            >
              <template #reference>
                <u class="script_count">{{ row.scripts.count }}</u>
              </template>
              <ul>
                <li v-for="item in row.scripts.list" :key="item.id">
                  <span>{{ item.name }}</span>
                  -
                  <span>{{ item.description }}</span>
                </li>
              </ul>
            </el-popover>
            <u v-else class="script_count">0</u>
          </template>
        </el-table-column>
        <el-table-column :label="t('scripts.actions')" fixed="right" width="160px">
          <template #default="{ row }">
            <template v-if="row.id !== 'builtin'">
              <el-button type="primary" @click="handleChange(row)">{{ t('scripts.edit') }}</el-button>
              <el-button
                v-show="row.id !== 'default'"
                type="danger"
                @click="deleteGroup(row)"
              >
                {{ t('scripts.delete') }}
              </el-button>
            </template>
            <template v-else>
              <span>{{ t('scripts.noAction') }}</span>
            </template>
          </template>
        </el-table-column>
      </el-table>

      <el-dialog
        v-model="groupFormVisible"
        width="600px"
        top="150px"
        :title="isModify ? t('scripts.editGroupTitle') : t('scripts.addGroupTitle')"
        :close-on-click-modal="false"
        @close="clearFormInfo"
      >
        <el-form
          ref="updateFormRef"
          :model="groupForm"
          :rules="rules"
          label-width="100px"
        >
          <el-form-item :label="t('scripts.groupName')" prop="name">
            <el-input v-model="groupForm.name" />
          </el-form-item>
          <el-form-item :label="t('scripts.index')" prop="index">
            <el-input v-model.number="groupForm.index" />
          </el-form-item>
        </el-form>
        <template #footer>
          <span class="dialog-footer">
            <el-button @click="groupFormVisible = false">{{ t('common.cancel') }}</el-button>
            <el-button type="primary" @click="updateForm">{{ t('common.confirm') }}</el-button>
          </span>
        </template>
      </el-dialog>
    </div>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { isMobile } from '@/utils'

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show', 'group-deleted',])

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

const { proxy: { $api, $store, $message, $messageBox } } = getCurrentInstance()
const { t } = useI18n()

const loading = ref(false)
const groupFormVisible = ref(false)
const isModify = ref(false)
const updateFormRef = ref()

const groupForm = ref({
  id: null,
  name: '',
  index: 0
})

const rules = computed(() => ({
  name: [{ required: true, message: t('scripts.groupNameRequired'), trigger: 'blur' },],
  index: [{ type: 'number', message: t('scripts.indexMustBeNumber') },]
}))

const scriptList = computed(() => $store.scriptList)
const groupList = computed(() => $store.scriptGroupList)

const list = computed(() => {
  return groupList.value.map(item => {
    const scripts = scriptList.value.reduce((prev, next) => {
      if (next.group === item.id) {
        prev.count++
        prev.list.push(next)
      }
      return prev
    }, { count: 0, list: [] })
    return { ...item, scripts }
  })
})

const addGroup = () => {
  groupForm.value.id = null
  groupForm.value.index = groupList.value.reduce((max, group) =>
    Math.max(max, Number(group.index) || 0), 0) + 1
  groupFormVisible.value = true
  isModify.value = false
}

const handleChange = (row) => {
  Object.assign(groupForm.value, { ...row })
  groupFormVisible.value = true
  isModify.value = true
}

const updateForm = () => {
  updateFormRef.value.validate()
    .then(async () => {
      const { id, index, name } = groupForm.value
      if (isModify.value) {
        await $api.updateScriptGroup(id, { index, name })
      } else {
        await $api.addScriptGroup({ index, name })
      }
      await $store.getScriptGroupList()
      groupFormVisible.value = false
      $message.success('success')
    })
}

const clearFormInfo = () => {
  nextTick(() => updateFormRef.value.resetFields())
}

const deleteGroup = ({ id, name }) => {
  $messageBox.confirm(t('scripts.deleteGroupConfirm', { name }), 'Warning', {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
    type: 'warning'
  })
    .then(async () => {
      await $api.deleteScriptGroup(id)
      await $store.getScriptList()
      await $store.getScriptGroupList()
      emit('group-deleted', id)
      $message.success('success')
    })
}
</script>

<style lang="scss" scoped>
.group_container {
  padding: 0 20px 20px 20px;

  .header {
    display: flex;
    align-items: center;
    justify-content: end;
  }
}

.script_count {
  display: block;
  width: 100px;
  text-align: center;
  font-size: 15px;
  color: #87cf63;
  cursor: pointer;
}
</style>