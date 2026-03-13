/**
 * useTerminalTabContextMenu
 * 抽离终端 Tab / 标题栏右键菜单的通用逻辑，供多窗口模式和单窗口模式复用。
 *
 * @param {Object} options
 * @param {import('vue').ComputedRef<Array>} options.terminalTabs   - 当前所有终端 tab 列表
 * @param {Function} options.onSuspend          - (item, index) => Promise<boolean>  挂起单个终端
 * @param {Function} options.onSuspendAll       - ()            => void              挂起所有
 * @param {Function} options.onCloseOther       - (index)       => void              关闭其他
 * @param {Function} options.onCloseAll         - ()            => void              关闭所有
 * @param {import('@/composables/useContextMenu').showMenu} options.showMenu - 显示右键菜单的方法
 * @param {import('@/utils/enum').terminalStatus} options.terminalStatus    - 终端状态枚举
 */
export function useTerminalTabContextMenu({
  terminalTabs,
  onSuspend,
  onSuspendAll,
  onCloseOther,
  onCloseAll,
  showMenu,
  terminalStatus
}) {
  /**
   * 构建 Tab / 标题栏右键菜单项
   * @param {object} item    - 当前 tab 对象
   * @param {number} index   - 当前 tab 索引（单窗口模式中也传入相应索引）
   */
  const buildTabMenuItems = (item, index) => {
    const menuItems = []

    // 挂起终端（仅在已连接状态显示）
    if (item.status === terminalStatus.CONNECT_SUCCESS) {
      menuItems.push({
        label: '挂起',
        onClick: () => onSuspend(item, index)
      })
    }

    // 挂起所有会话（存在已连接会话时显示）
    const tabs = typeof terminalTabs === 'function' ? terminalTabs() : terminalTabs.value
    if (tabs.some(tab => tab.status === terminalStatus.CONNECT_SUCCESS)) {
      menuItems.push({
        label: '挂起所有',
        onClick: () => onSuspendAll()
      })
    }

    // 关闭其他终端
    if (tabs.length > 1) {
      menuItems.push({
        label: '关闭其他',
        onClick: () => onCloseOther(index, item)
      })
    }

    // 关闭所有终端
    menuItems.push({
      label: '关闭所有',
      onClick: () => onCloseAll()
    })

    return menuItems
  }

  /**
   * 处理 Tab / 标题栏右键事件
   * @param {MouseEvent} e
   * @param {object} item
   * @param {number} index
   */
  const handleTabContextMenu = (e, item, index) => {
    e.preventDefault()
    e.stopPropagation()
    const menuItems = buildTabMenuItems(item, index)
    showMenu(e, menuItems)
  }

  return {
    buildTabMenuItems,
    handleTabContextMenu
  }
}
