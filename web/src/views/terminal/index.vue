<template>
  <div class="container">
    <InfoSide
      ref="info-side"
      :token="token"
      :host="host"
      :visible="visible"
      @connect-sftp="connectSftp"
      @click-input-command="clickInputComand"
    />
    <section>
      <div class="terminals">
        <el-button class="full-screen-button" type="success" @click="handleFullScreen">
          {{ isFullScreen ? '退出全屏' : '全屏' }}
        </el-button>
        <div class="visible" @click="handleVisibleSidebar">
          <svg-icon
            name="icon-jiantou_zuoyouqiehuan"
            class="svg-icon"
          />
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
            <TerminalTab :ref="item.key" :token="token" :host="host" />
          </el-tab-pane>
        </el-tabs>
      </div>
      <div v-if="showSftp" class="sftp">
        <SftpFooter
          :token="token"
          :host="host"
          @resize="resizeTerminal"
        />
      </div>
    </section>
    <InputCommand
      v-model:show="showInputCommand"
      @input-command="handleInputCommand"
    />
  </div>
</template>

<script>
import TerminalTab from './components/terminal-tab.vue'
import InfoSide from './components/info-side.vue'
import SftpFooter from './components/sftp-footer.vue'
import InputCommand from '@/components/input-command/index.vue'

export default {
  name: 'Terminals',
  components: {
    TerminalTab,
    InfoSide,
    SftpFooter,
    InputCommand
  },
  data() {
    return {
      name: '',
      host: '',
      token: this.$store.token,
      activeTab: '',
      terminalTabs: [],
      isFullScreen: false,
      timer: null,
      showSftp: false,
      showInputCommand: false,
      visible: true
    }
  },
  computed: {
    closable() {
      return this.terminalTabs.length > 1
    }
  },
  watch: {
    showInputCommand(newVal) {
      if(!newVal) this.$refs['info-side'].inputCommandStatus = false
    }
  },
  created() {
    if (!this.token) return this.$router.push('login')
    let { host, name } = this.$route.query
    this.name = name
    this.host = host
    document.title = `${ document.title }-${ name }`
    let key = Date.now().toString()
    this.terminalTabs.push({ title: name, key })
    this.activeTab = key
    this.registryDbClick()
  },
  // mounted() {
  //   window.onbeforeunload = () => {
  //     return ''
  //   }
  // },
  methods: {
    connectSftp(flag) {
      this.showSftp = flag
      this.resizeTerminal()
    },
    clickInputComand() {
      this.showInputCommand = true
    },
    tabAdd() {
      if(this.timer) clearTimeout(this.timer)
      this.timer = setTimeout(() => {
        let { name } = this
        let title = name
        let key = Date.now().toString()
        this.terminalTabs.push({ title, key })
        this.activeTab = key
        this.registryDbClick()
      }, 200)
    },
    removeTab(removeKey) {
      let idx = this.terminalTabs.findIndex(({ key }) => removeKey === key)
      this.terminalTabs.splice(idx, 1)
      if(removeKey !== this.activeTab) return
      this.activeTab = this.terminalTabs[0].key
    },
    tabChange(key) {
      this.$refs[key][0].focusTab()
    },
    handleFullScreen() {
      if(this.isFullScreen) document.exitFullscreen()
      else document.getElementsByClassName('terminals')[0].requestFullscreen()
      this.isFullScreen = !this.isFullScreen
    },
    registryDbClick() {
      this.$nextTick(() => {
        let tabItems = Array.from(document.getElementsByClassName('el-tabs__item'))
        tabItems.forEach(item => {
          item.removeEventListener('dblclick', this.handleDblclick)
          item.addEventListener('dblclick', this.handleDblclick)
        })
      })
    },
    handleDblclick(e) {
      if(this.terminalTabs.length > 1) {
        let key = e.target.id.substring(4)
        // console.log('dblclick', key)
        this.removeTab(key)
      }
    },
    handleVisibleSidebar() {
      this.visible = !this.visible
      this.resizeTerminal()
    },
    resizeTerminal() {
      let terminals = this.$refs
      for(let terminal in terminals) {
        const { handleResize } = this.$refs[terminal][0] || {}
        handleResize && handleResize()
      }
    },
    handleInputCommand(command) {
      // console.log(command)
      this.$refs[this.activeTab][0].handleInputCommand(`${ command }\n`)
      this.showInputCommand = false
    }
  }
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
.el-tabs__nav-scroll {
  .el-tabs__nav {
    padding-left: 60px;
  }
}
.el-tabs__new-tab {
  position: absolute;
  left: 18px;
  font-size: 50px;
  z-index: 98;
  // &::before {
  //   font-family: iconfont;
  //   content: '\eb0d';
  //   font-size: 12px;
  //   font-size: 18px;
  //   position: absolute;
  //   left: -28px;
  // }
}
.el-tabs--border-card {
  height: 100%;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.el-tabs__content {
  flex: 1;
}

.el-icon.is-icon-close {
  position: absolute;
  font-size: 13px;
}
</style>