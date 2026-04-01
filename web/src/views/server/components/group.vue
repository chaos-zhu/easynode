<template>
  <el-dialog
    v-model="visible"
    width="600px"
    :top="isMobile() ? '45px' : '15vh'"
    :append-to-body="false"
    :title="t('server.group.title')"
    :close-on-click-modal="false"
  >
    <div class="group_container">
      <div class="header">
        <el-button type="primary" @click="addGroup">{{ t('server.group.addGroup') }}</el-button>
      </div>
      <el-table v-loading="loading" :data="list">
        <el-table-column prop="index" :label="t('server.index')" />
        <el-table-column prop="name" :label="t('server.group.groupName')" />
        <el-table-column :label="t('server.group.relatedInstanceCount')" min-width="115px">
          <template #default="{ row }">
            <el-popover
              v-if="row.hosts.list.length !== 0"
              placement="left"
              :width="350"
              trigger="hover"
            >
              <template #reference>
                <u class="host_count">{{ row.hosts.count }}</u>
              </template>
              <ul>
                <li v-for="item in row.hosts.list" :key="item.host">
                  <span>{{ item.host }}</span>
                  -
                  <span>{{ item.name }}</span>
                </li>
              </ul>
            </el-popover>
            <u v-else class="host_count">0</u>
          </template>
        </el-table-column>
        <el-table-column :label="t('server.group.actions')" fixed="right" width="160px">
          <template #default="{ row }">
            <el-button type="primary" @click="handleChange(row)">{{ t('server.group.edit') }}</el-button>
            <el-button v-show="row.id !== 'default'" type="danger" @click="deleteGroup(row)">{{ t('server.group.delete') }}</el-button>
          </template>
        </el-table-column>
      </el-table>
      <el-dialog
        v-model="groupFormVisible"
        width="600px"
        top="150px"
        :title="isModify ? t('server.group.editTitle') : t('server.group.addTitle')"
        :close-on-click-modal="false"
        @close="clearFormInfo"
      >
        <el-form
          ref="updateFormRef"
          :model="groupForm"
          :rules="rules"
          :hide-required-asterisk="true"
          label-suffix="："
          label-width="100px"
          :show-message="false"
        >
          <el-form-item :label="t('server.group.groupName')" prop="name">
            <el-input
              v-model="groupForm.name"
              clearable
              autofocus
              placeholder=""
              autocomplete="off"
            />
          </el-form-item>
          <el-form-item :label="t('server.group.groupOrder')" prop="index">
            <el-input
              v-model.number="groupForm.index"
              clearable
              :placeholder="t('server.group.orderPlaceholder')"
              autocomplete="off"
            />
          </el-form-item>
        </el-form>
        <template #footer>
          <span>
            <el-button @click="groupFormVisible = false">{{ t('server.group.close') }}</el-button>
            <el-button type="primary" @click="updateForm">{{ isModify ? t('server.group.edit') : t('server.group.add') }}</el-button>
          </span>
        </template>
      </el-dialog>
    </div>
  </el-dialog>
</template>

<script setup>
import { isMobile } from '@/utils'
import { ref, reactive, computed, nextTick, getCurrentInstance } from 'vue'
import { useI18n } from 'vue-i18n'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()
const { t } = useI18n()

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show',])

const visible = computed({
  get: () => props.show,
  set: (newVal) => emit('update:show', newVal)
})

const loading = ref(false)
const groupFormVisible = ref(false)
let isModify = ref(false)
const groupForm = reactive({
  id: null,
  name: '',
  index: ''
})

const rules = computed(() => {
  return {
    name: { required: true, message: t('server.group.nameRequired'), trigger: 'change' },
    index: { required: true, type: 'number', message: t('server.group.numberRequired'), trigger: 'change' }
  }
})

const updateFormRef = ref(null)

let groupList = computed(() => $store.groupList || [])
const hostList = computed(() => $store.hostList)

const list = computed(() => {
  return groupList.value.map(item => {
    const hosts = hostList.value.reduce((prev, next) => {
      if (next.group === item.id) {
        prev.count++
        prev.list.push(next)
      }
      return prev
    }, { count: 0, list: [] })
    return { ...item, hosts }
  })
})

let addGroup = () => {
  groupForm.id = null
  const maxIndex = Math.max(...groupList.value.map(item => item.index), 0)
  groupForm.index = maxIndex + 1
  groupFormVisible.value = true
  isModify.value = false
}

const handleChange = (row) => {
  Object.assign(groupForm, { ...row })
  groupFormVisible.value = true
  isModify.value = true
}

const updateForm = () => {
  updateFormRef.value.validate()
    .then(async () => {
      const { id, index, name } = groupForm
      if (isModify.value) {
        await $api.updateGroup(id, { index, name })
      } else {
        await $api.addGroup({ index, name })
      }
      await $store.getGroupList()
      groupFormVisible.value = false
      $message.success('success')
    })
}

const clearFormInfo = () => {
  nextTick(() => updateFormRef.value.resetFields())
}

const deleteGroup = ({ id, name }) => {
  $messageBox.confirm(t('server.group.deleteConfirm', { name }), 'Warning', {
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel'),
    type: 'warning'
  })
    .then(async () => {
      await $api.deleteGroup(id)
      await $store.getHostList()
      await $store.getGroupList()
      $message.success('success')
    })
}

</script>

<style lang="scss" scoped>
.group_container {
  .header {
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