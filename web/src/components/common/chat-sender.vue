<template>
  <div class="chat_sender" :class="{ 'is_dark': isDark }">
    <el-input
      ref="inputRef"
      v-model="innerValue"
      type="textarea"
      class="chat_sender_input"
      :autosize="{ minRows: 1, maxRows: 6 }"
      resize="none"
      :placeholder="placeholder"
      @keydown="handleKeydown"
    />
    <div class="chat_sender_actions">
      <el-button
        v-if="loading"
        class="action_btn"
        circle
        title="停止生成"
        @click="handleCancel"
      >
        <el-icon><VideoPause /></el-icon>
      </el-button>
      <el-button
        v-else
        class="action_btn"
        type="primary"
        circle
        :disabled="!canSubmit"
        title="发送(Enter)"
        @click="handleSubmit"
      >
        <el-icon><Top /></el-icon>
      </el-button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance } from 'vue'
import { Top, VideoPause } from '@element-plus/icons-vue'

const { proxy: { $store } } = getCurrentInstance()

const props = defineProps({
  value: {
    type: String,
    default: ''
  },
  loading: {
    type: Boolean,
    default: false
  },
  placeholder: {
    type: String,
    default: '输入问题，Enter 发送，Shift + Enter 换行'
  }
})

const emit = defineEmits(['update:value', 'submit', 'cancel',])

const inputRef = ref(null)
const isDark = computed(() => $store.isDark)

const innerValue = computed({
  get: () => props.value,
  set: (val) => emit('update:value', val)
})

const canSubmit = computed(() => Boolean(props.value.trim()))

const handleSubmit = () => {
  if (!canSubmit.value || props.loading) return
  emit('submit', props.value)
}

const handleCancel = () => emit('cancel')

// Enter 发送，Shift/Ctrl/Meta + Enter 换行；输入法组合期间不拦截
const handleKeydown = (event) => {
  if (event.key !== 'Enter') return
  if (event.isComposing || event.shiftKey || event.ctrlKey || event.metaKey) return
  event.preventDefault()
  handleSubmit()
}

const focus = () => {
  // Element Plus 的 focus 在少数嵌套/teleport 布局里只会聚焦组件包装层；
  // 终端侧栏必须直接把焦点交给原生 textarea，避免 xterm 接走键盘输入。
  inputRef.value?.textarea?.focus?.({ preventScroll: true })
  inputRef.value?.focus?.()
}

// 侧栏从隐藏状态切换到可见时，Element Plus 的 autosize 可能还按 0 宽度量过一次。
// 由宿主在最终宽度生效后调用，重新计算 textarea 的行高和高度。
const refreshLayout = () => inputRef.value?.resizeTextarea?.()

defineExpose({ focus, refreshLayout })
</script>

<style lang="scss" scoped>
.chat_sender {
  display: flex;
  align-items: flex-end;
  gap: 8px;
  padding: 6px 8px 6px 12px;
  border: 1px solid #d9d9d9;
  border-radius: 8px;
  background-color: #fff;
  transition: border-color 0.2s;

  &:focus-within {
    border-color: #1677ff;
  }

  &.is_dark {
    border-color: #454242;
    background-color: transparent;
  }

  .chat_sender_input {
    flex: 1;

    :deep(.el-textarea__inner) {
      padding: 4px 0;
      border: none;
      border-radius: 0;
      box-shadow: none;
      background-color: transparent;
      line-height: 22px;
    }
  }

  &.is_dark .chat_sender_input :deep(.el-textarea__inner) {
    color: #bbb;
  }

  .chat_sender_actions {
    display: flex;
    align-items: center;
    padding-bottom: 2px;

    .action_btn {
      width: 28px;
      height: 28px;
    }
  }
}
</style>
