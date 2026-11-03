const MAX_LINK_ROWS = 16
const MAX_LINK_LENGTH = 4096
const URL_TOKEN = /^[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]+$/

// TUI 弹窗的局部折行没有 isWrapped 标记。只连接备用屏幕中独占一行、
// 同缩进且同样式的下划线片段，避免把普通日志、标签或另一条 URL 拼进去。
const readLinkRow = (terminal, row) => {
  const line = terminal.buffer.active.getLine(row)
  if (!line) return null
  const match = line.translateToString(true, 0, terminal.cols).match(/^( *)(\S+) *$/)
  if (!match || !URL_TOKEN.test(match[2])) return null
  const start = match[1].length
  const text = match[2]
  let style
  for (let column = start; column < start + text.length; column++) {
    const cell = line.getCell(column)
    if (!cell?.isUnderline() || cell.getWidth() !== 1) return null
    const currentStyle = [
      cell.getFgColorMode(), cell.getFgColor(), cell.getBgColorMode(), cell.getBgColor(),
      cell.isBold(), cell.isItalic(), cell.isInverse(), cell.isUnderline(),
    ].join(':')
    if (style && style !== currentStyle) return null
    style = currentStyle
  }
  return { row, start, text, style }
}

export function findTuiLinks(terminal, row) {
  if (terminal.buffer.active.type !== 'alternate') return []
  const links = []
  for (let startRow = Math.max(0, row - MAX_LINK_ROWS + 1); startRow <= row; startRow++) {
    const first = readLinkRow(terminal, startRow)
    if (!first || first.text.length > MAX_LINK_LENGTH || !/^https?:\/\//i.test(first.text)) continue
    const segments = [first,]
    let text = first.text
    for (let nextRow = startRow + 1; nextRow < startRow + MAX_LINK_ROWS; nextRow++) {
      const previous = segments.at(-1)
      if (previous.text.length < first.text.length) break
      const next = readLinkRow(terminal, nextRow)
      if (!next || next.start !== first.start || next.style !== first.style ||
        next.text.length > first.text.length || /^https?:\/\//i.test(next.text) ||
        text.length + next.text.length > MAX_LINK_LENGTH) break
      // 短行中的普通单词也可能有下划线，保留这种不明确的情况。
      if (next.text.length < first.text.length && !/[/?#&=%]/.test(next.text)) break
      segments.push(next)
      text += next.text
    }
    if (segments.length < 2 || !segments.some(segment => segment.row === row)) continue
    try {
      const url = new URL(text)
      if (!['http:', 'https:',].includes(url.protocol)) continue
    } catch {
      continue
    }
    links.push({ text, segments })
  }
  return links
}

export function getTerminalSelectionText(terminal, links) {
  const text = terminal.getSelection().trim()
  const position = terminal.getSelectionPosition()
  if (!position || !text.includes('\n')) return text
  const lines = text.split(/\r?\n/).map(line => line.trim())
  const link = (links || findTuiLinks(terminal, position.start.y)).find(candidate =>
    candidate.segments[0].row === position.start.y &&
    candidate.segments.length === lines.length &&
    candidate.segments.every((segment, index) => segment.text === lines[index])
  )
  return link?.text || text
}

export class TuiLinksAddon {
  constructor(activateLink) {
    this.activateLink = activateLink
  }

  activate(terminal) {
    this.registration = terminal.registerLinkProvider({
      provideLinks: (y, callback) => {
        callback(findTuiLinks(terminal, y - 1).map(link => {
          const segment = link.segments.find(segment => segment.row === y - 1)
          return {
            text: link.text,
            range: {
              start: { x: segment.start + 1, y },
              end: { x: segment.start + segment.text.length, y }
            },
            activate: this.activateLink
          }
        }))
      }
    })
  }

  dispose() {
    this.registration?.dispose()
  }
}
