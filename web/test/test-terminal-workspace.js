import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { parse, compileScript } from '@vue/compiler-sfc'
import * as Vue from 'vue'
import { useTerminalPanels } from '../src/composables/useTerminalPanels.js'
import { terminalStatus, terminalStatusList } from '../src/utils/enum.js'

// 使用 Vue 的真实渲染器和组件模板，验证 Teleport 移动不会卸载 SSH 组件。
const makeNode = type => ({ type, children: [], parent: null, style: {}, props: {} })
const body = makeNode('body')
const renderer = Vue.createRenderer({
  createElement: makeNode,
  createText: text => ({ ...makeNode('text'), text }),
  createComment: text => ({ ...makeNode('comment'), text }),
  setText: (node, text) => { node.text = text },
  setElementText: (node, text) => { node.text = text },
  parentNode: node => node.parent,
  nextSibling: node => node.parent?.children[node.parent.children.indexOf(node) + 1] || null,
  patchProp: (node, key, previous, value) => { node.props[key] = value },
  querySelector: selector => selector === 'body' ? body : null,
  insert(node, parent, anchor = null) {
    if (node.parent) node.parent.children.splice(node.parent.children.indexOf(node), 1)
    node.parent = parent
    const index = anchor ? parent.children.indexOf(anchor) : -1
    parent.children.splice(index < 0 ? parent.children.length : index, 0, node)
  },
  remove(node) {
    if (node.parent) node.parent.children.splice(node.parent.children.indexOf(node), 1)
    node.parent = null
  }
})

globalThis.localStorage = { getItem: () => null, setItem() {} }
globalThis.document = { addEventListener() {}, removeEventListener() {}, fullscreenElement: null }

const mounts = new Map()
const unmounts = []
const inputs = []
const suspended = []
const failedSuspends = new Set()
const pendingFocus = new Map()
let focusedKey = null
const flushWorkspace = async () => {
  // 等布局 watcher 完成，再模拟下一帧的 xterm focus 和 tab-focus 事件。
  for (let index = 0; index < 4; index++) await Vue.nextTick()
  while (pendingFocus.size) {
    const callbacks = [...pendingFocus.values(),]
    pendingFocus.clear()
    callbacks.forEach(callback => callback())
    for (let index = 0; index < 4; index++) await Vue.nextTick()
  }
}
const Terminal = Vue.defineComponent({
  props: ['hostObj',],
  setup(props, { expose, emit }) {
    const uid = Vue.getCurrentInstance().uid
    const key = props.hostObj.key
    Vue.onMounted(() => {
      mounts.set(key, (mounts.get(key) || 0) + 1)
      props.hostObj.status = terminalStatus.CONNECT_SUCCESS
    })
    Vue.onUnmounted(() => {
      unmounts.push(key)
      pendingFocus.delete(key)
      if (focusedKey === key) focusedKey = null
    })
    expose({
      getTabKey: () => props.hostObj.tabKey,
      getPanelKey: () => key,
      handleResize() {},
      focusTab() {
        pendingFocus.set(key, () => {
          focusedKey = key
          emit('tab-focus', uid)
        })
      },
      inputCommand: (...args) => inputs.push({ key, args }),
      suspendTerminal: async () => {
        if (failedSuspends.has(key)) return false
        suspended.push(key)
        return true
      }
    })
    return () => Vue.h('terminal', { uid, session: key })
  }
})
const Container = Vue.defineComponent({ setup: (_, { slots }) => () => Vue.h('container', slots.default?.()) })
const Empty = Vue.defineComponent({ render: () => Vue.h('empty') })
const useContextMenu = () => ({ showMenu() {} })
const useTerminalTabContextMenu = () => ({ handleTabContextMenu() {} })

function loadComponent(filename, dependencies, exposed) {
  let source = readFileSync(new URL(`../src/views/terminal/components/${ filename }`, import.meta.url), 'utf8')
  if (exposed) {
    source = source.includes('defineExpose({')
      ? source.replace('defineExpose({', `defineExpose({ ${ exposed },`)
      : source.replace('</script>', `defineExpose({ ${ exposed } })\n</script>`)
  }
  const { descriptor } = parse(source)
  const compiled = compileScript(descriptor, { id: filename, inlineTemplate: true })
  const bindings = {}
  const code = compiled.content.replace(/import\s+([\s\S]*?)\s+from\s+['"]([^'"]+)['"];?/g, (_, names, path) => {
    if (names.trim().startsWith('{')) {
      for (const specifier of names.replace(/[{}]/g, '').split(',').filter(item => item.trim())) {
        const [original, alias = original,] = specifier.trim().split(/\s+as\s+/)
        bindings[alias] = path === 'vue' ? Vue[original] : dependencies[original] || Empty
      }
    } else {
      bindings[names.trim()] = dependencies[names.trim()] || Empty
    }
    return ''
  }).replace('export default', 'return')
  return new Function(...Object.keys(bindings), code)(...Object.values(bindings))
}

const dependencies = {
  Terminal, terminalStatus, terminalStatusList, useTerminalPanels, useContextMenu, useTerminalTabContextMenu,
  useMobileWidth: () => ({ isMobileScreen: Vue.ref(false) })
}
const Single = loadComponent('terminal-single-window.vue', dependencies, 'handleExecCommand')
const Wrapper = loadComponent('terminal-wrapper.vue', { ...dependencies, TerminalSingleWindow: Single },
  'handleHorizontalScreen, handleVerticalScreen, handleSuspendTerminal, handleCloseTerminalSingle, terminalPanels, getTerminalPanels, isSingleWindowMode, singleWindowRef, activeTabIndex, terminalInstances, isSyncAllSession')
for (const initialSingle of [false, true,]) {
  globalThis.localStorage.getItem = key => key === 'isSingleWindowMode' ? String(initialSingle) : null
  mounts.clear()
  unmounts.length = 0
  inputs.length = 0
  suspended.length = 0
  const tabs = Vue.reactive([{ key: 'A', id: 'host', name: 'Host A', status: terminalStatus.CONNECTING },])
  const workspace = Vue.ref()
  const app = renderer.createApp({
    setup: () => () => Vue.h(Wrapper, {
      ref: workspace, terminalTabs: tabs,
      onRemoveTab: index => tabs.splice(index, 1)
    })
  })
  for (const name of ['el-dropdown', 'el-tabs', 'el-tab-pane', 'el-tooltip', 'el-switch', 'el-dialog', 'el-drawer', 'el-icon', 'el-button', 'el-radio-group', 'el-radio-button', 'svg-icon', 'el-cascader-panel', 'el-dropdown-item', 'el-dropdown-menu', 'el-tag',]) app.component(name, Container)
  app.config.globalProperties.$store = {
    terminalSettings: { behavior: {} }, isPlusActive: true, menuSetting: {},
    hostList: [], orderedHostSections: [], scriptList: [], scriptGroupList: [], suspendedSessions: [], getSuspendedSessions() {}
  }
  app.config.globalProperties.$message = { success() {}, warning() {}, error() {} }
  app.mount(body)
  await flushWorkspace()
  const w = workspace.value
  assert.equal(w.isSingleWindowMode, initialSingle)
  assert.ok(w.terminalInstances.A.$el.parent.props.class.includes(initialSingle ? 'terminal_content' : 'terminal_item'), '首次进入即使用保存的布局')
  w.handleHorizontalScreen()
  w.handleVerticalScreen()
  await flushWorkspace()
  const originalKeys = w.terminalPanels.map(panel => panel.key)
  assert.equal(originalKeys.length, 4)
  const instances = originalKeys.map(key => w.terminalInstances[key])

  failedSuspends.add(originalKeys[1])
  assert.equal(await w.handleSuspendTerminal(tabs[0], 0, { panelKey: originalKeys[1] }), false)
  await flushWorkspace()
  assert.equal(w.terminalPanels.length, 4, '挂起失败不删除任何分屏')
  assert.deepEqual(unmounts, [])
  failedSuspends.clear()

  for (const single of [true, false, true, false,]) {
    w.isSingleWindowMode = single
    await flushWorkspace()
    await flushWorkspace()
    assert.deepEqual(unmounts, [], '切换布局不卸载任何 SSH 组件')
    originalKeys.forEach((key, index) => {
      assert.equal(mounts.get(key), 1, '每个 shell 只创建一次')
      assert.equal(w.terminalInstances[key], instances[index], '布局复用原终端实例')
      const parentClass = w.terminalInstances[key].$el.parent.props.class
      assert.ok(parentClass.includes(single ? 'terminal_content' : 'terminal_item'), '同一个终端 DOM 移入当前布局')
    })
  }

  // 挂起非首屏、首屏，再只剩一个面板；未挂起的实例始终不变。
  for (const key of [originalKeys[1], originalKeys[0], originalKeys[2],]) {
    const focusKey = key === originalKeys[1] ? originalKeys[3] : key
    w.terminalInstances[focusKey].focusTab()
    await flushWorkspace()
    await w.handleSuspendTerminal(tabs[0], 0, { panelKey: key })
    await flushWorkspace()
    assert.equal(tabs.length, 1)
    assert.ok(!w.terminalPanels.some(panel => panel.key === key))
    assert.equal(w.terminalInstances[originalKeys[3]], instances[3])
    assert.equal(focusedKey, key === focusKey ? w.terminalPanels[0].key : focusKey, '挂起当前分屏后转移焦点，挂起其他分屏时保留焦点')
  }
  assert.deepEqual(suspended, [originalKeys[1], originalKeys[0], originalKeys[2],])
  assert.deepEqual(new Set(unmounts), new Set(suspended))

  // 原地增删数组后，单窗口脚本只发给仍存在的面板，并保留编码参数。
  tabs.push({ key: 'B', id: 'host-b', name: 'Host B', status: terminalStatus.CONNECTING })
  w.isSingleWindowMode = true
  await flushWorkspace()
  const single = w.singleWindowRef
  single.focusTerminal(originalKeys[3])
  await flushWorkspace()
  single.inputCommandToTerminal('echo encoded', 'script', true)
  assert.deepEqual(inputs.at(-1), { key: originalKeys[3], args: ['echo encoded', 'script', true,] })
  single.handleExecCommand({ terminal: { key: originalKeys[3] } }, { command: 'echo editor', useBase64: true })
  assert.deepEqual(inputs.at(-1), { key: originalKeys[3], args: ['echo editor', 'script', true,] })
  w.isSyncAllSession = true
  await flushWorkspace()
  const inputCount = inputs.length
  single.inputCommandToTerminal('echo sync', 'script', true)
  assert.deepEqual(inputs.slice(inputCount), [
    { key: originalKeys[3], args: ['echo sync', 'script', true,] },
    { key: 'B', args: ['echo sync', 'script', true,] },
  ])
  await w.handleSuspendTerminal(tabs[0], 0, { panelKey: originalKeys[3] })
  await flushWorkspace()
  assert.equal(tabs.length, 1)
  assert.equal(single.getFocusedTerminal().terminal.key, 'B')
  single.inputCommandToTerminal('echo live', 'script', true)
  assert.deepEqual(inputs.at(-1), { key: 'B', args: ['echo live', 'script', true,] })

  // 三个主机时关闭中间的非当前终端，隐藏标签页不能抢走焦点。
  tabs.push(...['C', 'D',].map(key => ({ key, id: `host-${ key }`, name: key, status: terminalStatus.CONNECTING })))
  await flushWorkspace()
  assert.equal(focusedKey, 'D', '单窗口新增连接仍自动聚焦最后一个新终端')
  single.focusTerminal('B')
  await flushWorkspace()
  w.handleCloseTerminalSingle('C')
  await flushWorkspace()
  assert.equal(focusedKey, 'B', '关闭非当前终端不改变实际输入焦点')
  assert.equal(single.getFocusedTerminal().terminal.key, 'B')
  w.isSyncAllSession = false
  await flushWorkspace()
  single.inputCommandToTerminal('echo keep-focus', 'script')
  assert.deepEqual(inputs.at(-1), { key: 'B', args: ['echo keep-focus', 'script', false,] })
  await flushWorkspace()
  await w.handleSuspendTerminal(tabs[1], 1, { panelKey: 'D' })
  await flushWorkspace()
  assert.equal(focusedKey, 'B', '挂起其他主机也不抢走焦点')
  tabs.push({ key: 'E', id: 'host-e', name: 'E', status: terminalStatus.CONNECTING })
  await flushWorkspace()
  assert.equal(focusedKey, 'E')
  w.handleCloseTerminalSingle('E')
  await flushWorkspace()
  assert.equal(focusedKey, 'B', '关闭当前单窗口终端后聚焦存活终端')
  app.unmount()
}
console.log('终端分屏挂起、布局实例复用和单窗口引用回归测试通过')
