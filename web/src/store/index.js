import { defineStore, acceptHMRUpdate } from 'pinia'
import dayjs from 'dayjs'
import $api from '@/api'
import { isValidDate } from '@/utils'

const useStore = defineStore('global', {
  state: () => ({
    serviceURI: null,
    hostList: [],
    groupList: [],
    sshList: [],
    scriptList: [],
    scriptGroupList: [],
    proxyList: [],
    localScriptList: [],
    user: localStorage.getItem('user') || null,
    token: localStorage.getItem('token') || sessionStorage.getItem('token') || null,
    uid: localStorage.getItem('uid') || sessionStorage.getItem('uid') || null,
    title: '',
    isDark: false,
    menuPosition: localStorage.getItem('menuPosition') || 'left', // left | top
    menuCollapse: localStorage.getItem('menuCollapse') === 'true',
    defaultBackgroundImages: [
      'linear-gradient(-225deg, #CBBACC 0%, #2580B3 100%)',
      'linear-gradient(to top, #a18cd1 0%, #fbc2eb 100%)',
      'linear-gradient(to top, #6a85b6 0%, #bac8e0 100%)',
      'linear-gradient(to top, #7028e4 0%, #e5b2ca 100%)',
      'linear-gradient(to top, #9be15d 0%, #00e3ae 100%)',
      'linear-gradient(60deg, #abecd6 0%, #fbed96 100%)',
      'linear-gradient(-20deg, #2b5876 0%, #4e4376 100%)',
      'linear-gradient(to top, #1e3c72 0%, #1e3c72 1%, #2a5298 100%)',
      'linear-gradient(to right, #243949 0%, #517fa4 100%)',

      // 深色背景
      'linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%)', // 深蓝紫
      'linear-gradient(to right, #1a1a2e 0%, #16213e 100%)', // 深夜蓝
      'linear-gradient(to right, #0f2027 0%, #203a43 50%, #2c5364 100%)', // 深青蓝
      'linear-gradient(135deg, #141e30 0%, #243b55 100%)', // 深靛蓝
      'linear-gradient(to bottom, #000000 0%, #2c2c2c 100%)', // 纯黑到灰
      'linear-gradient(135deg, #2c1810 0%, #3d2817 100%)', // 深褐
      'linear-gradient(to bottom, #1e3a2e 0%, #0f2922 100%)', // 深绿
      'linear-gradient(to right, #2b1b3d 0%, #3a2449 100%)', // 深紫

      // 浅色背景
      'linear-gradient(120deg, #ffffff 0%, #f5f5f5 100%)', // 纯白
      'linear-gradient(120deg, #faf8f3 0%, #f0ebe1 100%)', // 柔和浅米白
      'linear-gradient(120deg, #d4e4f7 0%, #b5d3e7 100%)', // 柔和浅蓝
      'linear-gradient(to top, #e8dff5 0%, #d5c6e0 100%)', // 柔和浅紫
      'linear-gradient(135deg, #e8d5c4 0%, #d4c4b0 100%)', // 柔和浅褐
      'linear-gradient(120deg, #d5e5d5 0%, #c8dcc8 100%)', // 柔和浅绿
    ],
    // 终端配置占位
    terminalConfig: {},
    menuSetting: {
      ...{
        scriptLibrary: true,
        scriptLibraryCascader: false,
        hostGroupCascader: false
      },
      ...(localStorage.getItem('menuSetting') ? JSON.parse(localStorage.getItem('menuSetting')) : {})
    },
    plusInfo: {},
    isPlusActive: false,
    aiConfig: {},
    chatHistory: []
  }),
  actions: {
    async setJwtToken(token, isSession = true) {
      if (isSession) sessionStorage.setItem('token', token)
      else localStorage.setItem('token', token)
      this.$patch({ token })
    },
    async setUser(username, uid) {
      localStorage.setItem('user', username)
      localStorage.setItem('uid', uid)
      this.$patch({ user: username, uid })
    },
    async setTitle(title) {
      this.$patch({ title })
    },
    async removeLoginInfo() {
      localStorage.removeItem('token')
      sessionStorage.removeItem('token')
      sessionStorage.removeItem('uid')
      localStorage.removeItem('uid')
      localStorage.removeItem('user')
      this.$patch({ token: null, uid: null, user: null })
    },
    async getMainData() {
      await this.getGroupList()
      await this.getHostList()
      await this.getSSHList()
      await this.getScriptList()
      await this.getScriptGroupList()
      await this.getPlusInfo()
      await this.getProxyList()
      await this.getTerminalConfig() // 添加终端配置获取
      this.getAIConfig()
      this.getChatHistory()
    },
    async getHostList() {
      let { data: newHostList } = await $api.getHostList()
      newHostList = newHostList.map(newHostObj => {
        let { expired = null } = newHostObj
        newHostObj.expired = (isValidDate(expired)) ? dayjs(expired).format('YYYY-MM-DD') : '--'
        const oldHostObj = this.hostList.find(({ id }) => id === newHostObj.id)
        return oldHostObj ? Object.assign({}, { ...oldHostObj }, { ...newHostObj }) : newHostObj
      })
      this.$patch({ hostList: newHostList })
    },
    async getAIConfig() {
      const { data: aiConfig } = await $api.getAIConfig()
      this.$patch({ aiConfig })
    },
    async getChatHistory() {
      const { data: chatHistory } = await $api.getChatHistory()
      this.$patch({ chatHistory })
    },
    async getGroupList() {
      const { data: groupList } = await $api.getGroupList()
      this.$patch({ groupList })
    },
    async getSSHList() {
      const { data: sshList } = await $api.getSSHList()
      this.$patch({ sshList })
    },
    async getScriptList() {
      const { data: scriptList } = await $api.getScriptList()
      this.$patch({ scriptList })
    },
    async getScriptGroupList() {
      const { data: scriptGroupList } = await $api.getScriptGroupList()
      this.$patch({ scriptGroupList })
    },
    async getLocalScriptList() {
      const { data: localScriptList } = await $api.getLocalScriptList()
      this.$patch({ localScriptList })
    },
    async getProxyList() {
      const { data: proxyList } = await $api.getProxyList()
      this.$patch({ proxyList })
    },
    async getPlusInfo() {
      const { data: plusInfo = {} } = await $api.getPlusInfo()
      if (plusInfo?.expiryDate) {
        const isPlusActive = new Date(plusInfo.expiryDate) > new Date()
        this.$patch({ isPlusActive })
        if (!isPlusActive) {
          localStorage.setItem('autoReconnect', 'false')
          return
        }
        plusInfo.expiryDate = dayjs(plusInfo.expiryDate).format('YYYY-MM-DD')
        plusInfo.expiryDate?.startsWith('9999') && (plusInfo.expiryDate = '永久授权')
        this.$patch({ plusInfo })
      } else {
        this.$patch({ isPlusActive: false })
      }
      this.$patch({ plusInfo })
    },
    async getTerminalConfig() {
      try {
        const { data: terminalConfig } = await $api.getTerminalConfig()
        this.$patch({ terminalConfig })
      } catch (error) {
        console.error('获取终端配置失败:', error)
        // Fallback
        // 默认配置信息位于: server/app/controller/terminal-config.js
        this.$patch({ terminalConfig: {
          themeName: 'Afterglow',
          fontFamily: 'monospace',
          fontSize: 16,
          fontColor: '',
          cursorColor: '',
          selectionColor: '#264f78',
          background: '',
          keywordHighlight: true,
          highlightDebugMode: false,
          customHighlightRules: null,
          autoExecuteScript: false,
          autoReconnect: false,
          autoShowContextMenu: true
        } })
      }
    },
    async setTerminalSetting(setTarget = {}) {
      const newConfig = { ...this.terminalConfig, ...setTarget }
      try {
        await $api.saveTerminalConfig(newConfig)
        this.$patch({ terminalConfig: newConfig })
      } catch (error) {
        console.error('保存终端配置失败:', error)
      }
    },
    setMenuSetting(setTarget = {}) {
      let newConfig = { ...this.menuSetting, ...setTarget }
      localStorage.setItem('menuSetting', JSON.stringify(newConfig))
      this.$patch({ menuSetting: newConfig })
    },
    setTheme(isDark, animate = true) {
      // $store.setThemeConfig({ isDark: val })
      const html = document.documentElement
      let setAttribute = () => {
        if (isDark) html.setAttribute('class', 'dark')
        else html.setAttribute('class', '')
        localStorage.setItem('isDark', isDark)
        this.$patch({ isDark })
      }
      if (animate && typeof document.startViewTransition === 'function') {
        let transition = document.startViewTransition(() => {
          document.documentElement.classList.toggle('dark')
        })
        transition.ready.then(() => {
          const centerX = 0
          const centerY = window.innerHeight
          const radius = Math.hypot(
            Math.max(centerX, window.innerWidth - centerX),
            Math.max(centerY, window.innerHeight - centerY)
          )
          // console.log('radius: ', innerWidth, innerHeight, radius)
          // 自定义动画
          document.documentElement.animate(
            {
              clipPath: [
                `circle(0% at ${ centerX }px ${ centerY }px)`,
                `circle(${ radius }px at ${ centerX }px ${ centerY }px)`,
              ]
            },
            {
              duration: 500,
              pseudoElement: '::view-transition-new(root)'
            }
          )
          setAttribute()
        })
      } else {
        setAttribute()
      }
    },
    setDefaultTheme() {
      let isDark = false
      if (localStorage.getItem('isDark')) {
        isDark = localStorage.getItem('isDark') === 'true' ? true : false
      } else {
        const prefersDarkScheme = window.matchMedia('(prefers-color-scheme: dark)')
        const systemTheme = prefersDarkScheme.matches
        console.log('当前系统使用的是深色模式：', systemTheme ? '是' : '否')
        isDark = systemTheme
      }
      this.setTheme(isDark, false)
    },
    setMenuCollapse(newState = null) {
      if (newState === null) {
        newState = !this.menuCollapse
      }
      localStorage.setItem('menuCollapse', newState)
      this.$patch({ menuCollapse: newState })
    },
    setMenuPosition(position) {
      localStorage.setItem('menuPosition', position)
      this.$patch({ menuPosition: position })
    }
  }
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useStore, import.meta.hot))
}

export default useStore
