<template>
  <div ref="footerBarContainerRef" class="footer_bar_container">
    <!-- <div ref="adjustRef" class="adjust" /> -->
    <div class="footer_bar_content">
      <el-tabs v-model="activeTab" type="border-card" class="footer_bar_tabs">
        <!-- <el-tab-pane label="文件传输" name="sftp">
          <Sftp :host-id="hostId" />
        </el-tab-pane> -->
        <el-tab-pane label="脚本库" name="script">
          <ScriptInput :host-id="hostId" @exec-command="execCommand" />
        </el-tab-pane>
        <el-tab-pane label="容器管理" name="docker">
          <Docker :host-id="hostId" />
        </el-tab-pane>
      </el-tabs>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, nextTick, onBeforeUnmount } from 'vue'
import { EventBus } from '@/utils'
import Sftp from './sftp.vue'
import ScriptInput from './script-input.vue'
import Docker from './docker.vue'

defineProps({
  hostId: {
    required: true,
    type: String
  }
})

const emit = defineEmits(['resize', 'exec-command',])
const footerBarContainerRef = ref(null)
const adjustRef = ref(null)
const activeTab = ref('script')

const adjustHeight = async () => {
  await nextTick()

  try {
    const savedHeight = localStorage.getItem('footerBarHeight')
    if (savedHeight) {
      footerBarContainerRef.value.style.height = savedHeight
    }

    let startAdjust = false
    let timer = null

    // 清理之前的事件监听器
    const cleanup = () => {
      if (timer) {
        clearTimeout(timer)
        timer = null
      }
    }

    const handleMouseDown = () => {
      startAdjust = true
    }

    const handleMouseMove = (e) => {
      if (!startAdjust) return

      if (timer) clearTimeout(timer)
      timer = setTimeout(() => {
        const footerBarHeight = `calc(100vh - ${ e.pageY }px - 20px)`
        footerBarContainerRef.value.style.height = footerBarHeight
        timer = null
      }, 0)
    }

    const handleMouseUp = () => {
      if (!startAdjust) return
      startAdjust = false

      const currentHeight = footerBarContainerRef.value.style.height
      footerBarContainerRef.value.style.height = `${ currentHeight } !important`
      footerBarContainerRef.value.style.maxHeight = `${ currentHeight } !important`
      localStorage.setItem('footerBarHeight', currentHeight)
      EventBus.$emit('update-footer-bar-height')
      emit('resize')
      cleanup()
    }

    adjustRef.value.addEventListener('mousedown', handleMouseDown)
    document.addEventListener('mousemove', handleMouseMove)
    document.addEventListener('mouseup', handleMouseUp)

    return () => {
      cleanup()
      adjustRef.value?.removeEventListener('mousedown', handleMouseDown)
      document.removeEventListener('mousemove', handleMouseMove)
      document.removeEventListener('mouseup', handleMouseUp)
    }
  } catch (error) {
    console.warn('adjustHeight error:', error.message)
    return () => {}
  }
}

const execCommand = (command) => {
  emit('exec-command', command)
}

// 保存清理函数的引用
let cleanupAdjustHeight = null

onMounted(async () => {
  cleanupAdjustHeight = await adjustHeight()
  EventBus.$on('update-footer-bar-height', async () => {
    if (cleanupAdjustHeight) cleanupAdjustHeight()
    cleanupAdjustHeight = await adjustHeight()
  })
})

onBeforeUnmount(() => {
  if (cleanupAdjustHeight) {
    cleanupAdjustHeight()
  }
})

</script>

<style lang="scss" scoped>

.footer_bar_container {
  position: relative;
  background: #ffffff;
  border: 1px solid var(--el-border-color);
  height: 100%;
  .adjust {
    user-select: none;
    position: absolute;
    top: -3px;
    width: 100%;
    height: 5px;
    background: var(--el-color-primary);
    opacity: 0.3;
    cursor: ns-resize;
  }
  .footer_bar_content {
    width: 100%;
    height: 100%;
    background-color: var(--el-fill-color-light);
  }
  .footer_bar_tabs {
    height: 100%;
  }
}
</style>

