<template>
  <div class="script_input_container">
    <!-- 拖拽调整条 -->
    <div
      class="resize_handle"
      @mousedown="startResize"
    >
      <div class="resize_handle_line" />
    </div>

    <ScriptInput :host-id="hostId" @exec-command="execCommand" />
    <!-- <Docker v-if="show" :host-id="hostId" /> -->
  </div>
</template>

<script setup>
import { ref, onUnmounted } from 'vue'
import ScriptInput from './script-input.vue'
// import Docker from './docker.vue'

const props = defineProps({
  hostId: {
    required: true,
    type: String
  },
  show: {
    required: true,
    type: Boolean
  },
  height: {
    type: Number,
    default: 250
  }
})

const emit = defineEmits(['resize', 'exec-command', 'height-change',])

// 拖拽相关状态
const isResizing = ref(false)
const startY = ref(0)
const startHeight = ref(0)

// 开始拖拽
const startResize = (e) => {
  isResizing.value = true
  startY.value = e.clientY
  startHeight.value = props.height

  document.addEventListener('mousemove', handleResize)
  document.addEventListener('mouseup', stopResize)
  document.body.style.cursor = 'ns-resize'
  document.body.style.userSelect = 'none'
  e.preventDefault()
}

// 处理拖拽
const handleResize = (e) => {
  if (!isResizing.value) return

  const deltaY = startY.value - e.clientY // 向上拖拽为正值
  const newHeight = Math.max(250, Math.min(380, startHeight.value + deltaY)) // 最小250px，最大380px

  emit('height-change', newHeight)
}

// 停止拖拽
const stopResize = () => {
  isResizing.value = false
  document.removeEventListener('mousemove', handleResize)
  document.removeEventListener('mouseup', stopResize)
  document.body.style.cursor = ''
  document.body.style.userSelect = ''
}

const execCommand = (command) => {
  emit('exec-command', command)
}

// 清理事件监听
onUnmounted(() => {
  document.removeEventListener('mousemove', handleResize)
  document.removeEventListener('mouseup', stopResize)
})
</script>

<style lang="scss" scoped>
.script_input_container {
  position: relative;
  border: 1px solid var(--el-border-color);
  height: 100%;

  .resize_handle {
    position: absolute;
    top: -3px;
    left: 0;
    right: 0;
    height: 6px;
    cursor: ns-resize;
    z-index: 10;
    display: flex;
    align-items: center;
    justify-content: center;

    &:hover .resize_handle_line {
      height: 6px;
      background-color: var(--el-color-primary);
      opacity: 1;
    }

    .resize_handle_line {
      width: 40px;
      height: 2px;
      background-color: var(--el-border-color-darker);
      border-radius: 1px;
      opacity: 0.6;
      transition: all 0.2s;
    }
  }

  .footer_bar_content {
    height: 100%;
    background-color: var(--el-fill-color-light);
    padding-top: 3px; // 为拖拽条留出空间
  }

  .footer_bar_tabs {
    height: calc(100% - 3px); // 减去padding-top的高度
  }
}
</style>

