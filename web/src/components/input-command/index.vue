<template>
  <el-dialog
    v-model="visible"
    width="800px"
    :top="'20vh'"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :show-close="false"
    center
    custom-class="container"
  >
    <template #title>
      <div class="title">
        输入多行命令发送到终端执行
      </div>
    </template>
    <el-input
      v-model="command"
      :autosize="{ minRows: 10, maxRows: 20 }"
      type="textarea"
      placeholder="Please input command"
    />
    <template #footer>
      <footer>
        <div class="btns">
          <el-button type="primary" @click="handleSave">执行</el-button>
          <el-button type="info" @click="visible = false">关闭</el-button>
        </div>
      </footer>
    </template>
  </el-dialog>
</template>

<script>

export default {
  name: 'InputCommand',
  props: {
    show: {
      required: true,
      type: Boolean
    }
  },
  emits: ['update:show', 'closed', 'input-command',],
  data() {
    return {
      command: ''
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
    }
  },
  methods: {
    handleSave() {
      this.$emit('input-command', this.command)
    }
  }
}
</script>

<style lang="scss" scoped>
</style>

<style lang="scss">
.container {
  .el-dialog__header {
    padding: 5px 0;
    .title {
      color: #409eff;
      text-align: left;
      padding-top: 10px;
      padding-left: 10px;
      font-size: 13px;
    }
  }
  .el-dialog__body {
    padding: 10px!important;
  }
  .el-dialog__footer {
    padding: 10px 0;
  }
  footer {
    display: flex;
    align-items: center;
    padding: 0 15px;
    justify-content: space-between;
    .btns {
      width: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
    }
  }
}
</style>