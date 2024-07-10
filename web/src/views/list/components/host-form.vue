<template>
  <el-dialog
    v-model="visible"
    width="400px"
    :title="title"
    :close-on-click-modal="false"
    @open="setDefaultData"
    @closed="handleClosed"
  >
    <el-form
      ref="form"
      :model="hostForm"
      :rules="rules"
      :hide-required-asterisk="true"
      label-suffix="："
      label-width="100px"
    >
      <transition-group
        name="list"
        mode="out-in"
        tag="div"
      >
        <el-form-item key="group" label="分组" prop="group">
          <el-select
            v-model="hostForm.group"
            placeholder="服务器分组"
            style="width: 100%;"
          >
            <el-option
              v-for="item in groupList"
              :key="item.id"
              :label="item.name"
              :value="item.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item key="name" label="主机别名" prop="name">
          <el-input
            v-model.trim="hostForm.name"
            clearable
            placeholder="主机别名"
            autocomplete="off"
          />
        </el-form-item>
        <el-form-item key="host" label="IP/域名" prop="host">
          <el-input
            v-model.trim="hostForm.host"
            clearable
            placeholder="IP/域名"
            autocomplete="off"
            @keyup.enter="handleSave"
          />
        </el-form-item>
        <el-form-item key="expired" label="到期时间" prop="expired">
          <el-date-picker
            v-model="hostForm.expired"
            type="date"
            value-format="x"
            placeholder="服务器到期时间"
          />
        </el-form-item>
        <el-form-item
          v-if="hostForm.expired"
          key="expiredNotify"
          label="到期提醒"
          prop="expiredNotify"
        >
          <el-tooltip content="将在服务器到期前7、3、1天发送提醒(需在设置中绑定有效邮箱)" placement="right">
            <el-switch
              v-model="hostForm.expiredNotify"
              :active-value="true"
              :inactive-value="false"
            />
          </el-tooltip>
        </el-form-item>
        <el-form-item key="consoleUrl" label="控制台URL" prop="consoleUrl">
          <el-input
            v-model.trim="hostForm.consoleUrl"
            clearable
            placeholder="用于直达服务器控制台"
            autocomplete="off"
            @keyup.enter="handleSave"
          />
        </el-form-item>
        <el-form-item key="remark" label="备注" prop="remark">
          <el-input
            v-model.trim="hostForm.remark"
            type="textarea"
            :rows="3"
            clearable
            autocomplete="off"
            placeholder="用于简单记录服务器用途"
          />
        </el-form-item>
      </transition-group>
    </el-form>
    <template #footer>
      <span class="dialog-footer">
        <el-button @click="visible = false">关闭</el-button>
        <el-button type="primary" @click="handleSave">确认</el-button>
      </span>
    </template>
  </el-dialog>
</template>

<script>
const resetForm = () => {
  return {
    group: 'default',
    name: '',
    host: '',
    expired: null,
    expiredNotify: false,
    consoleUrl: '',
    remark: ''
  }
}
export default {
  name: 'HostForm',
  props: {
    show: {
      required: true,
      type: Boolean
    },
    defaultData: {
      required: false,
      type: Object,
      default: null
    }
  },
  emits: ['update:show', 'update-list', 'closed',],
  data() {
    return {
      hostForm: resetForm(),
      oldHost: '',
      groupList: [],
      rules: {
        group: { required: true, message: '选择一个分组' },
        name: { required: true, message: '输入主机别名', trigger: 'change' },
        host: { required: true, message: '输入IP/域名', trigger: 'change' },
        expired: { required: false },
        expiredNotify: { required: false },
        consoleUrl: { required: false },
        remark: { required: false }
      }
    }
  },
  computed: {
    visible: {
      get() {
        return this.show
      },
      set(newVal) {
        this.$emit('update:show', newVal)
      }
    },
    title() {
      return this.defaultData ? '修改服务器' : '新增服务器'
    },
    formRef() {
      return this.$refs['form']
    }
  },
  watch: {
    show(newVal) {
      if(!newVal) return
      this.getGroupList()
    }
  },
  methods: {
    getGroupList() {
      this.$api.getGroupList()
        .then(({ data }) => {
          this.groupList = data
        })
    },
    handleClosed() {
      console.log('handleClosed')
      this.hostForm = resetForm()
      this.$emit('closed')
      this.$nextTick(() => this.formRef.resetFields())
    },
    setDefaultData() {
      if(!this.defaultData) return
      let { name, host, expired, expiredNotify, consoleUrl, group, remark } = this.defaultData
      this.oldHost = host // 保存旧的host用于后端查找
      this.hostForm = { name, host, expired, expiredNotify, consoleUrl, group, remark }

    },
    handleSave() {
      this.formRef.validate()
        .then(async () => {
          if(!this.hostForm.expired || !this.hostForm.expiredNotify) {
            this.hostForm.expired = null
            this.hostForm.expiredNotify = false
          }
          if(this.defaultData) {
            let { oldHost } = this
            let { msg } = await this.$api.updateHost(Object.assign({}, this.hostForm, { oldHost }))
            this.$message({ type: 'success', center: true, message: msg })
          }else {
            let { msg } = await this.$api.saveHost(this.hostForm)
            this.$message({ type: 'success', center: true, message: msg })
          }
          this.visible = false
          this.$emit('update-list')
          this.hostForm = resetForm()
        })
    }
  }
}
</script>

<style lang="scss" scoped>
.dialog-footer {
  display: flex;
  justify-content: center;
}
</style>
