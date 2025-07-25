<template>
  <el-dialog
    v-model="visible"
    width="600px"
    :top="isMobile() ? '45px' : '15vh'"
    :append-to-body="false"
    title="脚本分组管理"
    :close-on-click-modal="false"
  >
    <div class="group_container">
      <div class="header">
        <el-button type="primary" @click="addGroup">添加分组</el-button>
      </div>
      <el-table v-loading="loading" :data="list">
        <el-table-column prop="index" label="序号" />
        <el-table-column prop="name" label="分组名称" />
        <el-table-column label="关联脚本数量" min-width="115px">
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
        <el-table-column label="操作" fixed="right" width="160px">
          <template #default="{ row }">
            <template v-if="row.id !== 'builtin'">
              <el-button type="primary" @click="handleChange(row)">修改</el-button>
              <el-button
                v-show="row.id !== 'default'"
                type="danger"
                @click="deleteGroup(row)"
              >
                删除
              </el-button>
            </template>
            <template v-else>
              <span>--</span>
            </template>
          </template>
        </el-table-column>
      </el-table>

      <el-dialog
        v-model="groupFormVisible"
        width="600px"
        top="150px"
        :title="isModify ? '修改分组' : '添加分组'"
        :close-on-click-modal="false"
        @close="clearFormInfo"
      >
        <el-form
          ref="updateFormRef"
          :model="groupForm"
          :rules="rules"
          label-width="100px"
        >
          <el-form-item label="分组名称" prop="name">
            <el-input v-model="groupForm.name" />
          </el-form-item>
          <el-form-item label="序号" prop="index">
            <el-input v-model.number="groupForm.index" />
          </el-form-item>
        </el-form>
        <template #footer>
          <span class="dialog-footer">
            <el-button @click="groupFormVisible = false">取消</el-button>
            <el-button type="primary" @click="updateForm">确定</el-button>
          </span>
        </template>
      </el-dialog>
    </div>
  </el-dialog>
</template>

<script setup>
import { ref, computed, getCurrentInstance, nextTick } from 'vue'
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

const loading = ref(false)
const groupFormVisible = ref(false)
const isModify = ref(false)
const updateFormRef = ref()

const groupForm = ref({
  id: null,
  name: '',
  index: 0
})

const rules = {
  name: [{ required: true, message: '请输入分组名称', trigger: 'blur' },],
  index: [{ type: 'number', message: '序号必须为数字值' },]
}

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
  $messageBox.confirm(`确认删除分组：${ name } (分组下脚本将移动至默认分组)`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
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