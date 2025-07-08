<template>
  <div class="footer_bar_container">
    <div class="footer_bar_content">
      <el-tabs v-model="activeTab" type="border-card" class="footer_bar_tabs">
        <el-tab-pane label="脚本库" name="script">
          <ScriptInput :host-id="hostId" @exec-command="execCommand" />
        </el-tab-pane>
        <el-tab-pane label="容器管理" name="docker">
          <Docker v-if="show" :host-id="hostId" />
        </el-tab-pane>
        <!-- <el-tab-pane label="进程管理" name="process">
        </el-tab-pane> -->
      </el-tabs>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import ScriptInput from './script-input.vue'
import Docker from './docker.vue'

defineProps({
  hostId: {
    required: true,
    type: String
  },
  show: {
    required: true,
    type: Boolean
  }
})

const emit = defineEmits(['resize', 'exec-command',])
const activeTab = ref('script')

const execCommand = (command) => {
  emit('exec-command', command)
}

</script>

<style lang="scss" scoped>

.footer_bar_container {
  background: #ffffff;
  border: 1px solid var(--el-border-color);
  height: 100%;
  .footer_bar_content {
    height: 100%;
    background-color: var(--el-fill-color-light);
  }
  .footer_bar_tabs {
    height: 100%;
  }
}
</style>

