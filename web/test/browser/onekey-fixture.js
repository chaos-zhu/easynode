import { createApp, h, reactive } from 'vue'
import ElementPlus from 'element-plus'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import 'element-plus/dist/index.css'
import '../../src/assets/scss/reset.scss'
import '../../src/assets/scss/_data-page.scss'
import Onekey from '../../src/views/onekey/index.vue'

const history = Array.from({ length: 126 }, (_, index) => ({
  id: `record-${ index + 1 }`,
  name: `Record ${ String(index + 1).padStart(3, '0') }`,
  host: '127.0.0.1',
  port: 22,
  command: 'echo fixture',
  startDate: 1000 + index,
  endDate: 2000 + index,
  status: '执行成功',
  result: Array.from({ length: 60 }, (_, line) => `Output ${ index + 1 }: line ${ line }`).join('\n')
}))
history[120].result = 'long output\n'.repeat(12000)
const pending = ['A', 'B',].map(hostId => ({
  batchId: 'test-batch',
  hostId,
  name: `Live ${ hostId }`,
  host: '127.0.0.1',
  port: 22,
  command: 'echo live',
  startDate: 3000,
  status: '执行中'
}))

window.onekeyFixture = {
  errors: [],
  listRequests: [],
  outputRequests: [],
  activeOutputRequests: 0,
  maxOutputRequests: 0,
  slowPage: 0,
  failNextOutput: false,
  output(text) {
    this.socket.receive('output', pending.map(row => ({ ...row, result: text.repeat(100) })))
  },
  finish() {
    history.unshift(...pending.map(row => ({
      ...row, id: `saved-${ row.hostId }`, status: '执行成功', endDate: 4000, result: 'finished'
    })))
    this.socket.receive('exec_complete')
    this.socket.disconnect()
  }
}

const app = createApp({
  setup: () => () => h('div', { class: 'view_container' }, [
    h('main', { class: 'main_container' }, [h(Onekey, { class: 'router_box' }),]),
  ])
})
app.use(ElementPlus, { locale: zhCn })
app.config.globalProperties.$store = reactive({
  token: 'fixture-token',
  hostList: pending.map(row => ({ id: row.hostId, name: row.name, isConfig: true })),
  scriptList: []
})
app.config.globalProperties.$api = {
  getOnekeyRecord: async ({ page: requestedPage, pageSize }) => {
    window.onekeyFixture.listRequests.push({ page: requestedPage, pageSize })
    const page = Math.min(requestedPage, Math.max(1, Math.ceil(history.length / pageSize)))
    const items = history.slice((page - 1) * pageSize, page * pageSize)
      .map(row => Object.fromEntries(Object.entries(row).filter(([key,]) => key !== 'result')))
    const response = { data: { items, total: history.length, page, pageSize } }
    if (requestedPage === window.onekeyFixture.slowPage) await new Promise(resolve => setTimeout(resolve, 250))
    return response
  },
  getOnekeyRecordOutput: async (id, { offset = 0 }) => {
    const fixture = window.onekeyFixture
    fixture.outputRequests.push({ id, offset })
    fixture.maxOutputRequests = Math.max(fixture.maxOutputRequests, ++fixture.activeOutputRequests)
    try {
      await new Promise(resolve => setTimeout(resolve, 30))
      if (fixture.failNextOutput) {
        fixture.failNextOutput = false
        throw new Error('Simulated output failure')
      }
      const result = history.find(row => row.id === id)?.result || ''
      const nextOffset = Math.min(offset + 64 * 1024, result.length)
      return { data: { result: result.slice(offset, nextOffset), nextOffset, hasMore: nextOffset < result.length } }
    } finally {
      fixture.activeOutputRequests--
    }
  },
  deleteOnekeyRecord: async ids => {
    for (let index = history.length - 1; index >= 0; index--) {
      if (ids === 'ALL' || ids.includes(history[index].id)) history.splice(index, 1)
    }
  }
}
app.config.globalProperties.$tools = { formatTimestamp: value => String(value) }
app.config.globalProperties.$messageBox = { confirm: async () => {} }
app.config.globalProperties.$message = { success() {}, error() {}, warning() {} }
app.config.globalProperties.$notification = () => {}
app.config.errorHandler = error => window.onekeyFixture.errors.push(error.stack || error.message)
app.mount('#app')
window.onekeyFixture.unmount = () => app.unmount()

// 与主布局相同的高度约束，避免由测试页面的整体滚动掩盖表格裁剪问题。
const style = document.createElement('style')
style.textContent = `
  .view_container { height: 100vh; display: flex; overflow: hidden; }
  .main_container { min-width: 0; min-height: 0; flex: 1; display: flex; flex-direction: column; overflow: hidden; }
  .router_box { min-height: 0; flex: 1; margin: 10px; overflow-y: auto; }
`
document.head.appendChild(style)
