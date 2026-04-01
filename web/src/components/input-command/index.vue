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
    <template #header>
      <div class="title">
        {{ t('terminal.multilineCommandTitle') }}
      </div>
    </template>
    <el-input
      v-model="command"
      :autosize="{ minRows: 10, maxRows: 20 }"
      type="textarea"
      :placeholder="t('terminal.multilineCommandPlaceholder')"
    />
    <template #footer>
      <footer>
        <div class="btns">
          <el-button type="primary" @click="handleSave">{{ t('terminal.sendToTerminal') }}</el-button>
          <el-button type="info" @click="visible = false">{{ t('common.close') }}</el-button>
        </div>
      </footer>
    </template>
  </el-dialog>
</template>
<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['update:show', 'closed', 'input-command',])

const command = ref('')
const { t } = useI18n()

const visible = computed({
  get() {
    return props.show
  },
  set(newVal) {
    emit('update:show', newVal)
  }
})

const handleSave = () => {
  emit('input-command', command.value)
}
</script>

<style lang="scss" scoped></style>

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
    padding: 10px !important;
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
