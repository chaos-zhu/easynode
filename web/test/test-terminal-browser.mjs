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
  assert.deepEqual(pageErrors, [])
  console.log('真实浏览器 / Element Plus / xterm：终端布局、会话关闭与挂起、脚本菜单焦点恢复、分屏和同步输入及卸载通过')
} finally {
  await browser?.close()
  await server.close()
  await rm(cacheDir, { recursive: true, force: true })
}
