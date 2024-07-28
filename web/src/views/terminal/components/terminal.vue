<template>
  <div class="terminal_wrap">
    <div class="info_box">
      <div class="top">
        <el-icon>
          <FullScreen class="full_icon" @click="handleFullScreen" />
        </el-icon>
        <el-dropdown trigger="click">
          <div class="action_wrap">
            <span class="link_host">连接<el-icon class="el-icon--right"><arrow-down /></el-icon></span>
          </div>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item v-for="(item, index) in hostList" :key="index" @click="handleCommandHost(item)">
                {{ item.name }} {{ item.host }}
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
      <InfoSide
        ref="infoSideRef"
        v-model:show-input-command="showInputCommand"
        :host-info="curHost"
        :visible="visible"
        @click-input-command="clickInputCommand"
      />
    </div>
    <div class="terminals_sftp_wrap">
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
import { ref, defineEmits, computed, defineProps, getCurrentInstance, watch, onMounted, onBeforeUnmount } from 'vue'
import { ArrowDown, FullScreen } from '@element-plus/icons-vue'
import TerminalTab from './terminal-tab.vue'
import InfoSide from './info-side.vue'
import Sftp from './sftp.vue'
import InputCommand from '@/components/input-command/index.vue'

const { proxy: { $nextTick, $store } } = getCurrentInstance()

const props = defineProps({
  terminalTabs: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['closed', 'removeTab', 'add-host',])

const activeTabIndex = ref(0)
const isFullScreen = ref(false)
const showInputCommand = ref(false)
const visible = ref(true)
const infoSideRef = ref(null)
const terminalTabRefs = ref([])
let mainHeight = ref('')

const terminalTabs = computed(() => props.terminalTabs)
const terminalTabsLen = computed(() => props.terminalTabs.length)
const curHost = computed(() => terminalTabs.value[activeTabIndex.value])
let hostList = computed(() => $store.hostList)

// const closable = computed(() => terminalTabs.length > 1)

onMounted(() => {
  handleResizeTerminalSftp()
  window.addEventListener('resize', handleResizeTerminalSftp)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResizeTerminalSftp)
})

function handleResizeTerminalSftp() {
  $nextTick(() => {
    mainHeight.value = document.querySelector('.terminals_sftp_wrap').offsetHeight - 45 // 45 is tab-header height+15
  })
}

const handleCommandHost = (host) => {
  emit('add-host', host)
}

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

const removeTab = (index) => {
  // terminalTabs.value.splice(index, 1)
  emit('removeTab', index)
  if (index !== activeTabIndex.value) return
  activeTabIndex.value = 0
}

const handleFullScreen = () => {
  if (isFullScreen.value) document.exitFullscreen()
  else document.getElementsByClassName('terminals_sftp_wrap')[0].requestFullscreen()
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
    padding: 0 5px 5px 0;
  }

  :deep(.el-tabs--border-card) {
    border: none;
  }

  :deep(.el-tabs__nav-wrap.is-scrollable.is-top) {
    display: flex;
    align-items: center;
  }

  .info_box {
    height: 100%;
    overflow: auto;
    display: flex;
    flex-direction: column;

    .top {
      height: 39px;
      flex-shrink: 0;
      position: sticky;
      top: 0px;
      z-index: 1;
      background-color: rgb(255, 255, 255);
      padding: 0 15px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      .full_icon {
        font-size: 15px;
        color: var(--el-color-primary);
        cursor: pointer;
      }
      .action_wrap {
        .link_host {
          font-size: var(--el-font-size-base);
          color: var(--el-color-primary);
          cursor: pointer;
        }
      }
    }
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
