<template>
  <div class="terminal_wrap">
    <div class="terminal_top" :class="{ 'mobile': isMobileScreen }">
      <div class="left_menu">
        <el-dropdown
          ref="hostDropdownRef"
          trigger="click"
          max-height="50vh"
          class="dropdown_menu"
          :teleported="isMobileScreen"
        >
          <span class="link_text">连接<el-icon class="link_icon"><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-cascader-panel
              v-if="hostGroupCascader"
              ref="hostGroupCascaderRef"
              style="width: fit-content"
              :props="{
                expandTrigger: 'hover',
              }"
              :options="formatHostGroupList"
              @change="handleLinkHost"
            />
            <el-dropdown-menu v-else>
              <el-dropdown-item
                class="link_close_all"
                @click="handleCloseAllTab"
              >
                <span>关闭所有连接</span>
              </el-dropdown-item>
              <el-dropdown-item
                v-for="(item, index) in hostList"
                :key="index"
                @click="handleLinkHost(item)"
              >
                {{ item.name }} {{ item.host }}
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <el-dropdown
          v-if="scriptLibrary"
          ref="scriptDropdownRef"
          trigger="click"
          max-height="50vh"
          class="dropdown_menu"
          :teleported="isMobileScreen"
        >
          <span class="link_text">脚本库<el-icon class="link_icon"><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-cascader-panel
              v-if="scriptLibraryCascader"
              ref="scriptCascaderRef"
              style="width: fit-content"
              :props="{
                expandTrigger: 'hover',
              }"
              :options="formatScriptList"
              @change="handleExecScript"
            />
            <el-dropdown-menu v-else>
              <el-dropdown-item
                v-for="item in scriptList"
                :key="item.id"
                @click="handleExecScript(item)"
              >
                <span :title="item.name">{{ item.name }}</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <el-dropdown
          trigger="click"
          :teleported="isMobileScreen"
        >
          <span class="link_text">功能项<el-icon class="link_icon"><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="handleFullScreen">
                <span>全屏</span>
              </el-dropdown-item>
              <el-dropdown-item @click="showSetting = true">
                <span>本地设置</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
      <div class="right_overview">
        <div class="switch_wrap">
          <el-tooltip
            effect="dark"
            content="同步输入到所有终端"
            placement="bottom"
          >
            <el-switch
              v-model="isSyncAllSession"
              class="swtich"
              inline-prompt
              style="
                --el-switch-on-color: #13ce66;
                --el-switch-off-color: #ff4949;
              "
              active-text="同步"
              inactive-text="同步"
            />
          </el-tooltip>
        </div>
        <div v-if="!isSingleWindowMode" class="switch_wrap">
          <el-tooltip
            effect="dark"
            content="包含脚本库与长指令输入"
            placement="bottom"
          >
            <el-switch
              v-model="showFooterBar"
              class="swtich"
              inline-prompt
              style="
                --el-switch-on-color: #13ce66;
                --el-switch-off-color: #ff4949;
              "
              active-text="长指令"
              inactive-text="长指令"
              @change="changeShowFooterBar"
            />
          </el-tooltip>
        </div>
        <div v-if="!isMobileScreen" class="switch_wrap">
          <el-tooltip
            effect="dark"
            placement="bottom"
            :content="isSingleWindowMode ? '多窗口展示多个服务器终端' : '单窗口一屏展示不同的服务器终端'"
          >
            <el-switch
              v-model="isSingleWindowMode"
              class="swtich"
              inline-prompt
              style="
                --el-switch-on-color: #409eff;
                --el-switch-off-color: #13ce66;
              "
              active-text="单窗口"
              inactive-text="多窗口"
              @change="changeIsSingleWindowMode"
            />
          </el-tooltip>
        </div>
        <div v-if="!isMobileScreen && isSingleWindowMode && terminalTabs.length > 4" class="layout_mode_wrap">
          <el-radio-group v-model="layoutMode" size="small">
            <el-radio-button value="grid">一屏展示</el-radio-button>
            <el-radio-button value="scroll">横向排列</el-radio-button>
          </el-radio-group>
        </div>
      </div>
    </div>
    <!-- 单窗口模式 -->
    <div v-if="isSingleWindowMode" class="single_window_wrapper">
      <TerminalSingleWindow
        ref="singleWindowRef"
        :terminal-tabs="terminalTabs"
        :is-sync-all-session="isSyncAllSession"
        :is-plus-active="isPlusActive"
        :long-press-ctrl="longPressCtrl"
        :long-press-alt="longPressAlt"
        :layout-mode="layoutMode"
        @close-terminal="handleCloseTerminalSingle"
        @ping-data="getPingData"
        @reset-long-press="resetLongPress"
      />
    </div>

    <!-- 多窗口模式 -->
    <el-tabs
      v-else
      v-model="activeTabIndex"
      type="border-card"
      tab-position="top"
      class="tabs_container"
      @tab-remove="removeTab"
      @tab-change="tabChange"
    >
      <el-tab-pane
        v-for="(item, index) in terminalTabs"
        :key="item.key"
        :label="item.name"
        :name="index"
        :closable="true"
      >
        <template #label>
          <div class="tab_label">
            <span
              class="tab_status"
              :style="{ background: getStatusColor(item.status) }"
            />
            <span>{{ item.name }}</span>
          </div>
        </template>
        <div class="tab_content_wrap">
          <div class="tab_content_header">
            <div :class="['tab_content_wrap_header_item', { 'active': showInfoSide }]">
              <el-tooltip
                effect="dark"
                content="状态"
                placement="bottom"
              >
                <span @click="changeInfoSide">
                  <svg-icon name="icon-zhuangtai" class="icon" />
                </span>
              </el-tooltip>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': showSftpSide }]">
              <el-tooltip
                effect="dark"
                content="文件传输"
                placement="bottom"
              >
                <span @click="changeSftp">
                  <svg-icon name="icon-sftp" class="icon" />
                </span>
              </el-tooltip>
            </div>
            <!-- <div :class="['tab_content_wrap_header_item', { 'active': showSftpSide }]">
              <el-tooltip
                effect="dark"
                content="同步终端目录到SFTP"
                placement="bottom"
              >
                <span @click="() => (showSftpSide = !showSftpSide)">
                  <svg-icon name="icon-CD" class="icon" />
                </span>
              </el-tooltip>
            </div> -->
            <div :class="['tab_content_wrap_header_item', { 'active': showDockerDialog }]">
              <el-tooltip
                effect="dark"
                content="docker容器管理"
                placement="bottom"
              >
                <span @click="() => (showDockerDialog = !showDockerDialog)">
                  <svg-icon name="icon-docker" class="icon" />
                </span>
              </el-tooltip>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': getSyncCurTab(item.key) }]">
              <el-tooltip
                effect="dark"
                content="同步输入到分屏"
                placement="bottom"
              >
                <span @click="handleSyncCurTabInput">
                  <svg-icon name="icon-lianjie" class="icon" />
                </span>
              </el-tooltip>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': getSplitStatus(item.key).h }]">
              <el-tooltip
                effect="dark"
                content="左右分屏"
                placement="bottom"
              >
                <span @click="handleHorizontalScreen">
                  <svg-icon name="icon-a-06gaodufenping" class="icon" />
                </span>
              </el-tooltip>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': getSplitStatus(item.key).v }]">
              <el-tooltip
                effect="dark"
                content="上下分屏"
                placement="bottom"
              >
                <span @click="handleVerticalScreen">
                  <svg-icon name="icon-a-05kuandufenping" class="icon" />
                </span>
              </el-tooltip>
            </div>
          </div>
          <div class="tab_content_main">
            <!-- 移动端 -->
            <el-drawer
              v-if="isMobileScreen"
              v-model="showInfoSide"
              :with-header="false"
              direction="ltr"
              class="mobile_menu_drawer"
            >
              <ServerStatus
                ref="infoSideRef"
                :visible="showInfoSide"
                :host-id="item.id"
                :ping-ms="pingData[item.host] || 0"
              />
            </el-drawer>
            <!-- PC端 -->
            <div v-else :class="['tab_content_main_info_side', { 'show_info_side': showInfoSide }]">
              <ServerStatus
                ref="infoSideRef"
                :visible="showInfoSide"
                :host-id="item.id"
                :ping-ms="pingData[item.host] || 0"
              />
            </div>
            <div
              class="tab_content_main_terminals"
              :class="getSplitContainerClass(item.key)"
            >
              <template v-for="panelIndex in getTerminalCount(item.key)" :key="`${item.key}-${panelIndex}`">
                <div
                  class="terminal_item"
                  :class="getSplitItemClass(item.key, panelIndex)"
                  @click="setActiveSplit(item.key, panelIndex)"
                >
                  <!-- @cd-command="cdCommand" -->
                  <Terminal
                    ref="terminalRefs"
                    :host-obj="item"
                    :long-press-ctrl="longPressCtrl"
                    :long-press-alt="longPressAlt"
                    :auto-focus="panelIndex === 1"
                    @input-command="(cmd, uid) => terminalInput(cmd, uid)"
                    @ping-data="getPingData"
                    @reset-long-press="resetLongPress"
                    @tab-focus="handleTabFocus"
                  />
                </div>
              </template>
            </div>

            <el-drawer
              v-if="isMobileScreen"
              v-model="showSftpSide"
              :with-header="false"
              direction="rtl"
              class="mobile_menu_drawer"
            >
              <SftpV2
                :init-connect="showSftpSide"
                :host-id="item.id"
                @exec-script="handleExecScript"
              />
            </el-drawer>
            <div v-else :class="['tab_content_main_sftp', { 'show_sftp': showSftpSide }]">
              <SftpV2
                :init-connect="showSftpSide"
                :host-id="item.id"
                @exec-script="handleExecScript"
              />
            </div>
          </div>
          <div
            :class="['tab_content_footer', { 'show_footer_bar': showFooterBar }]"
            :style="showFooterBar ? { height: footerBarHeight + 'px', minHeight: footerBarHeight + 'px' } : {}"
          >
            <FooterBar
              :host-id="item.id"
              :show="showFooterBar"
              :height="footerBarHeight"
              @resize="resizeTerminal"
              @exec-script="handleExecScript"
              @height-change="handleFooterBarHeightChange"
            />
          </div>
        </div>
        <el-dialog
          v-model="showDockerDialog"
          top="20vh"
          :title="`Docker容器管理-${ item.name }`"
          :width="isMobileScreen ? '100vw' : '80vw'"
          :style="isMobileScreen ? 'max-width: 100vw;' : 'max-width: 1300px;'"
        >
          <Docker :host-id="item.id" />
        </el-dialog>
      </el-tab-pane>
    </el-tabs>

    <HostForm
      v-model:show="hostFormVisible"
      :default-data="updateHostData"
      @update-list="handleUpdateList"
      @closed="updateHostData = null"
    />

    <TerminalSetting v-model:show="showSetting" />
  </div>
</template>

<script setup>
import {
  ref,
  reactive,
  computed,
  getCurrentInstance,
  watch,
  nextTick,
  onMounted,
  onUnmounted
} from 'vue'
import { ArrowDown } from '@element-plus/icons-vue'
import useMobileWidth from '@/composables/useMobileWidth'
import { terminalStatusList } from '@/utils/enum'
import Terminal from './terminal.vue'
import ServerStatus from './server-status.vue'
import HostForm from '../../server/components/host-form.vue'
import TerminalSetting from './terminal-setting.vue'
import FooterBar from './footer-bar.vue'
import SftpV2 from './sftp-v2.vue'
import TerminalSingleWindow from './terminal-single-window.vue'
import Docker from './docker.vue'

const {
  proxy: { $nextTick, $store, $message }
} = getCurrentInstance()

const props = defineProps({
  terminalTabs: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['closed', 'close-all-tab', 'removeTab', 'add-host',])
const hostGroupAll = 'host-group-all-'
const { isMobileScreen } = useMobileWidth()
const infoSideRef = ref(null)
const pingData = ref({})
const terminalRefs = ref([])
// const sftpRefs = ref([])
const activeTabIndex = ref(0)
const isSyncAllSession = ref(false)
const isSingleWindowMode = ref(isMobileScreen.value ? false : localStorage.getItem('isSingleWindowMode') === 'true')
const layoutMode = ref(localStorage.getItem('terminalLayoutMode') || 'grid')

// 监听布局模式变化
watch(layoutMode, (newMode) => {
  localStorage.setItem('terminalLayoutMode', newMode)
})
const hostFormVisible = ref(false)
const updateHostData = ref(null)
const showSetting = ref(false)
const showInfoSide = ref(isMobileScreen.value ? false : localStorage.getItem('showInfoSide') !== 'false')
const showSftpSide = ref(isMobileScreen.value ? false : localStorage.getItem('showSftpSide') !== 'false')
const showFooterBar = ref(localStorage.getItem('showFooterBar') === 'true')
const footerBarHeight = ref(parseInt(localStorage.getItem('footerBarHeight')) || 250)
const longPressCtrl = ref(false)
const longPressAlt = ref(false)
const scriptDropdownRef = ref(null)
const scriptCascaderRef = ref(null)
const hostGroupCascaderRef = ref(null)
const hostDropdownRef = ref(null)
const singleWindowRef = ref(null)
const showDockerDialog = ref(false)

// 当前聚焦终端 uid
const focusedUid = ref(null)

const handleTabFocus = (uid) => {
  focusedUid.value = uid
}

// ======================= 同步当前tab分屏状态 =======================
const syncCurTabMap = reactive({})

const getSyncCurTab = (key) => syncCurTabMap[key] || false

const handleSyncCurTabInput = () => {
  const key = getTabKeyByIndex(activeTabIndex.value)
  if (!key) return
  syncCurTabMap[key] = !getSyncCurTab(key)
}

// ======================= 分屏面板激活状态 =======================
const activeSplitMap = reactive({})

const getActiveSplit = (key) => activeSplitMap[key] || 1

const setActiveSplit = (key, idx) => {
  activeSplitMap[key] = idx
}

const getSplitItemClass = (key, panelIndex) => {
  const classes = []
  const { h, v } = getSplitStatus(key)
  if (h && v) { // four split
    const activeIdx = getActiveSplit(key)
    if (panelIndex === activeIdx) classes.push(`active_split_${ panelIndex }`)
  }
  // for two split no special class
  return classes
}

// ======================= 分屏状态 =======================
// 每个 tab(key) 对应的分屏状态 { h: boolean, v: boolean }
const splitStatusMap = reactive({})

const getTabKeyByIndex = (idx) => terminalTabs.value[idx]?.key

const getSplitStatus = (key) => splitStatusMap[key] || { h: false, v: false }

// 计算某 tab 需要渲染的终端数量
const getTerminalCountByIndex = (idx) => {
  const key = getTabKeyByIndex(idx)
  if (!key) return 0
  const { h, v } = getSplitStatus(key)
  return (h ? 2 : 1) * (v ? 2 : 1)
}

const changeInfoSide = () => {
  showInfoSide.value = !showInfoSide.value
  localStorage.setItem('showInfoSide', showInfoSide.value)
}

const changeSftp = () => {
  showSftpSide.value = !showSftpSide.value
  localStorage.setItem('showSftpSide', showSftpSide.value)
}

const changeShowFooterBar = () => {
  localStorage.setItem('showFooterBar', showFooterBar.value)
}

const changeIsSingleWindowMode = () => {
  localStorage.setItem('isSingleWindowMode', isSingleWindowMode.value)
}

// 防抖函数
const debounce = (func, delay) => {
  let timeoutId
  return (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => func.apply(null, args), delay)
  }
}

// 防抖版本的终端尺寸重计算
const debouncedResizeTerminal = debounce(() => {
  resizeTerminal()
}, 100)

// 防抖版本的localStorage保存
const debouncedSaveToStorage = debounce((height) => {
  localStorage.setItem('footerBarHeight', height.toString())
}, 300)

const handleFooterBarHeightChange = (height) => {
  // 立即更新响应式状态（保证UI实时更新）
  footerBarHeight.value = height

  // 防抖保存到localStorage
  debouncedSaveToStorage(height)

  // 防抖触发终端尺寸重计算
  debouncedResizeTerminal()
}

const getStartIndexByTabIndex = (idx) => {
  let start = 0
  for (let i = 0; i < idx; i++) {
    start += getTerminalCountByIndex(i)
  }
  return start
}

const getTerminalRefsOfTab = (idx) => {
  const start = getStartIndexByTabIndex(idx)
  const count = getTerminalCountByIndex(idx)
  return terminalRefs.value.slice(start, start + count)
}

const getFirstTerminalRefOfTab = (idx) => getTerminalRefsOfTab(idx)[0]

// ======================= 提供给模板使用的辅助函数 =======================
const getTerminalCount = (tabKey) => {
  const { h, v } = getSplitStatus(tabKey)
  return (h ? 2 : 1) * (v ? 2 : 1)
}

const getSplitContainerClass = (tabKey) => {
  const { h, v } = getSplitStatus(tabKey)
  if (h && v) return 'four_split'
  if (h) return 'horizontal_split'
  if (v) return 'vertical_split'
  return 'single_split'
}

const isPlusActive = computed(() => $store.isPlusActive)
const terminalTabs = computed(() => props.terminalTabs)
const terminalTabsLen = computed(() => props.terminalTabs.length)
const hostGroupList = computed(() => $store.groupList)
const hostList = computed(() => $store.hostList)
const curHost = computed(() =>
  hostList.value.find(
    (item) => item.host === terminalTabs.value[activeTabIndex.value]?.host
  )
)
const scriptGroupList = computed(() => $store.scriptGroupList)
const scriptList = computed(() => $store.scriptList)
const scriptLibrary = computed(() => $store.menuSetting.scriptLibrary)
const scriptLibraryCascader = computed(
  () => $store.menuSetting.scriptLibraryCascader
)
const hostGroupCascader = computed(() => $store.menuSetting.hostGroupCascader)
const formatHostGroupList = computed(() => {
  const groupList = hostList.value.reduce((acc, item) => {
    const groupName = hostGroupList.value.find((group) => group.id === item.group)?.name
    if (!acc[groupName]) {
      acc[groupName] = []
    }
    acc[groupName].push(item)
    return acc
  }, {})
  const result = Object.entries(groupList)
    .map(([groupName, hosts,]) => {
      const children = hosts.map((host) => ({
        value: host.id,
        label: host.name
      }))
      if (hosts.length > 1) {
        children.unshift({
          value: `${ hostGroupAll }${ hosts[0].group }`,
          label: '全部连接'
        })
      }
      return {
        value: groupName,
        label: groupName,
        children
      }
    })
  result.unshift({
    value: 'closeAll',
    label: '关闭所有连接'
  })
  return result
})
const formatScriptList = computed(() => {
  const scriptsByGroup = scriptList.value.reduce((acc, script) => {
    const groupId = script.group || 'default'
    if (!acc[groupId]) {
      acc[groupId] = []
    }
    acc[groupId].push({
      value: script.id,
      label: script.name,
      command: script.command // 保存command用于执行脚本
    })
    return acc
  }, {})
  return scriptGroupList.value.map((group) => ({
    value: group.id,
    label: group.name,
    children: scriptsByGroup[group.id] || []
  }))
})

const getStatusColor = (status) => {
  return (
    terminalStatusList.find((item) => item.value === status)?.color || 'gray'
  )
}

const handleUpdateList = async ({ host }) => {
  try {
    await $store.getHostList()
    let targetHost = hostList.value.find((item) => item.host === host)
    if (targetHost) emit('add-host', targetHost)
  } catch (err) {
    $message.error('获取实例列表失败')
    console.error('获取实例列表失败: ', err)
  }
}

const handleCloseAllTab = () => {
  emit('close-all-tab')
}

const resetLongPress = () => {
  longPressCtrl.value = false
  longPressAlt.value = false
}

const handleLinkHost = (hostDescObj) => {
  if (!hostDescObj) return // clearCheckedNodes二次触发change事件
  const id = Array.isArray(hostDescObj) ? hostDescObj.slice(-1)[0] : hostDescObj.id
  if (id === 'closeAll') return handleCloseAllTab()
  if (id.startsWith(hostGroupAll)) {
    const groupId = id.split(hostGroupAll)[1]
    const hosts = hostList.value.filter((host) => host.group === groupId)
    const configHosts = hosts.filter((host) => host.isConfig)
    if (configHosts.length > 0) {
      configHosts.forEach((host) => {
        emit('add-host', host)
      })
    } else {
      $message.warning('请先配置SSH连接信息')
    }
  } else {
    const host = hostList.value.find((item) => item.id === id)
    if (!host.isConfig) {
      $message.warning('请先配置SSH连接信息')
      hostFormVisible.value = true
      updateHostData.value = { ...host }
      return
    }
    emit('add-host', host)
  }
  setTimeout(() => {
    hostGroupCascaderRef.value?.clearCheckedNodes()
    hostDropdownRef.value?.handleClose()
  }, 100)
}

// scriptDescObj: 脚本库对象或脚本命令
const handleExecScript = async (scriptDescObj) => {
  if (!scriptDescObj) return // clearCheckedNodes二次触发change事件
  let command = ''
  const id = Array.isArray(scriptDescObj) ? scriptDescObj.slice(-1)[0] : scriptDescObj?.id
  if (id) {
    const script = scriptList.value.find((item) => item.id === id)
    command = script?.command
  } else {
    command = scriptDescObj
  }
  if (!command) return $message.warning('未找到对应的脚本')

  if (!isSyncAllSession.value) {
    // 不同步时，使用 handleInputCommand（会处理分屏同步）
    await handleInputCommand(command, 'script')
  } else {
    // 同步输入到所有终端
    if (isSingleWindowMode.value) {
      // 单窗口模式：inputCommand 方法内部会处理同步逻辑
      await $nextTick()
      singleWindowRef.value?.inputCommandToTerminal(command, 'script')
    } else {
      // 多窗口模式：遍历所有终端引用
      terminalRefs.value.forEach((terminalRef) => {
        terminalRef.inputCommand(command, 'script')
      })
    }
  }

  await $nextTick()
  setTimeout(() => {
    scriptCascaderRef.value?.clearCheckedNodes()
    scriptDropdownRef.value?.handleClose()
  }, 100)
}

const terminalInput = (command, uid) => {
  const curTabKey = getTabKeyByIndex(activeTabIndex.value)
  const isSyncCurTab = getSyncCurTab(curTabKey)

  if (!isSyncAllSession.value && !isSyncCurTab) return

  let targetRefs = []
  if (isSyncAllSession.value) {
    targetRefs = terminalRefs.value
  } else if (isSyncCurTab) {
    targetRefs = getTerminalRefsOfTab(activeTabIndex.value)
  }
  targetRefs = targetRefs.filter((r) => r?.$?.uid !== uid)
  targetRefs.forEach((hostRef) => {
    hostRef.inputCommand(command, 'input')
  })
}

// 识别命令动态切换目录功能暂时取消
// const cdCommand = (path) => {
//   // console.log('cdCommand:', path)
//   if (!showSftpSide.value) return
//   if (isSyncAllSession.value) {
//     sftpRefs.value.forEach(sftpRef => {
//       sftpRef.openDir(path)
//     })
//   } else {
//     sftpRefs.value[activeTabIndex.value].openDir(path, false)
//   }
// }

const getPingData = ({ host, time }) => {
  pingData.value[host] = time
}

const tabChange = async (index) => {
  await $nextTick()
  getFirstTerminalRefOfTab(index)?.focusTab()
}

watch(
  terminalTabsLen,
  () => {
    let len = terminalTabsLen.value
    // console.log('add tab:', len)
    if (len > 0) {
      activeTabIndex.value = len - 1
      tabChange(activeTabIndex.value)
    }
  },
  {
    immediate: true,
    deep: false
  }
)

watch(
  [showFooterBar, showInfoSide, showSftpSide,],
  () => {
    setTimeout(async () => {
      resizeTerminal()
    }, 210)
  },
  {
    immediate: true,
    deep: false
  }
)

const removeTab = (index) => {
  emit('removeTab', index)
  const key = getTabKeyByIndex(index)
  if (key) {
    if (splitStatusMap[key]) delete splitStatusMap[key]
    if (syncCurTabMap[key]) delete syncCurTabMap[key]
    if (activeSplitMap[key]) delete activeSplitMap[key]
  }
  if (index === activeTabIndex.value) {
    nextTick(() => {
      activeTabIndex.value = 0
    })
  }
}

const handleFullScreen = () => {
  if (isMobileScreen.value) return
  if (document.fullscreenElement) document?.exitFullscreen()
  document
    .getElementsByClassName('terminal_wrap')[0]
    .requestFullscreen()
}

const handleHorizontalScreen = () => {
  // if (isMobileScreen.value) return $message.info('移动端暂不支持左右分屏')
  const key = getTabKeyByIndex(activeTabIndex.value)
  if (!key) return
  const status = splitStatusMap[key] || { h: false, v: false }
  splitStatusMap[key] = { ...status, h: !status.h }
  nextTick(() => {
    resizeTerminal()
    // 重新聚焦原先终端
    const ref = terminalRefs.value.find(r => r?.$?.uid === focusedUid.value)
    ref?.focusTab ? ref.focusTab() : terminalRefs.value?.[0]?.focusTab()
  })
}

const handleVerticalScreen = () => {
  // if (isMobileScreen.value) return
  const key = getTabKeyByIndex(activeTabIndex.value)
  if (!key) return
  const status = splitStatusMap[key] || { h: false, v: false }
  splitStatusMap[key] = { ...status, v: !status.v }
  nextTick(() => {
    resizeTerminal()
    // focusLastTerminalOfActive()
    const ref = terminalRefs.value.find(r => r?.$?.uid === focusedUid.value)
    ref?.focusTab ? ref.focusTab() : terminalRefs.value?.[0]?.focusTab()
  })
}

const resizeTerminal = () => {
  for (let terminalTabRef of terminalRefs.value) {
    const { handleResize } = terminalTabRef || {}
    handleResize && handleResize()
  }
}

const handleInputCommand = async (command, type = 'input') => {
  if (isSingleWindowMode.value) {
    // 单窗口模式下，使用 singleWindowRef 来执行命令
    await $nextTick()
    singleWindowRef.value?.inputCommandToTerminal(command, type)
  } else {
    // 多窗口模式下，优先使用当前聚焦的终端
    let targetTerminalRef = null

    // 首先尝试找到当前聚焦的终端
    if (focusedUid.value) {
      targetTerminalRef = terminalRefs.value.find(ref => ref?.$?.uid === focusedUid.value)
    }

    // 如果没有找到聚焦的终端，则使用当前活跃标签页的第一个终端
    if (!targetTerminalRef) {
      targetTerminalRef = getFirstTerminalRefOfTab(activeTabIndex.value)
    }

    await $nextTick()
    targetTerminalRef?.focusTab()
    targetTerminalRef?.inputCommand(command, type)

    // 处理分屏同步逻辑
    const curTabKey = getTabKeyByIndex(activeTabIndex.value)
    const isSyncCurTab = getSyncCurTab(curTabKey)

    if (isSyncCurTab) {
      // 同步到当前标签页的其他分屏终端
      const tabTerminalRefs = getTerminalRefsOfTab(activeTabIndex.value)
      const targetUid = targetTerminalRef?.$?.uid

      tabTerminalRefs.forEach((terminalRef) => {
        if (terminalRef?.$?.uid !== targetUid) {
          terminalRef.inputCommand(command, type)
        }
      })
    }
  }
}

// 单窗口模式相关函数
const handleCloseTerminalSingle = (terminalKey) => {
  const tabIndex = terminalTabs.value.findIndex(tab => tab.key === terminalKey)
  if (tabIndex !== -1) {
    emit('removeTab', tabIndex)
  }
}

const handleToFullScreen = () => {
  if (isSingleWindowMode.value) {
    const singleWindowWrapper = document.querySelector('.single_window_wrapper')
    singleWindowWrapper.style.height = 'calc(100vh - 32px)'
  } else {
    const terminalWraps = document.querySelectorAll('.tab_content_wrap')
    terminalWraps.forEach(wrap => {
      wrap.style.height = 'calc(100vh - 62px)'
    })
  }
}
const handleToNormal = () => {
  if (isSingleWindowMode.value) {
    const singleWindowWrapper = document.querySelector('.single_window_wrapper')
    singleWindowWrapper.style.height = 'calc(100vh - 115px)'
  } else {
    const terminalWraps = document.querySelectorAll('.tab_content_wrap')
    terminalWraps.forEach(wrap => {
      wrap.style.height = 'calc(100vh - 142px)'
    })
  }
}

const fullScreenCb = () => {
  if (document.fullscreenElement) {
    handleToFullScreen()
  } else {
    handleToNormal()
  }
  setTimeout(() => {
    resizeTerminal()
  }, 210)
}

watch(isSingleWindowMode, async() => {
  await $nextTick()
  if (document.fullscreenElement) fullScreenCb()
})

onMounted(() => {
  document.addEventListener('fullscreenchange', fullScreenCb)
})
onUnmounted(() => {
  document.removeEventListener('fullscreenchange', fullScreenCb)
})
</script>

<style lang="scss" scoped>
.terminal_wrap {

  :deep(.el-tabs__content) {
    padding: 0;
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
    &.mobile {
      overflow-x: scroll;
      overflow-y: auto;
      -ms-overflow-style: none; /* IE/Edge */
      scrollbar-width: none; /* Firefox */
      &::-webkit-scrollbar { display: none; }
    }
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 5px 0 15px;
    // position: sticky;
    // top: 0;
    background: var(--el-fill-color-light);
    color: var(--el-text-color-regular);
    // z-index: 3;
    user-select: none;

    // :deep(.el-dropdown) {
    //   margin-top: -2px;
    // }
    .dropdown_menu {
      :deep(.el-dropdown-menu) {
        min-width: 120px;
        max-width: 300px;
      }
    }

    .link_text {
      font-size: var(--el-font-size-base);
      color: var(--el-text-color-regular);
      white-space: nowrap;
      // color: var(--el-color-primary);
      cursor: pointer;
      margin-right: 10px;
      display: flex;
      align-items: center;
      .link_icon {
        margin-left: 5px;
      }
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
        margin-right: 16px;
      }

      .layout_mode_wrap {
        display: flex;
        align-items: center;
        margin-right: 16px;
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

  .tabs_container {
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
      flex: 1;
      height: calc(100vh - 142px);
      overflow: hidden;
      display: flex;
      flex-direction: column;
      .tab_content_header {
        height: 30px;
        min-height: 30px;
        display: flex;
        align-items: center;
        border-bottom: 1px solid var(--el-border-color);
        .tab_content_wrap_header_item {
          padding: 0 15px;
          &.active {
            color: var(--el-color-success);
          }
          .icon {
            font-size: 16px;
            cursor: pointer;
            outline: none;
          }
        }
      }
      .tab_content_main {
        flex: 1;
        min-height: 300px;
        display: flex;

        .tab_content_main_info_side {
          width: 0;
          min-width: 0;
          height: 100%;
          overflow-y: auto;
          overflow-x: hidden;
          transition: all 0.2s;
          &.show_info_side {
            width: 250px;
            min-width: 250px;
          }
        }

        .tab_content_main_terminals {
          height: 100%;
          flex: 1;
          min-width: 300px;
          display: flex;
          .terminal_item {
            box-sizing: border-box;
          }
          &.single_split {
            flex-direction: row;
            .terminal_item {
              flex: 1;
            }
          }
          &.horizontal_split {
            flex-direction: row;
            .terminal_item {
              flex: 1;
              &:not(:first-child) {
                border-left: 1px solid var(--el-color-success);
              }
            }
          }
          &.vertical_split {
            flex-direction: column;
            .terminal_item {
              flex: 1;
              &:not(:first-child) {
                border-top: 1px solid var(--el-color-success);
              }
            }
          }
          &.four_split {
            flex-wrap: wrap;
            .terminal_item {
              flex: 0 0 50%;
              height: 50%;
              box-sizing: border-box;
              border: 1px solid var(--el-border-color);
            }
            .terminal_item.active_split_1 {
              border-right: 1px solid var(--el-color-success);
              border-bottom: 1px solid var(--el-color-success);
            }
            .terminal_item.active_split_2 {
              border-left: 1px solid var(--el-color-success);
              border-bottom: 1px solid var(--el-color-success);
            }
            .terminal_item.active_split_3 {
              border-right: 1px solid var(--el-color-success);
              border-top: 1px solid var(--el-color-success);
            }
            .terminal_item.active_split_4 {
              border-left: 1px solid var(--el-color-success);
              border-top: 1px solid var(--el-color-success);
            }
          }
          .terminal_item {
            min-width: 0;
            min-height: 0;
            height: 100%;
            box-sizing: border-box;
          }
        }

        .tab_content_main_sftp {
          height: 100%;
          width: 0;
          min-width: 0;
          overflow: hidden;
          transition: all 0.2s;
          flex-shrink: 0;
          &.show_sftp {
            width: 450px;
            min-width: 450px;
            max-width: 450px;
            overflow-y: auto;
            overflow-x: hidden;
          }
        }
      }

      .tab_content_footer {
        transition: all 0.2s;
        height: 0;
        min-height: 0;
        overflow: hidden;
        &.show_footer_bar {
          overflow-x: hidden;
          overflow-y: auto;
        }
      }

    }

      .full-screen-button {
    position: absolute;
    right: 10px;
    top: 4px;
    z-index: 99999;
  }
}

.single_window_wrapper {
  height: calc(100vh - 115px);
  overflow: hidden;
  border: 1px solid var(--el-border-color);
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
  color: #ff4949 !important;
}
</style>
