<template>
  <div class="terminal_wrap">
    <InfoSide
      ref="infoSideRef"
      v-model:show-input-command="showInputCommand"
      :host-info="curHost"
      :visible="visible"
      @click-input-command="clickInputCommand"
    />
    <div class="terminals_sftp_wrap">
      <!-- <el-button class="full-screen-button" type="success" @click="handleFullScreen">
        {{ isFullScreen ? '退出全屏' : '全屏' }}
      </el-button> -->
      <!-- <div class="visible" @click="handleVisibleSidebar">
        <svg-icon name="icon-jiantou_zuoyouqiehuan" class="svg-icon" />
      </div> -->
      <el-tabs
        v-model="activeTabIndex"
        type="border-card"
        tab-position="top"
        @tab-remove="removeTab"
        @tab-change="tabChange"
      >
        <el-tab-pane
          v-for="(item, index) in terminalTabs"
          :key="index"
          :label="item.name"
          :name="index"
          :closable="true"
        >
          <div class="tab_content_wrap" :style="{ height: mainHeight + 'px' }">
            <TerminalTab ref="terminalTabRefs" :host="item.host" />
            <Sftp :host="item.host" @resize="resizeTerminal" />
          </div>
        </el-tab-pane>
      </el-tabs>
    </div>
    <InputCommand v-model:show="showInputCommand" @input-command="handleInputCommand" />
  </div>
</template>

<script setup>
import { ref, defineEmits, computed, defineProps, getCurrentInstance, watch, onMounted } from 'vue'
import TerminalTab from './terminal-tab.vue'
import InfoSide from './info-side.vue'
import Sftp from './sftp.vue'
import InputCommand from '@/components/input-command/index.vue'

const { proxy: { $nextTick } } = getCurrentInstance()

const props = defineProps({
  terminalTabs: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['closed', 'removeTab',])

const activeTabIndex = ref(0)
// const terminalTabs = reactive([])
const isFullScreen = ref(false)
const timer = ref(null)
const showSftp = ref(false)
const showInputCommand = ref(false)
const visible = ref(true)
const infoSideRef = ref(null)
const terminalTabRefs = ref([])
let mainHeight = ref('')

const terminalTabs = computed(() => props.terminalTabs)
const terminalTabsLen = computed(() => props.terminalTabs.length)
const curHost = computed(() => terminalTabs.value[activeTabIndex.value])

// const closable = computed(() => terminalTabs.length > 1)

onMounted(() => {
  $nextTick(() => {
    mainHeight.value = document.querySelector('.terminals_sftp_wrap').offsetHeight - 45 // 45 is tab-header height+10
  })
})

const tabChange = async (index) => {
  await $nextTick()
  const curTabTerminal = terminalTabRefs.value[index]
  curTabTerminal?.focusTab()
}

watch(terminalTabsLen, () => {
  let len = terminalTabsLen.value
  console.log('add tab:', len)
  if (len > 0) {
    activeTabIndex.value = len - 1
    // registryDbClick()
    tabChange(activeTabIndex.value)
  }
}, {
  immediate: true,
  deep: false
})

// const windowBeforeUnload = () => {
//   window.onbeforeunload = () => {
//     return ''
//   }
// }

const clickInputCommand = () => {
  showInputCommand.value = true
}

const tabAdd = () => {
  if (timer.value) clearTimeout(timer.value)
  timer.value = setTimeout(() => {
    let title = name.value
    let key = Date.now().toString()
    terminalTabs.value.push({ title, key })
    activeTabIndex.value = key
    tabChange(key)
    // registryDbClick()
  }, 200)
}

const removeTab = (index) => {
  // terminalTabs.value.splice(index, 1)
  emit('removeTab', index)
  if (index !== activeTabIndex.value) return
  activeTabIndex.value = 0
}

const handleFullScreen = () => {
  if (isFullScreen.value) document.exitFullscreen()
  else document.getElementsByClassName('tab_content_wrap')[0].requestFullscreen()
  isFullScreen.value = !isFullScreen.value
}

// const registryDbClick = () => {
//   $nextTick(() => {
//     let tabItems = Array.from(document.getElementsByClassName('el-tabs__item'))
//     tabItems.forEach(item => {
//       item.removeEventListener('dblclick', handleDblclick)
//       item.addEventListener('dblclick', handleDblclick)
//     })
//   })
// }

// const handleDblclick = (e) => {
//   let key = e.target.id.substring(4)
//   removeTab(key)
// }

const handleVisibleSidebar = () => {
  visible.value = !visible.value
  resizeTerminal()
}

const resizeTerminal = () => {
  for (let terminalTabRef of terminalTabRefs.value) {
    const { handleResize } = terminalTabRef || {}
    handleResize && handleResize()
  }
}

const handleInputCommand = async (command) => {
  const curTabTerminal = terminalTabRefs.value[activeTabIndex.value]
  await $nextTick()
  curTabTerminal?.focusTab()
  curTabTerminal.handleInputCommand(`${ command }\n`)
  showInputCommand.value = false
}
</script>

<style lang="scss" scoped>
.terminal_wrap {
  display: flex;
  height: 100%;

  :deep(.el-tabs__content) {
    flex: 1;
    width: 100%;
    padding: 5px;
    padding-top: 0px;
  }

  .terminals_sftp_wrap {
    height: 100%;
    overflow: hidden;
    flex: 1;
    display: flex;
    flex-direction: column;
    position: relative;

    .tab_content_wrap {
      display: flex;
      flex-direction: column;
      justify-content: space-between;

      :deep(.terminal_tab_container) {
        flex: 1;
      }

      :deep(.sftp_tab_container) {
        height: 300px;
      }
    }

    .full-screen-button {
      position: absolute;
      right: 10px;
      top: 4px;
      z-index: 99999;
    }
  }

  .visible {
    position: absolute;
    z-index: 999999;
    top: 13px;
    left: 5px;
    cursor: pointer;
    transition: all 0.3s;

    &:hover {
      transform: scale(1.1);
    }
  }
}
</style>

<style lang="scss">
// .el-tabs {
//   border: none;
// }

// .el-tabs--border-card>.el-tabs__content {
//   padding: 0;
// }

// .el-tabs__header {
//   position: sticky;
//   top: 0;
//   z-index: 1;
//   user-select: none;
// }

// .el-tabs__nav-scroll {
//   .el-tabs__nav {
//     // padding-left: 60px;
//   }
// }

// .el-tabs__new-tab {
//   position: absolute;
//   left: 18px;
//   font-size: 50px;
//   z-index: 98;
// }

// .el-tabs--border-card {
//   height: 100%;
//   overflow: hidden;
//   display: flex;
//   flex-direction: column;
// }

// .el-icon.is-icon-close {
//   font-size: 13px;
//   position: absolute;
//   right: 0px;
//   top: 2px;
// }
</style>