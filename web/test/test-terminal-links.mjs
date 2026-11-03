import assert from 'node:assert/strict'
import xterm from '@xterm/xterm'
import { findTuiLinks, getTerminalSelectionText, TuiLinksAddon } from '../src/utils/terminal-links.js'

const first = 'https://example.com/device?user_code=ABCD-'
const second = 'EFGH&client_id=example-cli'
const url = first + second
const selectedTerminal = (terminal, text) => ({
  cols: terminal.cols,
  buffer: terminal.buffer,
  getSelection: () => text,
  getSelectionPosition: () => ({ start: { x: 5, y: 2 }, end: { x: text.split('\n').at(-1).length, y: 3 } })
})
const createTerminal = async ({ alternate = true, indent = 5, continuationStyle = '4;32' } = {}) => {
  const terminal = new xterm.Terminal({ cols: 100, rows: 20, allowProposedApi: true })
  await new Promise(resolve => terminal.write(
    `${ alternate ? '\x1b[?1049h' : '' }\x1b[3;6H\x1b[4;32m${ first }\x1b[0m` +
    `\x1b[4;${ indent + 1 }H\x1b[${ continuationStyle }m${ second }\x1b[0m`, resolve
  ))
  return terminal
}

const terminal = await createTerminal()
assert.equal(terminal.buffer.active.getLine(3).isWrapped, false, 'The popup uses cursor positioning, not terminal wrapping')
for (const row of [2, 3]) {
  const links = findTuiLinks(terminal, row)
  assert.equal(links.length, 1)
  assert.equal(links[0].text, url, 'Both popup rows must resolve to the complete URL')
}
assert.equal(getTerminalSelectionText(selectedTerminal(terminal, `${ first }\n     ${ second }`)), url, 'Copy only the URL, without popup padding or hard line breaks')
assert.equal(getTerminalSelectionText(selectedTerminal(terminal, first)), first, 'Partial selections must stay partial')

let provider
let disposed = false
const activated = []
const addon = new TuiLinksAddon((event, uri) => activated.push(uri))
addon.activate({
  cols: terminal.cols,
  buffer: terminal.buffer,
  registerLinkProvider(value) { provider = value; return { dispose() { disposed = true } } }
})
provider.provideLinks(4, links => {
  assert.equal(links[0].text, url)
  assert.deepEqual(links[0].range, { start: { x: 6, y: 4 }, end: { x: 5 + second.length, y: 4 } })
  links[0].activate({}, links[0].text)
})
assert.deepEqual(activated, [url])
addon.dispose()
assert.equal(disposed, true)

for (const options of [
  { alternate: false },
  { indent: 6 },
  { continuationStyle: '32' },
  { continuationStyle: '4;31' },
  { continuationStyle: '4;32;44' },
]) {
  const other = await createTerminal(options)
  assert.deepEqual(findTuiLinks(other, 2), [], 'Do not join normal shell output or unrelated popup text')
  const text = `${ first }\n${ ' '.repeat(options.indent || 5) }${ second }`
  assert.equal(getTerminalSelectionText(selectedTerminal(other, text)), text, 'Preserve other multiline selections')
  other.dispose()
}

await new Promise(resolve => terminal.write('\x1b[5;6H\x1b[4;32mWaiting\x1b[0m', resolve))
assert.equal(findTuiLinks(terminal, 2)[0].text, url, 'Stop after the final short continuation row')
await new Promise(resolve => terminal.write('\x1b[4;1H\x1b[2K\x1b[4;6H\x1b[4;32mWaiting\x1b[0m', resolve))
assert.deepEqual(findTuiLinks(terminal, 2), [], 'Do not append a short underlined label to a URL')
await new Promise(resolve => terminal.write('\x1b[4;1H\x1b[2K\x1b[4;6H\x1b[4;32mhttps://other.example/\x1b[0m', resolve))
assert.deepEqual(findTuiLinks(terminal, 2), [], 'Never concatenate adjacent URLs')
terminal.dispose()
console.log('TUI cursor-positioned URL recognition, selection copying, and unrelated-text boundaries passed')
