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
          <span class="link_text">{{ t('common.connect') }}<el-icon class="link_icon"><arrow-down /></el-icon></span>
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
          ref="resumeSessionDropdownRef"
          v-model:visible="resumeSessionDropdownVisible"
          trigger="click"
          max-height="50vh"
          class="dropdown_menu"
          :teleported="isMobileScreen"
          @visible-change="handleResumeSessionDropdownChange"
        >
          <span class="link_text">{{ t('terminal.session') }}<el-icon class="link_icon"><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item v-if="suspendedSessions.length === 0" disabled>
                <span>{{ t('terminal.noSuspendedSessionsShort') }}</span>
              </el-dropdown-item>
              <el-dropdown-item
                v-for="session in suspendedSessions"
                :key="session.sessionId"
                @click="handleResumeSessionFromDropdown(session)"
              >
                <div class="session_item">
                  <span class="session_name">{{ session.hostName }}</span>
                  <el-tag
                    v-if="!session.connectionAlive"
                    type="danger"
                    size="small"
                    style="margin-left: 8px"
                  >
                    {{ t('common.disconnected') }}
                  </el-tag>
                </div>
              </el-dropdown-item>
              <el-dropdown-item divided @click="showSessionSetting = true">
                <span style="display: flex; align-items: center; gap: 5px;">
                  <el-icon><Setting /></el-icon>
                  {{ t('terminal.sessionSettings') }}
                </span>
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
          <span class="link_text">{{ t('menu.scripts') }}<el-icon class="link_icon"><arrow-down /></el-icon></span>
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
          <span class="link_text">{{ t('terminal.terminalSettingsMenu') }}<el-icon class="link_icon"><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="showSetting = true">
                <span>{{ t('terminal.basicSettings') }}</span>
              </el-dropdown-item>
              <el-dropdown-item @click="showHighlightSettings = true">
                <span>{{ t('terminal.highlightSettings') }}</span>
              </el-dropdown-item>
              <el-dropdown-item @click="showOtherSettings = true">
                <span>{{ t('terminal.otherSettings') }}</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <el-dropdown
          trigger="click"
          :teleported="isMobileScreen"
        >
          <span class="link_text">{{ t('terminal.features') }}<el-icon class="link_icon"><arrow-down /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="handleFullScreen">
                <span>{{ t('common.fullscreen') }}</span>
              </el-dropdown-item>
              <el-dropdown-item @click="showMenuOptions = true">
                <span>{{ t('terminal.menuOptions') }}</span>
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
      <div class="right_overview">
        <div class="switch_wrap">
          <el-tooltip
            effect="dark"
            :content="t('terminal.syncInputAll')"
            placement="bottom"
          >
            <el-switch
              v-model="isSyncAllSession"
              class="switch"
              inline-prompt
              style="
                --el-switch-on-color: #13ce66;
                --el-switch-off-color: #ff4949;
              "
              :active-text="t('terminal.sync')"
              :inactive-text="t('terminal.sync')"
            />
          </el-tooltip>
        </div>
        <div v-if="!isSingleWindowMode" class="switch_wrap">
          <el-tooltip
            effect="dark"
            :content="t('terminal.includesScriptLibrary')"
            placement="bottom"
          >
            <el-switch
              v-model="showFooterBar"
              class="switch"
              inline-prompt
              style="
                --el-switch-on-color: #13ce66;
                --el-switch-off-color: #ff4949;
              "
              :active-text="t('terminal.longCommand')"
              :inactive-text="t('terminal.longCommand')"
              @change="changeShowFooterBar"
            />
          </el-tooltip>
        </div>
        <div v-if="!isMobileScreen" class="switch_wrap">
          <el-tooltip
            effect="dark"
            placement="bottom"
            :content="isSingleWindowMode ? t('terminal.multiWindowModeTip') : t('terminal.singleWindowModeTip')"
          >
            <el-switch
              v-model="isSingleWindowMode"
              class="switch"
              inline-prompt
              style="
                --el-switch-on-color: #409eff;
                --el-switch-off-color: #13ce66;
              "
              :active-text="t('terminal.singleWindowMode')"
              :inactive-text="t('terminal.multiWindowMode')"
              @change="changeIsSingleWindowMode"
            />
          </el-tooltip>
        </div>
        <div v-if="!isMobileScreen && isSingleWindowMode && terminalTabs.length > 4" class="layout_mode_wrap">
          <el-radio-group v-model="layoutMode" size="small">
            <el-radio-button value="grid">{{ t('terminal.gridLayout') }}</el-radio-button>
            <el-radio-button value="scroll">{{ t('terminal.scrollLayout') }}</el-radio-button>
          </el-radio-group>
        </div>
      </div>
    </div>
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
        @suspend-terminal="handleSuspendTerminalSingleDone"
      />
    </div>

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
          <div
            class="tab_label"
            @contextmenu.prevent="handleTabContextMenu($event, item, index)"
          >
            <span
              class="tab_status"
              :style="{ background: getStatusColor(item.status) }"
            />
            <span>{{ item.name }}</span>
            <el-icon v-if="item.status === 'suspended'" class="suspended_icon" :title="t('terminal.suspended')">
              <VideoPause />
            </el-icon>
          </div>
        </template>
        <div class="tab_content_wrap">
          <div class="tab_content_header">
            <div :class="['tab_content_wrap_header_item', { 'active': showInfoSide }]">
              <span :title="t('terminal.statusPanel')" @click="changeInfoSide">
                <svg-icon name="icon-zhuangtai" class="icon" />
              </span>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': showSftpSide }]">
              <span :title="t('terminal.sftpManager')" @click="changeSftp">
                <svg-icon name="icon-sftp" class="icon" />
              </span>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': showDockerDialog }]">
              <span :title="t('terminal.dockerManager')" @click="() => (showDockerDialog = !showDockerDialog)">
                <svg-icon name="icon-docker" class="icon" />
              </span>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': getSyncCurTab(item.key) }]">
              <span :title="t('terminal.syncInputSplit')" @click="handleSyncCurTabInput">
                <svg-icon name="icon-lianjie" class="icon" />
              </span>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': getSplitStatus(item.key).h }]">
              <span :title="t('terminal.splitHorizontal')" @click="handleHorizontalScreen">
                <svg-icon name="icon-a-06gaodufenping" class="icon" />
              </span>
            </div>
            <div :class="['tab_content_wrap_header_item', { 'active': getSplitStatus(item.key).v }]">
              <span :title="t('terminal.splitVertical')" @click="handleVerticalScreen">
                <svg-icon name="icon-a-05kuandufenping" class="icon" />
              </span>
            </div>
          </div>
          <div class="tab_content_main">
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
                  <Terminal
                    ref="terminalRefs"
                    :host-obj="item"
                    :long-press-ctrl="longPressCtrl"
                    :long-press-alt="longPressAlt"
                    :auto-focus="panelIndex === 1"
                    :show-sftp-side="showSftpSide"
                    @input-command="(cmd, uid) => terminalInput(cmd, uid)"
                    @ping-data="getPingData"
                    @reset-long-press="resetLongPress"
                    @tab-focus="handleTabFocus"
                    @sync-path-to-sftp="(path) => handleSyncPathToSftp(path)"
                    @request-suspend="() => handleSuspendTerminal(item, index)"
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
                ref="sftpRefs"
                :init-connect="showSftpSide"
                :host-id="item.id"
                @exec-script="handleExecScript"
              />
            </el-drawer>
            <div
              v-else
              :class="['tab_content_main_sftp', { 'show_sftp': showSftpSide }]"
              :style="showSftpSide ? { width: sftpWidth + 'px', minWidth: sftpWidth + 'px', maxWidth: sftpWidth + 'px' } : {}"
            >
              <div
                v-if="showSftpSide"
                class="sftp_resize_handle"
                @mousedown="startResizeSftp"
              >
                <div class="sftp_resize_handle_line" />
              </div>
              <SftpV2
                ref="sftpRefs"
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
          align-center
          :title="t('terminal.dockerManagerTitle', { name: item.name })"
          :width="isMobileScreen ? '100vw' : '80vw'"
          :style="isMobileScreen ? 'max-width: 100vw;' : 'max-width: 1300px;'"
          :close-on-click-modal="false"
        >
          <Docker :host-id="item.id" :host="item.host" :visible="showDockerDialog" />
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
    <TerminalHighlightSettings v-model:show="showHighlightSettings" />
    <OtherSettings v-model:show="showOtherSettings" />
    <MenuOptions v-model:show="showMenuOptions" />
    <TerminalSessionSetting v-model:show="showSessionSetting" />
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
import { useI18n } from 'vue-i18n'
import { ArrowDown, VideoPause, Setting } from '@element-plus/icons-vue'
import useMobileWidth from '@/composables/useMobileWidth'
import { terminalStatusList, terminalStatus } from '@/utils/enum'
import { useContextMenu } from '@/composables/useContextMenu'
import { useTerminalTabContextMenu } from '@/composables/useTerminalTabContextMenu'
import Terminal from './terminal.vue'
import ServerStatus from './server-status.vue'
import HostForm from '../../server/components/host-form.vue'
import TerminalSetting from './terminal-setting.vue'
import TerminalHighlightSettings from './terminal-highlight-settings.vue'
import OtherSettings from './other-settings.vue'
import MenuOptions from './menu-options.vue'
import FooterBar from './footer-bar.vue'
import SftpV2 from './sftp-v2.vue'
import TerminalSingleWindow from './terminal-single-window.vue'
import Docker from './docker.vue'
import TerminalSessionSetting from './terminal-session-setting.vue'

const {
  proxy: { $nextTick, $store, $message }
} = getCurrentInstance()
const { t } = useI18n()

const props = defineProps({
  terminalTabs: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['closed', 'close-all-tab', 'removeTab', 'add-host',])
const hostGroupAll = 'host-group-all-'
const { isMobileScreen } = useMobileWidth()
const { showMenu } = useContextMenu()
const infoSideRef = ref(null)
const pingData = ref({})
const terminalRefs = ref([])
const activeTabIndex = ref(0)
const isSyncAllSession = ref(false)
const isSingleWindowMode = ref(isMobileScreen.value ? false : localStorage.getItem('isSingleWindowMode') === 'true')
const layoutMode = ref(localStorage.getItem('terminalLayoutMode') || 'grid')

watch(layoutMode, (newMode) => {
  localStorage.setItem('terminalLayoutMode', newMode)
})
const hostFormVisible = ref(false)
const updateHostData = ref(null)
const showSetting = ref(false)
const showHighlightSettings = ref(false)
const showOtherSettings = ref(false)
const showMenuOptions = ref(false)
const showSessionSetting = ref(false)
const showInfoSide = ref(isMobileScreen.value ? false : localStorage.getItem('showInfoSide') !== 'false')
const showSftpSide = ref(isMobileScreen.value ? false : localStorage.getItem('showSftpSide') !== 'false')
const showFooterBar = ref(localStorage.getItem('showFooterBar') === 'true')
const footerBarHeight = ref(parseInt(localStorage.getItem('footerBarHeight')) || 250)
const sftpWidth = ref(parseInt(localStorage.getItem(SFTP_WIDTH_KEY)) || 450)
const longPressCtrl = ref(false)
const longPressAlt = ref(false)
const scriptDropdownRef = ref(null)
const scriptCascaderRef = ref(null)
const hostGroupCascaderRef = ref(null)
const hostDropdownRef = ref(null)
const singleWindowRef = ref(null)
const showDockerDialog = ref(false)
const sftpRefs = ref([])
const resumeSessionDropdownRef = ref(null)
const resumeSessionDropdownVisible = ref(false)
const suspendedSessions = computed(() => $store.suspendedSessions)

const focusedUid = ref(null)

const handleTabFocus = (uid) => {
  focusedUid.value = uid
}

const syncCurTabMap = reactive({})
const getSyncCurTab = (key) => syncCurTabMap[key] || false
const handleSyncCurTabInput = () => {
  const key = getTabKeyByIndex(activeTabIndex.value)
  if (!key) return
  syncCurTabMap[key] = !getSyncCurTab(key)
}

const activeSplitMap = reactive({})
const getActiveSplit = (key) => activeSplitMap[key] || 1
const setActiveSplit = (key, idx) => {
  activeSplitMap[key] = idx
}

const getSplitItemClass = (key, panelIndex) => {
  const classes = []
  const { h, v } = getSplitStatus(key)
  if (h && v) {
    const activeIdx = getActiveSplit(key)
    if (panelIndex === activeIdx) classes.push(`active_split_${ panelIndex }`)
  }
  return classes
}

const splitStatusMap = reactive({})
const getTabKeyByIndex = (idx) => terminalTabs.value[idx]?.key
const getSplitStatus = (key) => splitStatusMap[key] || { h: false, v: false }
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

const debounce = (func, delay) => {
  let timeoutId
  return (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => func.apply(null, args), delay)
  }
}

const debouncedResizeTerminal = debounce(() => {
  resizeTerminal()
}, 100)

const debouncedSaveToStorage = debounce((height) => {
  localStorage.setItem('footerBarHeight', height.toString())
}, 300)

const handleFooterBarHeightChange = (height) => {
  footerBarHeight.value = height
  debouncedSaveToStorage(height)
  debouncedResizeTerminal()
}

const SFTP_WIDTH_KEY = 'easynode_sftp_width'
const isResizingSftp = ref(false)
const startX = ref(0)
const startWidth = ref(0)

const startResizeSftp = (e) => {
  isResizingSftp.value = true
  startX.value = e.clientX
  startWidth.value = sftpWidth.value
  document.addEventListener('mousemove', handleResizeSftp)
  document.addEventListener('mouseup', stopResizeSftp)
  document.body.style.cursor = 'ew-resize'
  document.body.style.userSelect = 'none'
  e.preventDefault()
}

const handleResizeSftp = (e) => {
  if (!isResizingSftp.value) return
  const deltaX = startX.value - e.clientX
  const newWidth = Math.max(200, Math.min(800, startWidth.value + deltaX))
  sftpWidth.value = newWidth
}

const stopResizeSftp = () => {
  isResizingSftp.value = false
  document.removeEventListener('mousemove', handleResizeSftp)
  document.removeEventListener('mouseup', stopResizeSftp)
  document.body.style.cursor = ''
  document.body.style.userSelect = ''
  localStorage.setItem(SFTP_WIDTH_KEY, sftpWidth.value.toString())
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
const hostList = computed(() => {
  if (!Array.isArray($store.hostList)) return []
  return $store.hostList.filter(item => item.connectType !== 'rdp')
})
const scriptGroupList = computed(() => $store.scriptGroupList)
const scriptList = computed(() => $store.scriptList)
const scriptLibrary = computed(() => $store.menuSetting.scriptLibrary)
const scriptLibraryCascader = computed(() => $store.menuSetting.scriptLibraryCascader)
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
          label: t('terminal.allConnect')
        })
      }
      return {
        value: groupName,
        label: groupName,
        children
      }
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
      command: script.command
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
  return terminalStatusList.find((item) => item.value === status)?.color || 'gray'
}

const handleUpdateList = async ({ host }) => {
  try {
    await $store.getHostList()
    let targetHost = hostList.value.find((item) => item.host === host)
    if (targetHost) emit('add-host', targetHost)
  } catch (err) {
    $message.error(t('common.fetchServerListFailed'))
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
  if (!hostDescObj) return
  const id = Array.isArray(hostDescObj) ? hostDescObj.slice(-1)[0] : hostDescObj.id
  if (id.startsWith(hostGroupAll)) {
    const groupId = id.split(hostGroupAll)[1]
    const hosts = hostList.value.filter((host) => host.group === groupId)
    const configHosts = hosts.filter((host) => host.isConfig)
    if (configHosts.length > 0) {
      configHosts.forEach((host) => {
        emit('add-host', host)
      })
    } else {
      $message.warning(t('terminal.reconnectRequired'))
    }
  } else {
    const host = hostList.value.find((item) => item.id === id)
    if (!host.isConfig) {
      $message.warning(t('terminal.reconnectRequired'))
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

const handleResumeSessionDropdownChange = (visible) => {
  if (visible) {
    fetchSuspendedSessions()
  }
}

const fetchSuspendedSessions = () => {
  $store.getSuspendedSessions()
}

const handleResumeSessionFromDropdown = (session) => {
  if (!session.connectionAlive) {
    $message.warning(t('terminal.sessionSshDisconnected'))
    return
  }

  const { hostId, host, sessionId } = session
  const targetHost = hostList.value.find(item => item.id === hostId)
  if (!targetHost) {
    $message.error(t('terminal.hostConfigNotFound'))
    return
  }

  const { id, name, isConfig } = targetHost
  terminalTabs.value.push({
    key: sessionId,
    id,
    name,
    host,
    status: terminalStatus.RESUMING,
    isConfig,
    resumeSessionId: sessionId
  })

  resumeSessionDropdownVisible.value = false
  resumeSessionDropdownRef.value?.handleClose()
}

const handleExecScript = async (scriptDescObj) => {
  if (!scriptDescObj) return
  let command = ''
  let useBase64 = false

  if (scriptDescObj.command !== undefined) {
    command = scriptDescObj.command
    useBase64 = scriptDescObj.useBase64 || false
  } else {
    const id = Array.isArray(scriptDescObj) ? scriptDescObj.slice(-1)[0] : scriptDescObj?.id
    if (id) {
      const script = scriptList.value.find((item) => item.id === id)
      command = script?.command
      useBase64 = script?.useBase64 || false
    } else {
      command = scriptDescObj
      useBase64 = false
    }
  }
  if (!command) return $message.warning(t('terminal.scriptNotFound'))

  if (!isSyncAllSession.value) {
    await handleInputCommand(command, 'script', useBase64)
  } else {
    if (isSingleWindowMode.value) {
      await $nextTick()
      singleWindowRef.value?.inputCommandToTerminal(command, 'script', useBase64)
    } else {
      terminalRefs.value.forEach((terminalRef) => {
        terminalRef.inputCommand(command, 'script', useBase64)
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

const getPingData = ({ host, time }) => {
  pingData.value[host] = time
}

const handleSyncPathToSftp = (path) => {
  const sftpRef = sftpRefs.value[activeTabIndex.value]
  if (sftpRef && sftpRef.switchToPath && showSftpSide.value) {
    sftpRef.switchToPath(path, false)
  }
}

const tabChange = async (index) => {
  await $nextTick()
  getFirstTerminalRefOfTab(index)?.focusTab()
}

watch(
  terminalTabsLen,
  () => {
    let len = terminalTabsLen.value
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
  const key = getTabKeyByIndex(activeTabIndex.value)
  if (!key) return
  const status = splitStatusMap[key] || { h: false, v: false }
  splitStatusMap[key] = { ...status, h: !status.h }
  nextTick(() => {
    resizeTerminal()
    const ref = terminalRefs.value.find(r => r?.$?.uid === focusedUid.value)
    ref?.focusTab ? ref.focusTab() : terminalRefs.value?.[0]?.focusTab()
  })
}

const handleVerticalScreen = () => {
  const key = getTabKeyByIndex(activeTabIndex.value)
  if (!key) return
  const status = splitStatusMap[key] || { h: false, v: false }
  splitStatusMap[key] = { ...status, v: !status.v }
  nextTick(() => {
    resizeTerminal()
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

const handleInputCommand = async (command, type = 'input', useBase64 = false) => {
  if (isSingleWindowMode.value) {
    await $nextTick()
    singleWindowRef.value?.inputCommandToTerminal(command, type, useBase64)
  } else {
    let targetTerminalRef = null
    if (focusedUid.value) {
      targetTerminalRef = terminalRefs.value.find(ref => ref?.$?.uid === focusedUid.value)
    }
    if (!targetTerminalRef) {
      targetTerminalRef = getFirstTerminalRefOfTab(activeTabIndex.value)
    }

    await $nextTick()
    targetTerminalRef?.focusTab()
    targetTerminalRef?.inputCommand(command, type, useBase64)

    const curTabKey = getTabKeyByIndex(activeTabIndex.value)
    const isSyncCurTab = getSyncCurTab(curTabKey)

    if (isSyncCurTab) {
      const tabTerminalRefs = getTerminalRefsOfTab(activeTabIndex.value)
      const targetUid = targetTerminalRef?.$?.uid

      tabTerminalRefs.forEach((terminalRef) => {
        if (terminalRef?.$?.uid !== targetUid) {
          terminalRef.inputCommand(command, type, useBase64)
        }
      })
    }
  }
}

const handleSuspendTerminal = async (item, index, { silent = false } = {}) => {
  const terminalRef = getFirstTerminalRefOfTab(index)
  if (!terminalRef) {
    if (!silent) $message.error(t('terminal.terminalRefMissing'))
    return false
  }

  const success = await terminalRef.suspendTerminal()
  if (success) {
    item.status = terminalStatus.SUSPENDED
    if (!silent) $message.success(t('terminal.terminalSuspended'))
    removeTab(index)
    fetchSuspendedSessions()
    return true
  }

  return false
}

const handleSuspendAllSessions = async () => {
  const indicesToSuspend = terminalTabs.value
    .map((tab, index) => ({ tab, index }))
    .filter(({ tab }) => tab.status === terminalStatus.CONNECT_SUCCESS)
    .map(({ index }) => index)
    .reverse()

  if (indicesToSuspend.length === 0) {
    $message.warning(t('terminal.noSuspendableSessions'))
    return
  }

  let successCount = 0
  let failCount = 0
  for (const index of indicesToSuspend) {
    const tab = terminalTabs.value[index]
    if (!tab) continue

    const ok = await handleSuspendTerminal(tab, index, { silent: true })
    if (ok) successCount += 1
    else failCount += 1
  }

  if (successCount > 0) {
    $message.success(t('terminal.suspendedSessionCount', { count: successCount }))
  }
  if (failCount > 0) {
    $message.warning(t('terminal.suspendSessionFailCount', { count: failCount }))
  }
}

const handleCloseOtherTabs = (keepIndex) => {
  const toRemove = []
  terminalTabs.value.forEach((_, index) => {
    if (index !== keepIndex) {
      toRemove.push(index)
    }
  })
  toRemove.reverse().forEach(index => {
    removeTab(index)
  })
}

const { handleTabContextMenu: _tabCtxMenu } = useTerminalTabContextMenu({
  terminalTabs,
  onSuspend: (item, index) => handleSuspendTerminal(item, index),
  onSuspendAll: () => handleSuspendAllSessions(),
  onCloseOther: (index) => handleCloseOtherTabs(index),
  onCloseAll: () => handleCloseAllTab(),
  showMenu,
  terminalStatus
})

const handleTabContextMenu = (e, item, index) => {
  _tabCtxMenu(e, item, index)
}

const handleCloseTerminalSingle = (terminalKey) => {
  const tabIndex = terminalTabs.value.findIndex(tab => tab.key === terminalKey)
  if (tabIndex !== -1) {
    emit('removeTab', tabIndex)
  }
}

const handleSuspendTerminalSingleDone = (terminalKey) => {
  const tabIndex = terminalTabs.value.findIndex(tab => tab.key === terminalKey)
  if (tabIndex !== -1) {
    emit('removeTab', tabIndex)
  }
  fetchSuspendedSessions()
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
  fetchSuspendedSessions()
})
onUnmounted(() => {
  document.removeEventListener('fullscreenchange', fullScreenCb)
  document.removeEventListener('mousemove', handleResizeSftp)
  document.removeEventListener('mouseup', stopResizeSftp)
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
      -ms-overflow-style: none;
      scrollbar-width: none;
      &::-webkit-scrollbar { display: none; }
    }
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 5px 0 15px;
    background: var(--el-fill-color-light);
    color: var(--el-text-color-regular);
    user-select: none;

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
      }

      .suspended_icon {
        margin-left: 4px;
        color: #909399;
        font-size: 14px;
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
          position: relative;
          &.show_sftp {
            overflow-y: auto;
            overflow-x: hidden;
          }

          .sftp_resize_handle {
            position: absolute;
            left: 0;
            top: 0;
            bottom: 0;
            width: 8px;
            cursor: ew-resize;
            z-index: 10;
            display: flex;
            align-items: center;
            justify-content: center;

            &:hover .sftp_resize_handle_line {
              opacity: 1;
            }

            .sftp_resize_handle_line {
              width: 2px;
              height: 40px;
              background: var(--el-color-primary);
              border-radius: 1px;
              opacity: 0;
              transition: opacity 0.2s;
            }
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

.session_item {
  display: flex;
  align-items: center;

  .session_name {
    font-weight: 500;
  }
}
</style>

