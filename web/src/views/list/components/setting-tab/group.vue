<template>
  <el-form
    ref="group-form"
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
      <!-- <el-input-number v-model="groupForm.index" :min="1" :max="10" /> -->
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
      <template #default="{row}">
        <el-popover
          v-if="row.hosts.list.length !== 0"
          placement="right"
          :width="350"
          trigger="hover"
        >
          <template #reference>
            <u class="host-count">{{ row.hosts.count }}</u>
          </template>
          <ul>
            <li v-for="item in row.hosts.list" :key="item.host">
              <span>{{ item.host }}</span>
              -
              <span>{{ item.name }}</span>
            </li>
          </ul>
        </el-popover>
        <u v-else class="host-count">0</u>
      </template>
    </el-table-column>
    <el-table-column label="操作">
      <template #default="{row}">
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
      ref="update-form"
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
</template>

<script>
export default {
  name: 'NotifyList',
  data() {
    return {
      loading: false,
      visible: false,
      groupList: [],
      groupForm: {
        name: '',
        index: ''
      },
      updateForm: {
        name: '',
        index: ''
      },
      rules: {
        'name': { required: true, message: '需输入分组名称', trigger: 'change' },
        'index': { required: true, type: 'number', message: '需输入数字', trigger: 'change' }
      }
    }
  },
  computed: {
    hostGroupInfo() {
      let total = this.$store.hostList.length
      let notGroupCount = this.$store.hostList.reduce((prev, next) => {
        if(!next.group) prev++
        return prev
      }, 0)
      return { total, notGroupCount }
    },
    list() {
      return this.groupList.map(item => {
        let hosts = this.$store.hostList.reduce((prev, next) => {
          if(next.group === item.id) {
            prev.count++
            prev.list.push(next)
          }
          return prev
        }, { count: 0, list: [] })
        return { ...item, hosts }
      })
    }
  },
  mounted() {
    this.getGroupList()
  },
  methods: {
    getGroupList() {
      this.loading = true
      this.$api.getGroupList()
        .then(({ data }) => {
          this.groupList = data
          this.groupForm.index = data.length
        })
        .finally(() => this.loading = false)
    },
    addGroup() {
      let formRef = this.$refs['group-form']
      formRef.validate()
        .then(() => {
          const { name, index } = this.groupForm
          this.$api.addGroup({ name, index })
            .then(() => {
              this.$message.success('success')
              this.groupForm = { name: '', index: '' }
              this.$nextTick(() => formRef.resetFields())
              this.getGroupList()
            })
        })
    },
    handleChange({ id, name, index }) {
      this.updateForm = { id, name, index }
      this.visible = true
    },
    updateGroup() {
      let formRef = this.$refs['update-form']
      formRef.validate()
        .then(() => {
          const { id, name, index } = this.updateForm
          this.$api.updateGroup(id, { name, index })
            .then(() => {
              this.$message.success('success')
              this.visible = false
              this.getGroupList()
            })
        })
    },
    deleteGroup({ id, name }) {
      this.$messageBox.confirm( `确认删除分组：${ name }`, 'Warning', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning'
      })
        .then(async () => {
          await this.$api.deleteGroup(id)
          await this.$store.getHostList()
          this.$message.success('success')
          this.getGroupList()
        })
    }
  }
}
</script>

<style lang="scss" scoped>
.host-count {
  display: block;
  width: 100px;
  text-align: center;
  font-size: 15px;
  color: #87cf63;
  cursor: pointer;
}
</style>
