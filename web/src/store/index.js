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
    ],
    terminalConfig: {
      ...{
        fontSize: 16,
        themeName: 'Afterglow',
        background: 'linear-gradient(-225deg, #CBBACC 0%, #2580B3 100%)',
        autoReconnect: true,
        autoExecuteScript: false
      },
      ...(localStorage.getItem('terminalConfig') ? JSON.parse(localStorage.getItem('terminalConfig')) : {})
    },
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
    async setUser(username) {
      localStorage.setItem('user', username)
      this.$patch({ user: username })
    },
    async setTitle(title) {
      this.$patch({ title })
    },
    async removeJwtToken() {
      localStorage.removeItem('token')
      sessionStorage.removeItem('token')
      this.$patch({ token: null })
    },
    async getMainData() {
      await this.getGroupList()
      await this.getHostList()
      await this.getSSHList()
      await this.getScriptList()
      await this.getScriptGroupList()
      await this.getPlusInfo()
      await this.getProxyList()
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
          this.setTerminalSetting({ autoReconnect: false })
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
    setTerminalSetting(setTarget = {}) {
      let newConfig = { ...this.terminalConfig, ...setTarget }
      localStorage.setItem('terminalConfig', JSON.stringify(newConfig))
      this.$patch({ terminalConfig: newConfig })
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
