// Requires Playwright (or NODE_PATH pointing to an existing installation).
// CHROME_PATH may select an installed Chromium browser; no real SSH is used.
import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { dirname, resolve, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createServer } from 'vite'
import vue from '@vitejs/plugin-vue'

const { chromium } = createRequire(import.meta.url)('playwright')
const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const cacheDir = await mkdtemp(resolve(tmpdir(), 'easynode-browser-test-'))
const ancillaryComponents = new Set([
  'server-status.vue', 'server-status-bar.vue', 'host-form.vue', 'terminal-settings-dialog.vue',
  'footer-bar.vue', 'sftp-v2.vue', 'docker.vue', 'terminal-session-setting.vue',
  'terminal-ai-chat.vue', 'terminal-workspace-background.vue', 'script-input.vue', 'PlusLimitTip.vue',
])
const server = await createServer({
  configFile: false,
  root: webRoot,
  cacheDir,
  plugins: [{
    name: 'terminal-browser-fixture',
    enforce: 'pre',
    resolveId(id, importer) {
      if (!importer?.includes('/src/views/terminal/components/')) return
      if (ancillaryComponents.has(basename(id))) return resolve(webRoot, 'test/browser/empty-component.js')
      if (id === '@/utils' || id === resolve(webRoot, 'src/utils')) return resolve(webRoot, 'test/browser/terminal-network.js')
    },
    transform(code, id) {
      if (id.endsWith('/terminal-wrapper.vue')) return code.replace('</script>', 'defineExpose({ terminalInstances, terminalPanels, handleHorizontalScreen, handleSuspendTerminal })\n</script>')
      if (id.endsWith('/terminal.vue')) return code.replace('defineExpose({', 'defineExpose({ term, searchAddon,')
    }
  }, vue(),],
  resolve: { alias: { '@': resolve(webRoot, 'src') } },
  optimizeDeps: { entries: ['test/browser/terminal.html',] },
  server: { host: '127.0.0.1', port: 0 },
  logLevel: 'error'
})
let browser
try {
  await server.listen()
  const installedChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || (existsSync(installedChrome) ? installedChrome : undefined),
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader',],
    headless: true
  })
  const page = await browser.newPage({ viewport: { width: 1500, height: 900 } })
  page.setDefaultTimeout(15000)
  const pageErrors = []
  page.on('pageerror', error => { pageErrors.push(error.stack || error.message); console.error(error.stack || error.message) })
  const address = server.httpServer.address()
  const url = `http://127.0.0.1:${ address.port }/test/browser/terminal.html`
  await page.goto(url)
  await page.waitForFunction(() => window.terminalFixture?.sockets.length === 3 && window.terminalFixture.sockets.every(s => s.sent.some(m => m.event === 'input')))
  const modeSwitch = page.locator('.el-switch').filter({ hasText: /单窗口|多窗口/ })
  const visibleTabs = page.locator('.tabs_container:visible')
  const assertSingleLayout = async (count) => {
    await page.waitForFunction(expected => {
      const panels = [...document.querySelectorAll('.single_window_wrapper .terminal_panel'),]
      return panels.length === expected && panels.every(panel => {
        const content = panel.querySelector('.terminal_content').getBoundingClientRect()
        const screen = panel.querySelector('.xterm-screen')?.getBoundingClientRect()
        return screen && screen.width > 100 && screen.height > 100
          && screen.width <= content.width + 1 && screen.height <= content.height + 1
      })
    }, count)
    assert.equal(await visibleTabs.count(), 0)
    const boxes = await page.locator('.single_window_wrapper .terminal_panel').evaluateAll(panels => panels.map(panel => {
      const { x, y, width, height } = panel.getBoundingClientRect()
      return { x, y, width, height }
    }))
    for (let i = 0; i < boxes.length; i++) {
      for (let j = i + 1; j < boxes.length; j++) {
        const a = boxes[i]
        const b = boxes[j]
        assert.ok(a.x + a.width <= b.x + 1 || b.x + b.width <= a.x + 1
          || a.y + a.height <= b.y + 1 || b.y + b.height <= a.y + 1, 'Terminal panels must not overlap')
      }
    }
  }
  await modeSwitch.click()
  await assertSingleLayout(3)
  if (process.env.TERMINAL_SCREENSHOT) await page.screenshot({ path: process.env.TERMINAL_SCREENSHOT })
  await modeSwitch.click()
  await page.locator('.el-tabs__item').filter({ hasText: 'Host A' }).click()
  await page.locator('.el-tabs__item').filter({ hasText: 'Host B' }).locator('.is-icon-close').click()
  await page.waitForFunction(() => window.terminalFixture.tabs.length === 2)
  await page.waitForTimeout(100)
  const errorsAfterClose = await page.evaluate(() => window.terminalFixture.errors)
  assert.deepEqual(errorsAfterClose, [], 'Closing an inactive tab must dispose real xterm addons without errors')
  assert.equal(await page.locator('.el-tabs__item').count(), 2)
  assert.equal(await page.locator('.terminal_tab_container').count(), 2)
  assert.equal(await page.getByRole('tab', { name: 'Host A', exact: true }).getAttribute('aria-selected'), 'true', 'Closing B must keep A selected')
  await page.waitForFunction(() => document.activeElement?.matches('.xterm-helper-textarea')
    && document.activeElement.closest('[role="tabpanel"]')?.id === 'pane-0')
  await page.keyboard.type('keep-focus')
  await page.waitForFunction(() => window.terminalFixture.sockets[0].sent.filter(m => m.event === 'input').map(m => m.payload).join('').endsWith('keep-focus'))
  assert.equal(await page.evaluate(() => window.terminalFixture.sockets[2].sent.filter(m => m.event === 'input').length), 1, 'Typing after closing B must not reach C')
  for (let index = 0; index < 3; index++) {
    await modeSwitch.click()
    await page.waitForTimeout(150)
    assert.equal(await visibleTabs.count(), 0, 'Multi-tab layout must be hidden in single-window mode')
    assert.equal(await page.locator('.single_window_wrapper:visible .terminal_content .xterm').count(), 2)
    await assertSingleLayout(2)
    await modeSwitch.click()
    await page.waitForTimeout(150)
    assert.equal(await visibleTabs.count(), 1)
    assert.equal(await page.locator('.single_window_wrapper:visible').count(), 0)
  }
  assert.equal(await page.evaluate(() => window.terminalFixture.sockets.length), 3, 'Layout switches must not reconnect SSH')
  await page.locator('.el-tabs__item').filter({ hasText: 'Host A' }).click()
  await page.locator('[title="左右分屏"]:visible').click()
  await page.waitForFunction(() => window.terminalFixture.sockets.length === 4 && window.terminalFixture.sockets[3].sent.some(m => m.event === 'input'))
  assert.equal(await page.evaluate(async () => {
    const fixture = window.terminalFixture
    const workspace = fixture.workspace.value
    const panel = workspace.terminalPanels.find(p => p.tabKey === 'A' && p.key !== 'A')
    return workspace.handleSuspendTerminal(fixture.tabs[0], 0, { panelKey: panel.key })
  }), true)
  await page.waitForFunction(() => window.terminalFixture.workspace.value.terminalPanels.length === 2)
  assert.deepEqual(await page.evaluate(() => window.terminalFixture.sockets.map(s => s.connected)), [true, false, true, false,], 'Suspend must disconnect only the chosen split')
  await modeSwitch.click()
  await assertSingleLayout(2)
  const hostA = page.locator('.single_window_wrapper .terminal_panel').filter({ hasText: 'Host A' })
  await hostA.locator('.xterm-screen').click()
  await page.keyboard.type('test-input')
  await page.waitForFunction(() => window.terminalFixture.sockets[0].sent.filter(m => m.event === 'input').map(m => m.payload).join('').endsWith('test-input'))
  assert.equal(await page.evaluate(() => window.terminalFixture.sockets[2].sent.filter(m => m.event === 'input').length), 1, 'Typing in A must not send input to C')
  await hostA.locator('.terminal_close').click()
  await assertSingleLayout(1)
  assert.equal(await page.evaluate(() => window.terminalFixture.sockets[0].connected), false)
  await page.evaluate(() => window.terminalFixture.unmount())
  await page.waitForTimeout(50)
  assert.deepEqual(await page.evaluate(() => window.terminalFixture.errors), [])
  assert.equal(await page.evaluate(() => window.terminalFixture.sockets.every(s => !s.connected)), true)
  await page.goto(`${ url }?single=true`)
  await page.waitForFunction(() => window.terminalFixture?.sockets.length === 3 && window.terminalFixture.sockets.every(s => s.sent.some(m => m.event === 'input')))
  await assertSingleLayout(3)
  await page.evaluate(() => {
    const store = window.terminalFixture.store
    store.scriptList = [{ id: 'focus-script', name: 'Focus script', command: 'echo fixture-script', group: 'default' },]
    store.scriptGroupList = [{ id: 'default', name: 'Fixture scripts' },]
    store.menuSetting.scriptLibrary = true
  })
  const assertScriptFocus = async (terminal, socketIndex) => {
    for (const cascader of [false, true,]) {
      await page.evaluate(value => { window.terminalFixture.store.menuSetting.scriptLibraryCascader = value }, cascader)
      await terminal.locator('.xterm-screen').click()
      await page.locator('.left_menu .link_text').filter({ hasText: '脚本库' }).click()
      if (cascader) await page.getByText('Fixture scripts', { exact: true }).hover()
      const before = await page.evaluate(index => window.terminalFixture.sockets[index].sent.length, socketIndex)
      await page.getByText('Focus script', { exact: true }).click()
      await page.waitForFunction(({ index, before }) => window.terminalFixture.sockets[index].sent.slice(before)
        .some(message => message.event === 'input' && message.payload.startsWith('echo fixture-script')), { index: socketIndex, before })
      await page.locator('.el-dropdown__popper:visible').waitFor({ state: 'hidden' })
      await page.waitForFunction(element => element === document.activeElement, await terminal.locator('.xterm-helper-textarea').elementHandle())
      const counts = await page.evaluate(() => window.terminalFixture.sockets.map(socket => socket.sent.length))
      await page.keyboard.type('after-script')
      await page.waitForFunction(index => window.terminalFixture.sockets[index].sent.filter(message => message.event === 'input')
        .map(message => message.payload).join('').endsWith('after-script'), socketIndex)
      const syncEnabled = await page.locator('.el-switch').filter({ hasText: '同步' }).evaluate(element => element.classList.contains('is-checked'))
      if (!syncEnabled) {
        assert.deepEqual(await page.evaluate(({ counts, index }) => window.terminalFixture.sockets
          .map((socket, i) => i === index ? false : socket.sent.slice(counts[i]).some(message => message.event === 'input')), { counts, index: socketIndex }),
        counts.map(() => false), 'Typing after script execution must stay in the original terminal')
      }
    }
  }
  const syncSwitch = page.locator('.el-switch').filter({ hasText: '同步' })
  const hostB = page.locator('.single_window_wrapper .terminal_panel').filter({ hasText: 'Host B' })
  await assertScriptFocus(hostB, 1)
  await syncSwitch.click()
  await assertScriptFocus(hostB, 1)
  await syncSwitch.click()
  await modeSwitch.click()
  await page.getByRole('tab', { name: 'Host B', exact: true }).click()
  await assertScriptFocus(page.locator('#pane-1 .terminal_tab_container'), 1)
  await syncSwitch.click()
  await assertScriptFocus(page.locator('#pane-1 .terminal_tab_container'), 1)
  await syncSwitch.click()
  await page.locator('[title="左右分屏"]:visible').click()
  await page.waitForFunction(() => window.terminalFixture.sockets.length === 4 && window.terminalFixture.sockets[3].sent.some(message => message.event === 'input'))
  await assertScriptFocus(page.locator('#pane-1 .terminal_tab_container').last(), 3)
  await page.evaluate(() => window.terminalFixture.unmount())
  await page.waitForTimeout(50)
  assert.deepEqual(await page.evaluate(() => window.terminalFixture.errors), [])
  // xterm 6: real WebGL, search decorations, transparency, scrolling, and DOM fallback.
  const rendererPage = await browser.newPage({ viewport: { width: 1500, height: 900 } })
  rendererPage.on('pageerror', error => pageErrors.push(error.stack || error.message))
  rendererPage.on('console', message => {
    if (message.type() === 'warning' && message.text().includes('WebGL')) console.warn(message.text())
  })
  const loadRendererFixture = async () => {
    await rendererPage.goto(url)
    await rendererPage.waitForFunction(() => window.terminalFixture?.sockets.length === 3
      && window.terminalFixture.sockets.every(socket => socket.sent.some(message => message.event === 'input')))
    await rendererPage.getByRole('tab', { name: 'Host A', exact: true }).click()
  }
  const verifyTerminalRendering = async (renderer) => {
    assert.equal(await rendererPage.evaluate(() => Boolean(document.querySelector('#pane-0 .xterm-screen canvas:last-of-type')?.getContext('webgl2'))), renderer === 'webgl')
    if (renderer === 'dom') await rendererPage.locator('#pane-0 .xterm-rows').waitFor()
    await rendererPage.evaluate(async () => {
      const { store, sockets, workspace } = window.terminalFixture
      store.effectiveTerminalSettings.appearance.background.mode = 'html'
      store.effectiveTerminalSettings.highlighting.enabled = true
      await new Promise(requestAnimationFrame)
      sockets[0].receive('output', '\r\nERROR xterm-six-search-target\r\n')
      const terminal = workspace.value.terminalInstances.A.term
      await new Promise(resolve => terminal.write('', resolve))
    })
    await rendererPage.waitForFunction(() => getComputedStyle(document.querySelector('#pane-0 .xterm-scrollable-element')).backgroundColor === 'rgba(0, 0, 0, 0)')
    assert.equal(await rendererPage.evaluate(() => {
      const terminal = window.terminalFixture.workspace.value.terminalInstances.A.term
      const buffer = terminal.buffer.active
      for (let row = 0; row < buffer.length; row++) {
        const line = buffer.getLine(row)
        if (line.translateToString().startsWith('ERROR xterm-six-search-target')) return line.getCell(0).getFgColor()
      }
    }), 1, 'Semantic error highlighting must survive the xterm 6 parser')
    await rendererPage.locator('#pane-0 .xterm-screen').click()
    await rendererPage.keyboard.press('Control+f')
    await rendererPage.getByPlaceholder('查找内容...').fill('xterm-six-search-target')
    await rendererPage.waitForFunction(() => window.terminalFixture.workspace.value.terminalInstances.A.term.getSelection() === 'xterm-six-search-target')
    await rendererPage.locator('#pane-0 .xterm-decoration').first().waitFor()
    await rendererPage.getByPlaceholder('查找内容...').press('Escape')
    await rendererPage.evaluate(async () => {
      const terminal = window.terminalFixture.workspace.value.terminalInstances.A.term
      await new Promise(resolve => terminal.write(Array.from({ length: 100 }, (_, index) => `scroll-${ index }\r\n`).join(''), resolve))
      terminal.scrollToBottom()
    })
    await rendererPage.waitForFunction(() => {
      const buffer = window.terminalFixture.workspace.value.terminalInstances.A.term.buffer.active
      return buffer.baseY > 0 && buffer.viewportY === buffer.baseY
    })
    await rendererPage.locator('#pane-0 .xterm-screen').hover()
    await rendererPage.mouse.wheel(0, -500)
    await rendererPage.waitForFunction(() => {
      const buffer = window.terminalFixture.workspace.value.terminalInstances.A.term.buffer.active
      return buffer.viewportY < buffer.baseY
    })
    await rendererPage.evaluate(() => window.terminalFixture.workspace.value.terminalInstances.A.term.scrollToBottom())
    await rendererPage.locator('#pane-0 .xterm-screen').click()
    await rendererPage.keyboard.type('renderer-input')
    await rendererPage.waitForFunction(() => window.terminalFixture.sockets[0].sent
      .filter(message => message.event === 'input').map(message => message.payload).join('').endsWith('renderer-input'))
    assert.equal(await rendererPage.evaluate(() => window.terminalFixture.sockets.length), 3, 'Renderer changes must preserve SSH sessions')
  }
  await loadRendererFixture()
  await verifyTerminalRendering('webgl')
  await rendererPage.evaluate(() => {
    const canvas = document.querySelector('#pane-0 .xterm-screen canvas:last-of-type')
    const extension = canvas.getContext('webgl2').getExtension('WEBGL_lose_context')
    if (!extension) throw new Error('Context loss extension unavailable')
    extension.loseContext()
  })
  await rendererPage.locator('#pane-0 .xterm-rows').waitFor()
  await verifyTerminalRendering('dom')
  // Reproduce a TUI popup using cursor positioning and real mouse-mode changes.
  const firstUrlRow = 'https://example.com/device?user_code=ABCD-'
  const secondUrlRow = 'EFGH&client_id=example-cli'
  const completeUrl = firstUrlRow + secondUrlRow
  await rendererPage.evaluate(async ({ first, second }) => {
    const { store, workspace } = window.terminalFixture
    store.effectiveTerminalSettings.highlighting.enabled = false
    await new Promise(requestAnimationFrame)
    window.openedTerminalUrls = []
    window.open = uri => { window.openedTerminalUrls.push(uri); return null }
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
      writeText: async text => { window.copiedTerminalText = text }
    } })
    const terminal = workspace.value.terminalInstances.A.term
    await new Promise(resolve => terminal.write(
      `\x1b[?1049h\x1b[2J\x1b[3;6H\x1b[4;32m${ first }\x1b[0m\x1b[4;6H\x1b[4;32m${ second }\x1b[0m`, resolve
    ))
  }, { first: firstUrlRow, second: secondUrlRow })
  const cellPosition = async (row, column = 6.5) => rendererPage.evaluate(({ row, column }) => {
    const terminal = window.terminalFixture.workspace.value.terminalInstances.A.term
    const screen = document.querySelector('#pane-0 .xterm-screen').getBoundingClientRect()
    return { x: screen.left + column * screen.width / terminal.cols, y: screen.top + (row + 0.5) * screen.height / terminal.rows }
  }, { row, column })
  for (const row of [2, 3,]) {
    const { x, y } = await cellPosition(row)
    await rendererPage.mouse.move(x, y)
    await rendererPage.waitForTimeout(100)
    await rendererPage.keyboard.down('Alt')
    await rendererPage.mouse.click(x, y)
    await rendererPage.keyboard.up('Alt')
  }
  assert.deepEqual(await rendererPage.evaluate(() => window.openedTerminalUrls), [completeUrl, completeUrl,], 'Clicking either popup row must open the complete URL')
  // Alt+click also enables column selection; return to normal selection first.
  await rendererPage.locator('#pane-0 .xterm-screen').click({ position: { x: 20, y: 10 } })
  const copyMenu = rendererPage.locator('.custom_context_menu:visible').getByText('复制', { exact: true })
  const drawPopup = async (mouseMode = true, autoMenu = true) => rendererPage.evaluate(async ({ first, second, mouseMode, autoMenu }) => {
    const { store, workspace } = window.terminalFixture
    store.effectiveTerminalSettings.behavior.autoShowContextMenu = autoMenu
    window.copiedTerminalText = null
    const terminal = workspace.value.terminalInstances.A.term
    await new Promise(resolve => terminal.write(
      `\x1b[?1002${ mouseMode ? 'h' : 'l' }\x1b[?1006h\x1b[2J\x1b[3;6H\x1b[4;32m${ first }\x1b[0m\x1b[4;6H\x1b[4;32m${ second }\x1b[0m`, resolve
    ))
    terminal.clearSelection()
  }, { first: firstUrlRow, second: secondUrlRow, mouseMode, autoMenu })
  const dragBetween = async (start, end, beforeRelease) => {
    await rendererPage.mouse.move(start.x, start.y)
    await rendererPage.mouse.down()
    await rendererPage.mouse.move(end.x, end.y, { steps: 8 })
    if (beforeRelease) await beforeRelease()
    await rendererPage.mouse.up()
  }
  const startOfUrl = await cellPosition(2, 5.1)
  const endOfUrl = await cellPosition(3, 5.1 + secondUrlRow.length)
  const repaintSelection = async () => rendererPage.evaluate(async ({ first, second }) => {
    const terminal = window.terminalFixture.workspace.value.terminalInstances.A.term
    await new Promise(resolve => terminal.write(
      `\x1b[3;6H\x1b[0;30;48;5;215m${ first }\x1b[0m\x1b[4;6H\x1b[30;48;5;215m${ second }\x1b[0m`, resolve
    ))
  }, { first: firstUrlRow, second: secondUrlRow })
  // Real pointer dragging while the TUI consumes mouse input, without term.select in the test.
  await drawPopup()
  const mouseReportsBefore = await rendererPage.evaluate(() => window.terminalFixture.sockets[0].sent.length)
  await dragBetween(startOfUrl, endOfUrl, async () => {
    assert.equal(await rendererPage.evaluate(() => window.terminalFixture.workspace.value.terminalInstances.A.term.getSelection()), '', 'Mouse reporting leaves no native xterm selection during the drag')
    // OpenTUI may repaint its orange selection and remove the URL underline.
    await repaintSelection()
  })
  await copyMenu.waitFor()
  assert.ok(await rendererPage.evaluate(before => window.terminalFixture.sockets[0].sent.slice(before)
    .some(message => message.event === 'input' && message.payload.startsWith('\x1b[<')), mouseReportsBefore), 'Selection support must preserve TUI mouse reports')
  await copyMenu.click()
  assert.equal(await rendererPage.evaluate(() => window.copiedTerminalText), completeUrl, 'TUI dragging must automatically offer and copy the complete URL even after repainting')

  await drawPopup()
  await dragBetween(endOfUrl, startOfUrl)
  await copyMenu.click()
  assert.equal(await rendererPage.evaluate(() => window.copiedTerminalText), completeUrl, 'Reverse TUI dragging must copy the complete URL')

  await drawPopup()
  await dragBetween(startOfUrl, await cellPosition(2, 5.1 + 10))
  await copyMenu.click()
  assert.equal(await rendererPage.evaluate(() => window.copiedTerminalText), firstUrlRow.slice(0, 10), 'Partial selections must remain partial')

  await drawPopup(true, false)
  await dragBetween(startOfUrl, endOfUrl, repaintSelection)
  await rendererPage.waitForFunction(() => window.terminalFixture.workspace.value.terminalInstances.A.term.getSelection().includes('EFGH&client_id=example-cli'))
  assert.equal(await copyMenu.count(), 0, 'Disabling the automatic menu must be respected')
  await rendererPage.mouse.click(startOfUrl.x + 20, startOfUrl.y, { button: 'right' })
  await copyMenu.click()
  assert.equal(await rendererPage.evaluate(() => window.copiedTerminalText), completeUrl, 'Manual context-menu copying must retain the complete dragged URL')

  await drawPopup(false)
  await dragBetween(startOfUrl, endOfUrl)
  await copyMenu.click()
  assert.equal(await rendererPage.evaluate(() => window.copiedTerminalText), completeUrl, 'Native xterm selection must also automatically open the menu after mouseup finishes')

  await drawPopup()
  await rendererPage.keyboard.down('Shift')
  await dragBetween(startOfUrl, endOfUrl)
  await rendererPage.keyboard.up('Shift')
  await copyMenu.click()
  assert.equal(await rendererPage.evaluate(() => window.copiedTerminalText), completeUrl, 'Shift dragging must select in mouse mode on both macOS and other platforms')

  await drawPopup()
  await rendererPage.mouse.click(startOfUrl.x, startOfUrl.y)
  assert.equal(await copyMenu.count(), 0, 'A TUI click without dragging must not open a selection menu')
  const openSelectionMenu = async () => {
    const selection = await rendererPage.evaluate(async () => {
      const { getTerminalSelectionText } = await import('/src/utils/terminal-links.js')
      const terminal = window.terminalFixture.workspace.value.terminalInstances.A.term
      terminal.select(5, 2, terminal.cols + 'EFGH&client_id=example-cli'.length)
      return { text: getTerminalSelectionText(terminal), position: terminal.getSelectionPosition(), raw: terminal.getSelection() }
    })
    assert.equal(selection.text, completeUrl, JSON.stringify(selection))
    await rendererPage.locator('#pane-0 .xterm-screen').dispatchEvent('contextmenu', { clientX: 300, clientY: 250 })
    await rendererPage.locator('.custom_context_menu:visible').getByText('复制', { exact: true }).waitFor()
  }
  await openSelectionMenu()
  await rendererPage.evaluate(async () => {
    const terminal = window.terminalFixture.workspace.value.terminalInstances.A.term
    await new Promise(resolve => terminal.write('\x1b[?1000h\x1b[?1006h', resolve))
    if (terminal.getSelection()) throw new Error('Mouse tracking should clear the live xterm selection')
  })
  await rendererPage.locator('.custom_context_menu:visible').getByText('复制', { exact: true }).click()
  assert.equal(await rendererPage.evaluate(() => window.copiedTerminalText), completeUrl, 'The menu must copy its captured URL after the live selection is cleared')
  await rendererPage.getByText('全屏', { exact: true }).click()
  await rendererPage.waitForFunction(() => Boolean(document.fullscreenElement))
  await rendererPage.waitForTimeout(150)
  await rendererPage.evaluate(() => {
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined })
    document.addEventListener('copy', event => {
      const textarea = document.activeElement
      window.legacyCopiedTerminalText = textarea.value?.slice(textarea.selectionStart, textarea.selectionEnd)
      window.copyTargetInFullscreen = document.fullscreenElement.contains(textarea)
      event.preventDefault()
    })
  })
  assert.equal(await rendererPage.evaluate(async text => {
    const { copyText } = await import('/src/utils/clipboard.js')
    return copyText(text, false)
  }, completeUrl), true)
  await rendererPage.waitForFunction(expected => window.legacyCopiedTerminalText === expected, completeUrl)
  assert.equal(await rendererPage.evaluate(() => window.copyTargetInFullscreen), true, 'Legacy copying must focus an element inside the fullscreen panel')
  await rendererPage.getByText('退出全屏', { exact: true }).click()
  await rendererPage.evaluate(() => window.terminalFixture.unmount())
  assert.deepEqual(await rendererPage.evaluate(() => window.terminalFixture.errors), [])
  await rendererPage.close()

  const domPage = await browser.newPage({ viewport: { width: 1500, height: 900 } })
  domPage.on('pageerror', error => pageErrors.push(error.stack || error.message))
  await domPage.addInitScript(() => {
    const getContext = HTMLCanvasElement.prototype.getContext
    HTMLCanvasElement.prototype.getContext = function(type, ...args) {
      return type.startsWith('webgl') ? null : getContext.call(this, type, ...args)
    }
  })
  await domPage.goto(url)
  await domPage.waitForFunction(() => window.terminalFixture?.sockets.length === 3
    && window.terminalFixture.sockets.every(socket => socket.sent.some(message => message.event === 'input')))
  assert.equal(await domPage.locator('.xterm-rows').count(), 3, 'Unavailable WebGL must fall back to DOM for every terminal')
  await domPage.evaluate(() => window.terminalFixture.unmount())
  assert.deepEqual(await domPage.evaluate(() => window.terminalFixture.errors), [])
  await domPage.close()
  assert.deepEqual(pageErrors, [])
  console.log('真实浏览器 / Element Plus / xterm 6：布局、会话、渲染、TUI 跨行链接、真实拖选自动菜单、右键选区快照及全屏剪贴板回退通过')
} finally {
  await browser?.close()
  await server.close()
  await rm(cacheDir, { recursive: true, force: true })
}
