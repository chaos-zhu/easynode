<template>
  <div class="group_container">
    <div class="header">
      <el-button type="primary" @click="addGroup">添加分组</el-button>
    </div>
    <el-table v-loading="loading" :data="list">
      <el-table-column prop="index" label="序号" />
      <el-table-column prop="name" label="分组名称" />
      <el-table-column label="关联实例数量" min-width="115px">
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
      <el-table-column label="操作" fixed="right" width="160px">
        <template #default="{ row }">
          <el-button type="primary" @click="handleChange(row)">修改</el-button>
          <el-button v-show="row.id !== 'default'" type="danger" @click="deleteGroup(row)">删除</el-button>
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
        :hide-required-asterisk="true"
        label-suffix="："
        label-width="100px"
        :show-message="false"
      >
        <el-form-item label="分组名称" prop="name">
          <el-input
            v-model="groupForm.name"
            clearable
            placeholder=""
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item label="分组序号" prop="index">
          <el-input
            v-model.number="groupForm.index"
            clearable
            placeholder="用于分组排序"
            autocomplete="off"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <span>
          <el-button @click="groupFormVisible = false">关闭</el-button>
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
const groupFormVisible = ref(false)
let isModify = ref(false)
const groupForm = reactive({
  id: null,
  name: '',
  index: ''
})

const rules = computed(() => {
  return {
    name: { required: true, message: '需输入分组名称', trigger: 'change' },
    index: { required: true, type: 'number', message: '需输入数字', trigger: 'change' }
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
  $messageBox.confirm(`确认删除分组：${ name } (分组下实例将移动至默认分组)`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
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