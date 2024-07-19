<template>
  <div class="container">
    <InfoSide
      ref="infoSideRef"
      v-model:show-input-command="showInputCommand"
      :token="token"
      :host="host"
      :visible="visible"
      @connect-sftp="connectSftp"
      @click-input-command="clickInputCommand"
    />
    <section>
      <div class="terminals">
        <el-button class="full-screen-button" type="success" @click="handleFullScreen">
          {{ isFullScreen ? '退出全屏' : '全屏' }}
        </el-button>
        <div class="visible" @click="handleVisibleSidebar">
          <svg-icon name="icon-jiantou_zuoyouqiehuan" class="svg-icon" />
        </div>
        <el-tabs
          v-model="activeTab"
          type="border-card"
          addable
          tab-position="top"
          @tab-remove="removeTab"
          @tab-change="tabChange"
          @tab-add="tabAdd"
        >
          <el-tab-pane
            v-for="item in terminalTabs"
            :key="item.key"
            :label="item.title"
            :name="item.key"
            :closable="closable"
          >
            <TerminalTab
              ref="terminalTabRefs"
              :token="token"
              :host="host"
              :tab-key="item.key"
            />
          </el-tab-pane>
        </el-tabs>
      </div>
      <div v-if="showSftp" class="sftp">
        <SftpFooter :token="token" :host="host" @resize="resizeTerminal" />
      </div>
    </section>
    <InputCommand v-model:show="showInputCommand" @input-command="handleInputCommand" />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onBeforeMount, getCurrentInstance } from 'vue'
import TerminalTab from './components/terminal-tab.vue'
import InfoSide from './components/info-side.vue'
import SftpFooter from './components/sftp-footer.vue'
import InputCommand from '@/components/input-command/index.vue'

const { proxy: { $store, $router, $route, $nextTick } } = getCurrentInstance()

const name = ref('')
const host = ref('')
const token = $store.token
const activeTab = ref('')
const terminalTabs = reactive([])
const isFullScreen = ref(false)
const timer = ref(null)
const showSftp = ref(false)
const showInputCommand = ref(false)
const visible = ref(true)
const infoSideRef = ref(null)
const terminalTabRefs = ref([])

const closable = computed(() => terminalTabs.length > 1)

onBeforeMount(() => {
  if (!token) return $router.push('login')
  let { host: routeHost, name: routeName } = $route.query
  name.value = routeName
  host.value = routeHost
  document.title = `${ document.title }-${ routeName }`
  let key = Date.now().toString()
  terminalTabs.push({ title: routeName, key })
  activeTab.value = key
  registryDbClick()
})

// const windowBeforeUnload = () => {
//   window.onbeforeunload = () => {
//     return ''
//   }
// }

const connectSftp = (flag) => {
  showSftp.value = flag
  resizeTerminal()
}

const clickInputCommand = () => {
  showInputCommand.value = true
}

const tabAdd = () => {
  if (timer.value) clearTimeout(timer.value)
  timer.value = setTimeout(() => {
    let title = name.value
    let key = Date.now().toString()
    terminalTabs.push({ title, key })
    activeTab.value = key
    tabChange(key)
    registryDbClick()
  }, 200)
}

const removeTab = (removeKey) => {
  let idx = terminalTabs.findIndex(({ key }) => removeKey === key)
  terminalTabs.splice(idx, 1)
  if (removeKey !== activeTab.value) return
  activeTab.value = terminalTabs[0].key
}

const tabChange = async (key) => {
  await $nextTick()
  const curTabTerminal = terminalTabRefs.value.find(({ tabKey }) => key === tabKey)
  curTabTerminal?.focusTab()
}

const handleFullScreen = () => {
  if (isFullScreen.value) document.exitFullscreen()
  else document.getElementsByClassName('terminals')[0].requestFullscreen()
  isFullScreen.value = !isFullScreen.value
}

const registryDbClick = () => {
  $nextTick(() => {
    let tabItems = Array.from(document.getElementsByClassName('el-tabs__item'))
    tabItems.forEach(item => {
      item.removeEventListener('dblclick', handleDblclick)
      item.addEventListener('dblclick', handleDblclick)
    })
  })
}

const handleDblclick = (e) => {
  if (terminalTabs.length > 1) {
    let key = e.target.id.substring(4)
    // console.log('dblclick', key)
    removeTab(key)
  }
}

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
  const curTabTerminal = terminalTabRefs.value.find(({ tabKey }) => activeTab.value === tabKey)
  await $nextTick()
  curTabTerminal?.focusTab()
  curTabTerminal.handleInputCommand(`${ command }\n`)
  showInputCommand.value = false
}
</script>

<style lang="scss" scoped>
.container {
  display: flex;
  height: 100vh;

  section {
    flex: 1;
    display: flex;
    flex-direction: column;
    width: calc(100vw - 250px); // 减去左边栏

    .terminals {
      min-height: 150px;
      flex: 1;
      position: relative;

      .full-screen-button {
        position: absolute;
        right: 10px;
        top: 4px;
        z-index: 99999;
      }
    }

    .sftp {
      border: 1px solid rgb(236, 215, 187);
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
}
</style>

<style lang="scss">
.el-tabs {
  border: none;
}

.el-tabs--border-card>.el-tabs__content {
  padding: 0;
}

.el-tabs__header {
  position: sticky;
  top: 0;
  z-index: 1;
  user-select: none;
}

// .el-tabs__nav-scroll {
//   .el-tabs__nav {
//     // padding-left: 60px;
//   }
// }

.el-tabs__new-tab {
  position: absolute;
  left: 18px;
  font-size: 50px;
  z-index: 98;
}

// .el-tabs--border-card {
//   height: 100%;
//   overflow: hidden;
//   display: flex;
//   flex-direction: column;
// }

.el-tabs__content {
  flex: 1;
}

.el-icon.is-icon-close {
  font-size: 13px;
  position: absolute;
  right: 0px;
  top: 2px;
}
</style>