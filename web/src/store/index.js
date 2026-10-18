import { defineStore, acceptHMRUpdate } from 'pinia'
import dayjs from 'dayjs'
import $api from '@/api'
import { isValidDate } from '@/utils'
import { cloneTerminalSettings, createDefaultTerminalSettings } from '@/utils/terminal-settings'

let terminalSettingsSaveQueue = Promise.resolve()

const useStore = defineStore('global', {
  state: () => ({
    hostList: [],
    panelTaskRevision: 0,
    hostCatalogLoaded: false,
    groupList: [],
    hostOrder: { schemaVersion: 1, revision: 0, sections: [], flatItemIds: [] },
    sshList: [],
    scriptList: [],
    scriptGroupList: [],
    scriptOrder: { schemaVersion: 1, revision: 0, sections: [] },
    proxyList: [],
    localScriptList: [],
    suspendedSessions: [], // 挂起的会话列表
    user: localStorage.getItem('user') || null,
    token: localStorage.getItem('token') || null,
    deviceId: localStorage.getItem('deviceId') || null,
    isDark: false,
    menuCollapse: localStorage.getItem('menuCollapse') === 'true',
    terminalSettings: createDefaultTerminalSettings(),
    terminalAppearanceDraft: null,
    // 服务器列表配置
    serverListConfig: {
      columnSettings: {
        selection: true,
        name: true,
        username: true,
        host: true,
        port: true,
        authType: true,
        proxyType: false,
        expired: false,
        consoleUrl: false,
        tag: false
      },
      displayMode: localStorage.getItem('host_list_display_mode') || 'group'
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
    aiConfig: { ui: { petEnabled: true } },
    aiConfigLoaded: false
  }),
  getters: {
    orderedHostSections(state) {
      const hostById = new Map(state.hostList.map(host => [host.id, host,]))
      const groupById = new Map(state.groupList.map(group => [group.id, group,]))
      return state.hostOrder.sections.map(section => ({
        group: groupById.get(section.groupId),
        hosts: section.itemIds.map(id => hostById.get(id)).filter(Boolean)
      })).filter(section => section.group)
    },
    effectiveTerminalSettings(state) {
      if (!state.terminalAppearanceDraft) return state.terminalSettings
      return {
        ...state.terminalSettings,
        appearance: state.terminalAppearanceDraft
      }
    }
  },
  actions: {
    async setJwtToken(token) {
      localStorage.setItem('token', token)
      this.$patch({ token })
    },
    async setUser(username, deviceId) {
      localStorage.setItem('user', username)
      localStorage.setItem('deviceId', deviceId)
      this.$patch({ user: username, deviceId })
    },
    clearLoginInfo() {
      localStorage.removeItem('token')
      localStorage.removeItem('uid')
      localStorage.removeItem('user')
      localStorage.removeItem('deviceId')
      this.$patch({ token: null, uid: null, user: null, deviceId: null })
    },
    async removeLoginInfo(removeSession = false) {
      try {
        if (removeSession && this.deviceId) {
          await $api.revokeLoginSid(this.deviceId)
        }
      } catch (err) {
        console.error('注销登录凭证失败: ', err.message)
      } finally {
        this.clearLoginInfo()
      }
    },
    async getMainData() {
      await Promise.all([
        this.getAIConfig(),
        this.getHostCatalog(),
        this.getSSHList(),
        this.getScriptCatalog(),
        this.getPlusInfo(),
        this.getProxyList(),
        this.getTerminalSettings(),
        this.getServerListConfig(),
      ])
    },
    async getHostCatalog() {
      let { data: catalog } = await $api.getHostCatalog()
      let newHostList = catalog.hosts || []
      newHostList = newHostList.map(newHostObj => {
        let { expired = null } = newHostObj
        newHostObj.expired = (isValidDate(expired)) ? dayjs(expired).format('YYYY-MM-DD') : '--'
        const oldHostObj = this.hostList.find(({ id }) => id === newHostObj.id)
        return oldHostObj ? Object.assign({}, { ...oldHostObj }, { ...newHostObj }) : newHostObj
      })
      this.$patch({
        hostList: newHostList,
        hostCatalogLoaded: true,
        groupList: catalog.groups || [],
        hostOrder: catalog.order
      })
      const savedSort = localStorage.getItem('host_table_sort')
      if (savedSort) {
        try {
          if (JSON.parse(savedSort)?.prop === 'index') localStorage.removeItem('host_table_sort')
        } catch {
          localStorage.removeItem('host_table_sort')
        }
      }
    },
    async getAIConfig() {
      try {
        const { data: aiConfig = {} } = await $api.getAIConfig()
        this.$patch({
          aiConfig: {
            ...aiConfig,
            ui: {
              ...(aiConfig.ui || {}),
              petEnabled: aiConfig.ui?.petEnabled !== false
            }
          }
        })
      } catch (error) {
        console.warn('获取 AI 配置失败:', error.message)
        this.$patch({ aiConfig: { ...this.aiConfig, ui: { ...this.aiConfig.ui, petEnabled: true } } })
      } finally {
        this.$patch({ aiConfigLoaded: true })
      }
    },
    async setAIPreferences(preferences = {}) {
      const nextPreferences = {
        ...this.aiConfig.ui,
        ...preferences
      }
      const { data = {} } = await $api.updateAIPreferences(nextPreferences)
      this.$patch({
        aiConfig: {
          ...this.aiConfig,
          ui: { ...nextPreferences, ...data }
        }
      })
      return this.aiConfig.ui
    },
    async getSSHList() {
      const { data: sshList } = await $api.getSSHList()
      this.$patch({ sshList })
    },
    async getScriptCatalog() {
      const { data: catalog } = await $api.getScriptCatalog()
      this.$patch({
        scriptList: catalog.scripts || [],
        scriptGroupList: catalog.groups || [],
        scriptOrder: catalog.order
      })
    },
    async getLocalScriptList() {
      const { data: localScriptList } = await $api.getLocalScriptList()
      this.$patch({ localScriptList })
    },
    async getProxyList() {
      const { data: proxyList } = await $api.getProxyList()
      this.$patch({ proxyList })
    },
    async getSuspendedSessions() {
      const { data: suspendedSessions } = await $api.getSuspendedSessions()
      const formattedSessions = (suspendedSessions || []).map(session => ({
        ...session,
        suspendTime: session.suspendTime ? dayjs(session.suspendTime).format('YYYY-MM-DD HH:mm:ss') : ''
      }))
      this.$patch({ suspendedSessions: formattedSessions })
    },
    async getPlusInfo() {
      const { data: plusInfo = {} } = await $api.getPlusInfo()
      this.$patch({ plusInfo })
      this.$patch({ isPlusActive: Boolean(plusInfo?.active) })
    },
    async getTerminalSettings() {
      const { data: terminalSettings } = await $api.getTerminalSettings()
      this.$patch({ terminalSettings })
    },
    async persistTerminalSettings(nextSettings) {
      const { data: savedSettings } = await $api.saveTerminalSettings(cloneTerminalSettings(nextSettings))
      this.$patch({ terminalSettings: savedSettings })
      return savedSettings
    },
    async saveTerminalSettings(nextSettings) {
      const request = () => this.persistTerminalSettings(nextSettings)
      terminalSettingsSaveQueue = terminalSettingsSaveQueue.then(request, request)
      return terminalSettingsSaveQueue
    },
    async setTerminalAppearance(appearance) {
      const request = () => {
        const nextSettings = cloneTerminalSettings(this.terminalSettings)
        nextSettings.appearance = JSON.parse(JSON.stringify(appearance))
        return this.persistTerminalSettings(nextSettings)
      }
      terminalSettingsSaveQueue = terminalSettingsSaveQueue.then(request, request)
      return terminalSettingsSaveQueue
    },
    setTerminalAppearanceDraft(appearance) {
      this.$patch({ terminalAppearanceDraft: JSON.parse(JSON.stringify(appearance)) })
    },
    clearTerminalAppearanceDraft() {
      this.$patch({ terminalAppearanceDraft: null })
    },
    async setTerminalHighlighting(setTarget = {}) {
      const request = () => {
        const nextSettings = cloneTerminalSettings(this.terminalSettings)
        nextSettings.highlighting = { ...nextSettings.highlighting, ...setTarget }
        return this.persistTerminalSettings(nextSettings)
      }
      terminalSettingsSaveQueue = terminalSettingsSaveQueue.then(request, request)
      return terminalSettingsSaveQueue
    },
    async setTerminalBehavior(setTarget = {}) {
      const request = () => {
        const nextSettings = cloneTerminalSettings(this.terminalSettings)
        nextSettings.behavior = { ...nextSettings.behavior, ...setTarget }
        return this.persistTerminalSettings(nextSettings)
      }
      terminalSettingsSaveQueue = terminalSettingsSaveQueue.then(request, request)
      return terminalSettingsSaveQueue
    },
    async getServerListConfig() {
      const { data: serverListConfig } = await $api.getServerListConfig()
      if (serverListConfig.displayMode) {
        // 将displayMode写入localStorage，避免刷新时闪烁
        localStorage.setItem('host_list_display_mode', serverListConfig.displayMode)
      }
      this.$patch({ serverListConfig })
    },
    async setServerListConfig(setTarget = {}) {
      const newConfig = { ...this.serverListConfig, ...setTarget }
      await $api.saveServerListConfig(newConfig)
      await this.getServerListConfig()
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
    }
  }
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useStore, import.meta.hot))
}

export default useStore
