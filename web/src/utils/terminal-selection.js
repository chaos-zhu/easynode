import { findTuiLinks, getTerminalSelectionText } from './terminal-links.js'

// 鼠标上报模式下，TUI 自己绘制的选区不会进入 xterm 的 SelectionService。
// 保留鼠标上报，在拖动结束时用公共 select API 建立对应的本地选区。
export class TerminalSelectionAddon {
  constructor(onComplete, onContextMenu) {
    this.onComplete = onComplete
    this.onContextMenu = onContextMenu
  }

  activate(terminal) {
    this.terminal = terminal
    this.element = terminal.element
    this.screen = this.element.querySelector('.xterm-screen')
    this.document = this.element.ownerDocument
    this.onMouseDown = event => this.start(event)
    this.onMouseUp = event => this.finish(event)
    this.onContextMenuEvent = event => {
      event.stopPropagation()
      const text = this.contextSelection || getTerminalSelectionText(terminal, this.selectionLinks)
      this.contextSelection = undefined
      this.onContextMenu(event, text)
    }
    this.onBlur = () => this.reset()
    this.element.addEventListener('mousedown', this.onMouseDown, true)
    this.element.addEventListener('contextmenu', this.onContextMenuEvent)
    this.document.defaultView.addEventListener('blur', this.onBlur)
  }

  coordinates(event) {
    const rect = this.screen.getBoundingClientRect()
    if (!rect.width || !rect.height) return null
    const { cols, rows, buffer } = this.terminal
    return {
      x: Math.max(0, Math.min(cols, Math.ceil((event.clientX - rect.left) * cols / rect.width + 0.5) - 1)),
      y: buffer.active.viewportY + Math.max(0, Math.min(rows - 1, Math.floor((event.clientY - rect.top) * rows / rect.height)))
    }
  }

  start(event) {
    if (event.button === 2) {
      // 右键的鼠标上报同样会清空选区，须在 xterm 处理 mousedown 前捕获。
      this.contextSelection = getTerminalSelectionText(this.terminal, this.selectionLinks)
      return
    }
    if (event.button !== 0) return
    this.contextSelection = undefined
    this.selectionLinks = undefined
    this.reset()
    if (!this.screen.contains(event.target)) return
    const position = this.coordinates(event)
    if (!position) return
    const terminal = this.terminal
    const modified = event.ctrlKey || event.altKey || event.metaKey
    this.drag = {
      position, clientX: event.clientX, clientY: event.clientY,
      buffer: terminal.buffer.active, cols: terminal.cols, rows: terminal.rows,
      modified,
      useTuiSelection: terminal.buffer.active.type === 'alternate' && terminal.modes.mouseTrackingMode !== 'none' && !modified,
      links: findTuiLinks(terminal, position.y)
    }
    this.document.addEventListener('mouseup', this.onMouseUp, true)
  }

  finish(event) {
    if (event.button !== 0 || !this.drag) return
    const drag = this.drag
    this.reset()
    const terminal = this.terminal
    if (terminal.buffer.active !== drag.buffer || terminal.cols !== drag.cols || terminal.rows !== drag.rows) return
    const distance = Math.hypot(event.clientX - drag.clientX, event.clientY - drag.clientY)
    if (drag.modified && distance < 3) return
    let selection
    if (drag.useTuiSelection) {
      const end = this.coordinates(event)
      if (!end || distance < 3) return
      const startIndex = drag.position.y * terminal.cols + drag.position.x
      const endIndex = end.y * terminal.cols + end.x
      if (startIndex === endIndex) return
      const start = startIndex < endIndex ? drag.position : end
      selection = { start, length: Math.abs(endIndex - startIndex) }
    }
    // mouseup 上报会清空本地选区，普通选区也在 document 的 mouseup 中完成。
    // 等整次事件分发结束后再建立 TUI 选区、捕获文字并通知菜单。
    this.completionTimer = setTimeout(() => {
      this.completionTimer = null
      if (terminal.buffer.active !== drag.buffer || terminal.cols !== drag.cols || terminal.rows !== drag.rows) return
      if (selection && !terminal.hasSelection()) terminal.select(selection.start.x, selection.start.y, selection.length)
      this.selectionLinks = selection ? drag.links : undefined
      // TUI 拖选可能重画文字样式，使用按下鼠标时识别的 URL 边界。
      this.onComplete(event, getTerminalSelectionText(terminal, this.selectionLinks))
    }, 0)
  }

  reset() {
    this.drag = null
    clearTimeout(this.completionTimer)
    this.completionTimer = null
    this.document.removeEventListener('mouseup', this.onMouseUp, true)
  }

  dispose() {
    this.reset()
    this.element.removeEventListener('mousedown', this.onMouseDown, true)
    this.element.removeEventListener('contextmenu', this.onContextMenuEvent)
    this.document.defaultView.removeEventListener('blur', this.onBlur)
  }
}
