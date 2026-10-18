import { computed, reactive, watch } from 'vue'
import { terminalStatus } from '../utils/enum.js'

// 布局与 SSH 会话分离：面板增删使用稳定 key，移动布局不会创建新会话。
export function useTerminalPanels(tabs) {
  const panelsByTab = reactive({})
  let sequence = 0

  const createPanel = (tab, first = false) => ({
    ...tab,
    key: first ? tab.key : `${ tab.key }:split:${ ++sequence }`,
    tabKey: tab.key,
    status: tab.resumeSessionId && first ? terminalStatus.RESUMING : terminalStatus.CONNECTING,
    resumeSessionId: first ? tab.resumeSessionId : undefined
  })

  watch(() => tabs.value.map(tab => tab.key), (keys) => {
    const liveKeys = new Set(keys)
    for (const key of Object.keys(panelsByTab)) {
      if (!liveKeys.has(key)) delete panelsByTab[key]
    }
    for (const tab of tabs.value) {
      if (!panelsByTab[tab.key]) panelsByTab[tab.key] = [createPanel(tab, true),]
    }
  }, { immediate: true, flush: 'sync' })

  const getPanels = key => panelsByTab[key] || []
  const panels = computed(() => tabs.value.flatMap(tab => getPanels(tab.key)))
  const resizePanels = (key, count) => {
    const tab = tabs.value.find(item => item.key === key)
    const items = panelsByTab[key]
    if (!tab || !items) return
    while (items.length < count) items.push(createPanel(tab))
    if (items.length > count) items.splice(count)
  }
  const removePanel = (tabKey, panelKey) => {
    const items = panelsByTab[tabKey]
    const index = items?.findIndex(panel => panel.key === panelKey) ?? -1
    if (index !== -1) items.splice(index, 1)
  }

  watch(() => panels.value.map(panel => panel.status), () => {
    for (const tab of tabs.value) {
      const states = getPanels(tab.key).map(panel => panel.status)
      tab.status = states.includes(terminalStatus.CONNECT_SUCCESS)
        ? terminalStatus.CONNECT_SUCCESS
        : states.includes(terminalStatus.CONNECTING)
          ? terminalStatus.CONNECTING
          : states[0] || terminalStatus.SUSPENDED
    }
  })

  return { panels, getPanels, resizePanels, removePanel }
}
