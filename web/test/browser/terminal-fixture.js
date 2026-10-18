/* eslint-disable vue/one-component-per-file */
import { createApp, h, reactive, ref } from 'vue'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import TerminalWrapper from '../../src/views/terminal/components/terminal-wrapper.vue'
import { createDefaultTerminalSettings } from '../../src/utils/terminal-settings.js'

localStorage.setItem('showInfoSide', 'false')
localStorage.setItem('showSftpSide', 'false')
localStorage.setItem('showTerminalAi', 'false')
localStorage.setItem('isSingleWindowMode', new URLSearchParams(location.search).get('single') || 'false')

const tabs = reactive(['A', 'B', 'C',].map(key => ({ key, id: key, name: `Host ${ key }`, status: 'connecting' })))
const workspace = ref(null)
const settings = createDefaultTerminalSettings()
settings.behavior.statusBarEnabled = false
window.terminalFixture = { tabs, workspace, errors: [], sockets: [] }

const app = createApp({
  setup: () => () => h(TerminalWrapper, {
    ref: workspace,
    terminalTabs: tabs,
    onRemoveTab: index => tabs.splice(index, 1)
  })
})
app.use(ElementPlus)
app.component('SvgIcon', { render: () => h('span', '◇') })
app.config.globalProperties.$store = reactive({
  effectiveTerminalSettings: settings,
  terminalSettings: settings,
  isPlusActive: true,
  hostList: [], orderedHostSections: [], scriptList: [], scriptGroupList: [], suspendedSessions: [], menuSetting: {},
  getSuspendedSessions() {}
})
app.config.globalProperties.$api = { getCommand: async () => ({ data: 'echo initialized' }) }
app.config.globalProperties.$notification = () => {}
app.config.globalProperties.$message = { success() {}, error() {}, warning() {} }
app.config.errorHandler = error => window.terminalFixture.errors.push(error.stack || error.message)
app.mount('#app')
window.terminalFixture.unmount = () => app.unmount()

const style = document.createElement('style')
style.textContent = 'html,body,#app{height:100%;margin:0}body{background:#202020}#app{height:850px;padding:10px;box-sizing:border-box}'
document.head.appendChild(style)
