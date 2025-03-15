<template>
  <div ref="footerBarContainerRef" class="footer_bar_container">
    <div ref="adjustRef" class="adjust" />
    <div class="footer_bar_content">
      <el-tabs v-model="activeTab" type="border-card">
        <el-tab-pane label="文件传输" name="sftp">
          <Sftp :host-id="hostId" />
        </el-tab-pane>
        <el-tab-pane label="脚本库" name="script">
          <ScriptInput :host-id="hostId" @exec-command="execCommand" />
        </el-tab-pane>
      </el-tabs>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, nextTick } from 'vue'
import { EventBus } from '@/utils'
import Sftp from './sftp.vue'
import ScriptInput from './script-input.vue'

defineProps({
  hostId: {
    required: true,
    type: String
  }
})

const emit = defineEmits(['resize', 'exec-command',])
const footerBarContainerRef = ref(null)
const adjustRef = ref(null)
const activeTab = ref('sftp')

const adjustHeight = async () => {
  let startAdjust = false
  let timer = null
  await nextTick()
  try {
    let footerBarHeight = localStorage.getItem('footerBarHeight')
    if (footerBarHeight) footerBarContainerRef.value.style.height = footerBarHeight
    adjustRef.value.addEventListener('mousedown', () => {
      startAdjust = true
    })
    document.addEventListener('mousemove', (e) => {
      if (!startAdjust) return
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => {
        footerBarHeight = `calc(100vh - ${ e.pageY }px - 20px)`
        footerBarContainerRef.value.style.height = footerBarHeight
        emit('resize')
      })
    })
    document.addEventListener('mouseup', () => {
      if (!startAdjust) return
      startAdjust = false
      localStorage.setItem('footerBarHeight', footerBarHeight)
      EventBus.$emit('update-footer-bar-height')
    })
  } catch (error) {
    console.warn(error.message)
  }
}

const execCommand = (command) => {
  emit('exec-command', command)
}

onMounted(() => {
  adjustHeight()
  EventBus.$on('update-footer-bar-height', () => {
    adjustHeight()
  })
})
</script>

<style lang="scss" scoped>

.footer_bar_container {
  position: relative;
  background: #ffffff;
  border: 1px solid var(--el-border-color);
  min-height: 100px;
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
}
</style>

