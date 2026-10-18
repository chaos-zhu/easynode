import assert from 'node:assert/strict'
import fs from 'node:fs'
import * as Vue from 'vue'
import { renderToString } from '@vue/server-renderer'
import { parse, compileScript, compileTemplate } from '@vue/compiler-sfc'

const filename = new URL('../src/components/ai-agent/panel-batch-preview.vue', import.meta.url)
const { descriptor } = parse(fs.readFileSync(filename, 'utf8'), { filename: filename.pathname })
const script = compileScript(descriptor, { id: 'test-panel-preview' })
const source = script.content.replace(/^import[^\n]+\n/gm, '').replace('export default', 'return')
const component = new Function('computed', source)(Vue.computed)
const template = compileTemplate({ source: descriptor.template.content, filename: filename.pathname, id: 'test-panel-preview',
  compilerOptions: { mode: 'function', bindingMetadata: script.bindings } })
assert.deepEqual(template.errors, [])
component.render = new Function('Vue', template.code)(Vue)
const diff = Array.from({ length: 1000 }, (_, index) => `+echo line-${ index }`).join('\n')
const html = await renderToString(Vue.createSSRApp(component, { preview: {
  action: 'delete', items: [{ id: 'script-1', name: '<script>alert(1)</script>', changed: true,
    changes: [{ field: 'command', diff },], group: { name: 'Default' }, members: [],
    affectedTasks: [{ taskId: 'task-1', name: 'Nightly task' },] },]
} }))
assert.ok(html.includes('<details>'))
assert.ok(html.includes('line-999'))
assert.ok(html.includes('Nightly task'))
assert.ok(html.includes('以下定时任务将被禁用'))
assert.ok(!html.includes('<script>alert(1)</script>'))
console.log('批量预览真实组件渲染、完整长差异、任务影响与文本转义通过')
