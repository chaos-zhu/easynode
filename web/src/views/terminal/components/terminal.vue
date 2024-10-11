<template>
  <div class="terminal_wrap">
    <div class="terminal_top">
      <div class="left_menu">
        <el-dropdown trigger="click">
          <span class="link_text">连接管理<el-icon><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item class="link_close_all" @click="handleCloseAllTab">
                <span>关闭所有连接</span>
              </el-dropdown-item>
              <el-dropdown-item v-for="(item, index) in hostList" :key="index" @click="handleLinkHost(item)">
                {{ item.name }} {{ item.host }}
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <el-dropdown
          trigger="click"
          max-height="50vh"
          :teleported="false"
          class="scripts_menu"
        >
          <span class="link_text">脚本库<el-icon><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item v-for="item in scriptList" :key="item.id" @click="handleExecScript(item)">
                <span>{{ item.name }}</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <!-- <el-dropdown trigger="click">
          <span class="link_text">分屏<el-icon><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="handleFullScreen">
                <span>双屏</span>
              </el-dropdown-item>
              <el-dropdown-item @click="handleFullScreen">
                <span>三屏</span>
              </el-dropdown-item>
              <el-dropdown-item @click="handleFullScreen">
                <span>四屏</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown> -->
        <el-dropdown trigger="click">
          <span class="link_text">设置<el-icon><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="handleFullScreen">
                <span>启用全屏</span>
              </el-dropdown-item>
              <el-dropdown-item @click="showSetting = true">
                <span>终端设置</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
      <div class="right_overview">
        <div class="switch_wrap">
          <el-tooltip
            effect="dark"
            content="开启后同步键盘输入到所有会话"
            placement="top"
          >
            <el-switch
              v-model="isSyncAllSession"
              class="swtich"
              inline-prompt
              style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
              active-text="同步"
              inactive-text="同步"
            />
          </el-tooltip>
        </div>
        <div class="switch_wrap">
          <el-tooltip
            effect="dark"
            content="SFTP文件传输"
            placement="top"
          >
            <el-switch
              v-model="showSftp"
              class="swtich"
              inline-prompt
              style="--el-switch-on-color: #13ce66; --el-switch-off-color: #ff4949"
              active-text="SFTP"
              inactive-text="SFTP"
            />
          </el-tooltip>
        </div>
        <!-- <el-icon class="full_icon">
          <FullScreen class="icon" @click="handleFullScreen" />
        </el-icon> -->
      </div>
    </div>
    <div class="info_box">
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
          :key="item.key"
          :label="item.name"
          :name="index"
          :closable="true"
          class="el_tab_pane"
        >
          <template #label>
            <div class="tab_label">
              <span class="tab_status" :style="{ background: getStatusColor(item.status) }" />
              <span>{{ item.name }}</span>
            </div>
          </template>
          <div class="tab_content_wrap" :style="{ height: mainHeight + 'px' }">
            <TerminalTab
              ref="terminalRefs"
              :host-obj="item"
              :theme="themeObj"
              :background="terminalBackground"
              :font-size="terminalFontSize"
              @input-command="terminalInput"
              @cd-command="cdCommand"
            />
            <Sftp
              v-if="showSftp"
              ref="sftpRefs"
              :host="item.host"
              @resize="resizeTerminal"
            />
          </div>
        </el-tab-pane>
      </el-tabs>
    </div>
    <InputCommand v-model:show="showInputCommand" @input-command="handleInputCommand" />
    <HostForm
      v-model:show="hostFormVisible"
      :default-data="updateHostData"
      @update-list="handleUpdateList"
      @closed="updateHostData = null"
    />
    <TerminalSetting
      v-model:show="showSetting"
      v-model:themeName="themeName"
      v-model:background="terminalBackground"
      v-model:font-size="terminalFontSize"
      @closed="showSetting = false"
    />
  </div>
</template>

<script setup>
import { ref, computed, getCurrentInstance, watch, onMounted, onBeforeUnmount, nextTick } from 'vue'
import { ArrowDown } from '@element-plus/icons-vue'
import TerminalTab from './terminal-tab.vue'
import InfoSide from './info-side.vue'
import Sftp from './sftp.vue'
import InputCommand from '@/components/input-command/index.vue'
import HostForm from '../../server/components/host-form.vue'
import TerminalSetting from './terminal-setting.vue'
import themeList from 'xterm-theme'
import { terminalStatusList } from '@/utils/enum'

const { proxy: { $nextTick, $store, $message } } = getCurrentInstance()

const props = defineProps({
  terminalTabs: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['closed', 'close-all-tab', 'removeTab', 'add-host',])

const showInputCommand = ref(false)
const infoSideRef = ref(null)
const terminalRefs = ref([])
const sftpRefs = ref([])
const activeTabIndex = ref(0)
const visible = ref(true)
const showSftp = ref(localStorage.getItem('showSftp') === 'true')
const mainHeight = ref('')
const isSyncAllSession = ref(false)
const hostFormVisible = ref(false)
const updateHostData = ref(null)
const showSetting = ref(false)
const themeName = ref(localStorage.getItem('themeName') || 'Afterglow')
let localTerminalBackground = localStorage.getItem('terminalBackground')
const terminalBackground = ref(localTerminalBackground || '')
let localTerminalFontSize = localStorage.getItem('terminalFontSize')
const terminalFontSize = ref(Number(localTerminalFontSize) || 16)

const terminalTabs = computed(() => props.terminalTabs)
const terminalTabsLen = computed(() => props.terminalTabs.length)
const hostList = computed(() => $store.hostList)
const curHost = computed(() => hostList.value.find(item => item.host === terminalTabs.value[activeTabIndex.value]?.host))
const scriptList = computed(() => $store.scriptList)
const themeObj = computed(() => themeList[themeName.value])

watch(themeName, (newVal) => {
  console.log('update theme:', newVal)
  localStorage.setItem('themeName', newVal)
})
watch(terminalBackground, (newVal) => {
  console.log('update terminalBackground:', newVal)
  localStorage.setItem('terminalBackground', newVal)
})
watch(terminalFontSize, (newVal) => {
  console.log('update terminalFontSize:', newVal)
  localStorage.setItem('terminalFontSize', newVal)
})

onMounted(() => {
  handleResizeTerminalSftp()
  window.addEventListener('resize', handleResizeTerminalSftp)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResizeTerminalSftp)
})

const getStatusColor = (status) => {
  return terminalStatusList.find(item => item.value === status)?.color || 'gray'
}

const handleUpdateList = async ({ host }) => {
  try {
    await $store.getHostList()
    let targetHost = hostList.value.find(item => item.host === host)
    if (targetHost) emit('add-host', targetHost)
  } catch (err) {
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
  }
}

const handleResizeTerminalSftp = () => {
  $nextTick(() => {
    mainHeight.value = document.querySelector('.terminals_sftp_wrap')?.offsetHeight - 45 // 45 is tab-header height+15
  })
}

const handleLinkHost = (host) => {
  if (!host.isConfig) {
    $message.warning('请先配置SSH连接信息')
    hostFormVisible.value = true
    updateHostData.value = { ...host }
    return
  }
  emit('add-host', host)
}

const handleCloseAllTab = () => {
  emit('close-all-tab')
}

const handleExecScript = (scriptObj) => {
  let { command } = scriptObj
  command += '\n'
  if (!isSyncAllSession.value) return handleInputCommand(command)
  terminalRefs.value.forEach(terminalRef => {
    terminalRef.inputCommand(command)
  })
}

const terminalInput = (command) => {
  if (!isSyncAllSession.value) return
  let filterTerminalRefs = terminalRefs.value.filter((host, index) => {
    return index !== activeTabIndex.value
  })
  filterTerminalRefs.forEach(hostRef => {
    hostRef.inputCommand(command)
  })
}

const cdCommand = (path) => {
  // console.log('cdCommand:', path)
  if (!showSftp.value) return
  if (isSyncAllSession.value) {
    sftpRefs.value.forEach(sftpRef => {
      sftpRef.openDir(path)
    })
  } else {
    sftpRefs.value[activeTabIndex.value].openDir(path, false)
  }
}

const tabChange = async (index) => {
  await $nextTick()
  const curTerminalRef = terminalRefs.value[index]
  curTerminalRef?.focusTab()
}

watch(terminalTabsLen, () => {
  let len = terminalTabsLen.value
  // console.log('add tab:', len)
  if (len > 0) {
    activeTabIndex.value = len - 1
    // registryDbClick()
    tabChange(activeTabIndex.value)
  }
}, {
  immediate: true,
  deep: false
})

watch(showSftp, () => {
  localStorage.setItem('showSftp', showSftp.value)
  nextTick(() => {
    resizeTerminal()
  })
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
  emit('removeTab', index)
  if (index === activeTabIndex.value) {
    nextTick(() => {
      activeTabIndex.value = 0
    })
  }
}

const handleFullScreen = () => {
  document.getElementsByClassName('terminals_sftp_wrap')[0].requestFullscreen()
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

const resizeTerminal = () => {
  for (let terminalTabRef of terminalRefs.value) {
    const { handleResize } = terminalTabRef || {}
    handleResize && handleResize()
  }
}

const handleInputCommand = async (command) => {
  const curTerminalRef = terminalRefs.value[activeTabIndex.value]
  await $nextTick()
  curTerminalRef?.focusTab()
  curTerminalRef.inputCommand(`${ command }`) // \n
  showInputCommand.value = false
}
</script>

<style lang="scss" scoped>
.terminal_wrap {
  display: flex;
  flex-wrap: wrap;
  height: 100%;

  :deep(.el-tabs__content) {
    // width: 100%;
    padding: 0 0 5px 0;
  }

  :deep(.el-tabs--border-card) {
    border: none;
  }

  :deep(.el-tabs__nav-wrap.is-scrollable.is-top) {
    display: flex;
    align-items: center;
  }

  $terminalTopHeight: 30px;

  .terminal_top {
    width: 100%;
    height: $terminalTopHeight;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 15px;
    position: sticky;
    top: 0;
    background: var(--el-fill-color-light);
    color: var(--el-text-color-regular);
    z-index: 3;
    user-select: none;

    // :deep(.el-dropdown) {
    //   margin-top: -2px;
    // }
    .scripts_menu {
      :deep(.el-dropdown-menu) {
        min-width: 120px;
        max-width: 300px;
      }
    }

    .link_text {
      font-size: var(--el-font-size-base);
      color: var(--el-text-color-regular);
      // color: var(--el-color-primary);
      cursor: pointer;
      margin-right: 15px;

      .hidden_icon {
        opacity: 0;
      }
    }

    .left_menu {
      display: flex;
      align-items: center;
    }

    .right_overview {
      display: flex;
      align-items: center;
      .switch_wrap {
        display: flex;
        align-items: center;
        margin-right: 5px;
      }
      .full_icon {
        cursor: pointer;

        &:hover .icon {
          color: var(--el-color-primary);
        }
      }
    }
  }

  .info_box {
    height: calc(100% - $terminalTopHeight);
    overflow: auto;
    display: flex;
    flex-direction: column;
    border: var(--el-descriptions-table-border);
  }

  .terminals_sftp_wrap {
    height: calc(100% - $terminalTopHeight);
    overflow: hidden;
    flex: 1;
    display: flex;
    flex-direction: column;
    position: relative;
    .tab_label {
      display: flex;
      align-items: center;
      justify-content: center;
      .tab_status {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        margin-right: 5px;
        transition: all 0.5s;
        // background-color: var(--el-color-primary);
      }
    }
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

<style>
.action_icon {
  color: var(--el-color-primary);
}
.link_close_all:hover {
  color: #ff4949!important;
}
</style>