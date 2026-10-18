// Uses Playwright (or NODE_PATH pointing to an existing installation) and Chrome.
// Only API and Socket.IO transport are mocked; no real commands are executed.
import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createServer } from 'vite'
import vue from '@vitejs/plugin-vue'

const { chromium } = createRequire(import.meta.url)('playwright')
const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const cacheDir = await mkdtemp(resolve(tmpdir(), 'easynode-onekey-test-'))
const server = await createServer({
  configFile: false,
  root: webRoot,
  cacheDir,
  plugins: [vue(),],
  resolve: {
    alias: [
      { find: /^@\/utils$/, replacement: resolve(webRoot, 'test/browser/onekey-network.js') },
      { find: '@', replacement: resolve(webRoot, 'src') },
    ]
  },
  optimizeDeps: { entries: ['test/browser/onekey.html',] },
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
  const page = await browser.newPage({ viewport: { width: 1500, height: 700 } })
  page.setDefaultTimeout(15000)
  const pageErrors = []
  page.on('pageerror', error => pageErrors.push(error.stack || error.message))
  await page.goto(`http://127.0.0.1:${ server.httpServer.address().port }/test/browser/onekey.html`)
  const table = page.locator('.onekey_table_wrap')
  const rows = table.locator('.el-table__body tr.el-table__row')
  const outputs = table.locator('.detail_content_box')
  const pagination = page.locator('.onekey_pagination')
  const pageButton = number => pagination.locator('.el-pager li.number').filter({ hasText: new RegExp(`^\\s*${ number }\\s*$`) })
  const firstExpand = () => rows.first().locator('.el-table__expand-icon')
  const togglePageExpansion = async name => {
    await page.getByRole('button', { name: '更多操作', exact: true }).click()
    await page.getByRole('menuitem', { name, exact: true }).waitFor({ state: 'visible' })
    assert.equal(await page.getByRole('menuitem', { name: /^(展开|折叠)本页$/ }).count(), 1, 'More menu uses one expansion toggle')
    await page.getByRole('menuitem', { name, exact: true }).click()
  }

  await page.waitForFunction(() => document.querySelectorAll('.el-table__body tr.el-table__row').length === 20)
  assert.match(await pagination.locator('.el-pagination__total').innerText(), /126/)
  assert.equal(await page.locator('.data_page_summary').count(), 0, 'History totals should appear only in pagination')
  assert.equal(await page.getByRole('button', { name: /^(展开|折叠)本页$/ }).count(), 0, 'Expansion should live in the More menu')
  assert.deepEqual(await page.evaluate(() => window.onekeyFixture.listRequests), [{ page: 1, pageSize: 20 }])
  assert.equal(await page.evaluate(() => window.onekeyFixture.outputRequests.length), 0, 'Collapsed history must not fetch output')

  await page.evaluate(() => { window.onekeyFixture.slowPage = 2 })
  await pageButton(2).click()
  await page.waitForFunction(() => window.onekeyFixture.listRequests.some(request => request.page === 2))
  await pageButton(3).click()
  await page.waitForFunction(() => document.querySelector('.instance_cell strong').textContent === 'Record 041')
  await page.waitForTimeout(300)
  assert.match(await rows.first().innerText(), /Record 041/, 'Late responses must not replace the current page')
  await page.evaluate(() => { window.onekeyFixture.slowPage = 0 })
  await pageButton(7).click()
  await page.waitForFunction(() => document.querySelectorAll('.el-table__body tr.el-table__row').length === 6)
  assert.match(await rows.last().innerText(), /Record 126/)
  await togglePageExpansion('展开本页')
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 6)
  await page.waitForFunction(() => [...document.querySelectorAll('.output_text'),].at(-1)?.textContent.includes('Output 126'))
  assert.equal(await page.evaluate(() => window.onekeyFixture.outputRequests.length), 6)
  assert.equal(await outputs.first().locator('.output_text').evaluate(element => element.textContent.length), 64 * 1024)
  await outputs.first().getByRole('button', { name: '加载更多输出', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('.output_text').textContent.length === 128 * 1024)
  await page.evaluate(() => { window.onekeyFixture.failNextOutput = true })
  await outputs.first().getByRole('button', { name: '加载更多输出', exact: true }).click()
  await outputs.first().getByRole('button', { name: '重试加载', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('.output_text').textContent.length === 'long output\n'.length * 12000)
  assert.equal(await outputs.first().getByRole('button', { name: '加载更多输出', exact: true }).count(), 0)
  await table.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate(element => { element.scrollTop = element.scrollHeight })
  await page.waitForFunction(() => {
    const last = [...document.querySelectorAll('.el-table__body tr.el-table__row'),].at(-1).getBoundingClientRect()
    const viewport = document.querySelector('.el-table__body-wrapper .el-scrollbar__wrap').getBoundingClientRect()
    return last.top >= viewport.top && last.bottom <= viewport.bottom + 1
  })
  assert.equal(await outputs.first().evaluate(element => element.scrollHeight > element.clientHeight), true, 'Long output must scroll independently')

  // Off-page rows keep their own expansion state; bulk actions affect the current page only.
  await pageButton(1).click()
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 0)
  assert.equal(await table.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate(element => element.scrollTop), 0)
  await togglePageExpansion('展开本页')
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 20)
  await togglePageExpansion('折叠本页')
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 0)
  await pageButton(7).click()
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 6)

  // Deleting and refreshing preserve the page and the surviving rows' expansion.
  await rows.first().getByRole('button', { name: '删除', exact: true }).click()
  await page.waitForFunction(() => document.querySelectorAll('.el-table__body tr.el-table__row').length === 5)
  assert.equal(await outputs.count(), 5)
  for (let remaining = 5; remaining > 0; remaining--) {
    await rows.first().getByRole('button', { name: '删除', exact: true }).click()
    await page.waitForFunction(total => document.querySelector('.el-pagination__total').textContent.replace(/\s/g, '') === `共${ total }条`, 120 + remaining - 1)
  }
  assert.equal(await pageButton(6).getAttribute('aria-current'), 'true', 'Deleting the last row on a page must select the previous page')
  assert.equal(await rows.count(), 20)

  await pagination.locator('.el-select').click()
  await page.getByRole('option', { name: '50条/页', exact: true }).click()
  await page.waitForFunction(() => document.querySelectorAll('.el-table__body tr.el-table__row').length === 50)
  assert.equal(await pageButton(1).getAttribute('aria-current'), 'true')
  await pagination.locator('.el-select').click()
  await page.getByRole('option', { name: '100条/页', exact: true }).click()
  await page.waitForFunction(() => document.querySelectorAll('.el-table__body tr.el-table__row').length === 100)
  await pageButton(2).click()
  await page.waitForFunction(() => document.querySelectorAll('.el-table__body tr.el-table__row').length === 20)
  await pagination.locator('.el-select').click()
  await page.getByRole('option', { name: '20条/页', exact: true }).click()
  await pageButton(2).click()

  // Start through the real form and feed new objects through the Socket.IO handlers.
  await page.getByRole('button', { name: '执行指令', exact: true }).click()
  await page.locator('.select_host_wrap .el-select').click()
  await page.getByRole('option', { name: 'Live A', exact: true }).click()
  await page.locator('.el-dialog textarea').fill('echo live')
  await page.getByRole('button', { name: '开始执行', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('.data_page_summary').textContent.includes('当前批次 2 条'))
  assert.equal(await pageButton(1).getAttribute('aria-current'), 'true', 'New batches must return to page one')
  assert.equal(await rows.count(), 22)
  assert.match(await rows.first().innerText(), /Live A/)
  assert.equal(await outputs.count(), 2, 'Live rows initially expand')
  await firstExpand().click()
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 1)
  await page.evaluate(() => window.onekeyFixture.output('updated'))
  await page.waitForFunction(() => document.querySelector('.detail_content_box').textContent.includes('updated'))
  assert.equal(await outputs.count(), 1, 'Output updates must respect a manual collapse')
  await pageButton(2).click()
  await page.waitForFunction(() => document.querySelectorAll('.el-table__body tr.el-table__row').length === 22)
  await page.waitForFunction(() => document.querySelector('.instance_cell strong')?.textContent === 'Live A'
    && [...document.querySelectorAll('.instance_cell strong'),][2]?.textContent === 'Record 021')
  assert.match(await rows.first().innerText(), /Live A/, 'Live rows must stay above every history page')
  await togglePageExpansion('折叠本页')
  await page.evaluate(() => window.onekeyFixture.output('collapsed'))
  await page.waitForTimeout(100)
  assert.equal(await outputs.count(), 0, 'Bulk collapse must survive subsequent output updates')
  await togglePageExpansion('展开本页')
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 22)
  await firstExpand().click()
  await pageButton(1).click()
  await page.evaluate(() => window.onekeyFixture.finish())
  await page.waitForFunction(() => document.querySelector('.el-pagination__total').textContent.replace(/\s/g, '') === '共122条')
  assert.equal(await outputs.count(), 1, 'Persisting live rows must retain both expanded and collapsed states')

  await togglePageExpansion('折叠本页')
  await page.waitForFunction(() => document.querySelectorAll('.detail_content_box').length === 0)
  await togglePageExpansion('展开本页')
  for (const viewport of [{ width: 1000, height: 420 }, { width: 390, height: 650 },]) {
    await page.setViewportSize(viewport)
    await page.waitForTimeout(150)
    assert.equal(await pagination.evaluate(element => {
      const box = element.getBoundingClientRect()
      return box.top >= 0 && box.bottom <= window.innerHeight
    }), true, 'Pagination must remain visible after resizing')
    assert.equal(await table.evaluate(element => element.getBoundingClientRect().height > 100), true)
    await table.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate(element => { element.scrollTop = element.scrollHeight })
    assert.equal(await table.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate(element => element.scrollTop > 0), true)
  }
  if (process.env.ONEKEY_SCREENSHOT) await page.screenshot({ path: process.env.ONEKEY_SCREENSHOT })
  await page.getByRole('button', { name: '更多操作', exact: true }).click()
  await page.getByRole('menuitem', { name: '删除全部记录', exact: true }).click()
  await page.waitForFunction(() => document.querySelector('.el-pagination__total').textContent.replace(/\s/g, '') === '共0条')
  assert.equal(await rows.count(), 0)
  assert.equal(await page.getByRole('button', { name: '更多操作', exact: true }).count(), 0)
  assert.deepEqual(await page.evaluate(() => window.onekeyFixture.errors), [])
  assert.ok(await page.evaluate(() => window.onekeyFixture.maxOutputRequests) <= 4, 'Bulk expansion must limit concurrent output requests')
  assert.deepEqual(pageErrors, [])
  await page.evaluate(() => window.onekeyFixture.unmount())
  console.log('批量指令浏览器回归通过：服务端分页、快速翻页、输出分段加载和重试、展开折叠、实时输出及小窗口')
} finally {
  await browser?.close()
  await server.close()
  await rm(cacheDir, { recursive: true, force: true })
}
