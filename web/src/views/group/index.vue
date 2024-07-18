<template>
  <div class="group_container">
    <el-form
      ref="groupFormRef"
      :model="groupForm"
      :rules="rules"
      :inline="true"
      :hide-required-asterisk="true"
      label-suffix="："
    >
      <el-form-item label="" prop="name" style="width: 200px;">
        <el-input
          v-model.trim="groupForm.name"
          clearable
          placeholder="分组名称"
          autocomplete="off"
          @keyup.enter="addGroup"
        />
      </el-form-item>
      <el-form-item label="" prop="index" style="width: 200px;">
        <el-input
          v-model.number="groupForm.index"
          clearable
          placeholder="序号(数字, 用于分组排序)"
          autocomplete="off"
          @keyup.enter="addGroup"
        />
      </el-form-item>
      <el-form-item label="">
        <el-button type="primary" @click="addGroup">
          添加
        </el-button>
      </el-form-item>
    </el-form>
    <!-- 提示 -->
    <el-alert type="success" :closable="false">
      <template #title>
        <span style="letter-spacing: 2px;">
          Tips: 已添加服务器数量 <u>{{ hostGroupInfo.total }}</u>
          <span v-show="hostGroupInfo.notGroupCount">, 有 <u>{{ hostGroupInfo.notGroupCount }}</u> 台服务器尚未分组</span>
        </span>
      </template>
    </el-alert><br>
    <el-alert type="success" :closable="false">
      <template #title>
        <span style="letter-spacing: 2px;"> Tips: 删除分组会将分组内所有服务器移至默认分组 </span>
      </template>
    </el-alert>
    <el-table v-loading="loading" :data="list">
      <el-table-column prop="index" label="序号" />
      <el-table-column prop="id" label="ID" />
      <el-table-column prop="name" label="分组名称" />
      <el-table-column label="关联服务器数量">
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
      <el-table-column label="操作">
        <template #default="{ row }">
          <el-button type="primary" @click="handleChange(row)">修改</el-button>
          <el-button v-show="row.id !== 'default'" type="danger" @click="deleteGroup(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog
      v-model="visible"
      width="400px"
      title="修改分组"
      :close-on-click-modal="false"
    >
      <el-form
        ref="updateFormRef"
        :model="updateForm"
        :rules="rules"
        :hide-required-asterisk="true"
        label-suffix="："
        label-width="100px"
      >
        <el-form-item label="分组名称" prop="name">
          <el-input
            v-model.trim="updateForm.name"
            clearable
            placeholder="分组名称"
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item label="分组序号" prop="index">
          <el-input
            v-model.number="updateForm.index"
            clearable
            placeholder="分组序号"
            autocomplete="off"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <span class="dialog-footer">
          <el-button @click="visible = false">关闭</el-button>
          <el-button type="primary" @click="updateGroup">修改</el-button>
        </span>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, getCurrentInstance } from 'vue'

const { proxy: { $api, $message, $messageBox, $store } } = getCurrentInstance()

const loading = ref(false)
const visible = ref(false)
const groupList = ref([])
const groupForm = reactive({
  name: '',
  index: ''
})
const updateForm = reactive({
  name: '',
  index: ''
})
const rules = reactive({
  name: { required: true, message: '需输入分组名称', trigger: 'change' },
  index: { required: true, type: 'number', message: '需输入数字', trigger: 'change' }
})

const groupFormRef = ref(null)
const updateFormRef = ref(null)

const hostGroupInfo = computed(() => {
  const total = $store.hostList.length
  const notGroupCount = $store.hostList.reduce((prev, next) => {
    if (!next.group) prev++
    return prev
  }, 0)
  return { total, notGroupCount }
})

const list = computed(() => {
  return groupList.value.map(item => {
    const hosts = $store.hostList.reduce((prev, next) => {
      if (next.group === item.id) {
        prev.count++
        prev.list.push(next)
      }
      return prev
    }, { count: 0, list: [] })
    return { ...item, hosts }
  })
})

const getGroupList = () => {
  loading.value = true
  $api.getGroupList()
    .then(({ data }) => {
      groupList.value = data
      groupForm.index = data.length
    })
    .finally(() => loading.value = false)
}

const addGroup = () => {
  groupFormRef.value.validate()
    .then(() => {
      const { name, index } = groupForm
      $api.addGroup({ name, index })
        .then(() => {
          $message.success('success')
          groupForm.name = ''
          groupForm.index = ''
          getGroupList()
        })
    })
}

const handleChange = ({ id, name, index }) => {
  updateForm.id = id
  updateForm.name = name
  updateForm.index = index
  visible.value = true
}

const updateGroup = () => {
  updateFormRef.value.validate()
    .then(() => {
      const { id, name, index } = updateForm
      $api.updateGroup(id, { name, index })
        .then(() => {
          $message.success('success')
          visible.value = false
          getGroupList()
        })
    })
}

const deleteGroup = ({ id, name }) => {
  $messageBox.confirm(`确认删除分组：${ name }`, 'Warning', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  })
    .then(async () => {
      await $api.deleteGroup(id)
      await $store.getHostList()
      $message.success('success')
      getGroupList()
    })
}

onMounted(() => {
  getGroupList()
})
</script>

<style lang="scss" scoped>
.group_container {
  padding: 20px;
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