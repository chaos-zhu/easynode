import assert from 'node:assert/strict'
import {
  DEFAULT_HIGHLIGHT_RULES,
  resolveHighlightRules,
  serializeHighlightRules,
  TerminalHighlighter
} from '../src/utils/highlighter.js'
import {
  createCustomThemeId,
  createCustomHtmlThemeId,
  createDefaultTerminalSettings,
  hasDecorativeBackground,
  resolveOverlayColor,
  resolveTerminalTheme,
  resolveThemeEntity
} from '../src/utils/terminal-settings.js'
import {
  DEFAULT_TERMINAL_HTML_THEME_ID,
  getTerminalHtmlTheme,
  TERMINAL_HTML_THEMES,
  validateCustomHtmlThemeSource
} from '../src/utils/terminal-html-themes.js'

const settings = createDefaultTerminalSettings()
assert.equal(settings.version, 3)
assert.equal(settings.behavior.statusBarEnabled, true)
assert.match(createCustomThemeId(), /^custom:[0-9a-f-]{36}$/)
assert.match(createCustomHtmlThemeId(), /^custom-html:[0-9a-f-]{36}$/)
assert.equal(resolveThemeEntity(settings).id, 'builtin:Cobalt_Neon')

settings.appearance.activeThemeId = 'builtin:missing-theme'
assert.equal(resolveThemeEntity(settings).id, 'builtin:Cobalt_Neon')

settings.appearance.overrides.foreground = '#ffffff'
assert.equal(resolveTerminalTheme(settings).foreground, '#ffffff')
assert.equal(resolveTerminalTheme(settings, true).background, '#00000000')
assert.equal(resolveOverlayColor(settings), '0, 0, 0')
settings.appearance.overrides.foreground = '#000000'
assert.equal(resolveOverlayColor(settings), '255, 255, 255')
settings.appearance.overrides.foreground = 'rgba(0, 0, 0, 0.8)'
assert.equal(resolveOverlayColor(settings), '255, 255, 255')
settings.appearance.overrides.foreground = 'rgb(100%, 100%, 100%)'
assert.equal(resolveOverlayColor(settings), '0, 0, 0')
settings.appearance.overrides.foreground = '#000000ff'
assert.equal(resolveOverlayColor(settings), '255, 255, 255')
settings.appearance.overrides.foreground = null

assert.equal(hasDecorativeBackground(settings), false)
settings.appearance.background.mode = 'html'
assert.equal(hasDecorativeBackground(settings), true)

const resolvedDefaultRules = resolveHighlightRules(settings.highlighting)
assert.equal(resolvedDefaultRules.length, 8)
assert.equal(resolvedDefaultRules.find(rule => rule.id === 'error').style.foreground.token, 'red')
assert.equal(resolvedDefaultRules.find(rule => rule.id === 'success').style.foreground.token, 'green')
assert.equal(resolvedDefaultRules.find(rule => rule.id === 'info').style.foreground.token, 'cyan')
const customizedRules = structuredClone(resolvedDefaultRules)
customizedRules[0].style.bold = false
const serializedRules = serializeHighlightRules(customizedRules)
assert.equal(serializedRules.builtinOverrides.length, 1)
assert.equal(serializedRules.builtinOverrides[0].id, 'error')
assert.deepEqual(serializedRules.customRules, [])
assert.equal(settings.appearance.background.htmlThemeId, DEFAULT_TERMINAL_HTML_THEME_ID)
assert.equal(getTerminalHtmlTheme('missing').id, DEFAULT_TERMINAL_HTML_THEME_ID)
assert.equal(TERMINAL_HTML_THEMES.length, 10)
assert.ok(TERMINAL_HTML_THEMES.every(theme => theme.html.includes("default-src 'none'")))
const customHtmlThemes = [{
  id: 'custom-html:00000000-0000-4000-8000-000000000001',
  name: 'Custom',
  html: '<style>.glow { color: cyan; }</style><div class="glow"></div>'
}]
assert.equal(getTerminalHtmlTheme(customHtmlThemes[0].id, customHtmlThemes).name, 'Custom')
assert.equal(validateCustomHtmlThemeSource(customHtmlThemes[0].html), null)
assert.match(validateCustomHtmlThemeSource('<script>alert(1)</script>'), /不能包含/)
settings.appearance.background.mode = 'image'
settings.appearance.background.assetId = '00000000-0000-4000-8000-000000000001'
assert.equal(hasDecorativeBackground(settings), true)

const highlighter = new TerminalHighlighter(null, {
  enabled: true,
  customRules: DEFAULT_HIGHLIGHT_RULES
})
const highlighted = highlighter.highlightText('[2026-08-30 12:00:00] ERROR request failed')
assert.match(highlighted, /\x1b\[90m/)
assert.match(highlighted, /\x1b\[31m/)
assert.match(highlighter.highlightText('missing dependency'), /\x1b\[31m/)
assert.match(highlighter.highlightText('server address 2001:db8::1'), /\x1b\[35m/)
assert.match(highlighter.highlightText('open file://tmp/output.log'), /\x1b\[34m/)
assert.match(highlighter.highlightText('finished at 08/30/2026 9:30 PM'), /\x1b\[90m/)
assert.match(highlighter.highlightText('throughput 120 qps'), /\x1b\[35m/)
const connectionInfo = highlighter.highlightText('连接信息: ssh root@43.136.14.137 -p 22 -> password\r\n')
assert.match(connectionInfo, /\x1b\[35m43\.136\.14\.137\x1b\[0m/)

const ansiHighlighter = new TerminalHighlighter(null, {
  enabled: true,
  customRules: DEFAULT_HIGHLIGHT_RULES
})
const ansiInput = '\x1b[32mERROR request failed and remains colored'
const ansiOutput = ansiHighlighter.highlightText(ansiInput)
assert.match(ansiOutput, /\x1b\[31m/)
assert.match(ansiOutput, /\x1b\[0m\x1b\[32m$/)
assert.equal(ansiOutput.replace(TerminalHighlighter.ANSI_FULL, ''), ansiInput.replace(TerminalHighlighter.ANSI_FULL, ''))

const splitAnsiOutput = ansiHighlighter.highlightText('\x1b[36mconnec\x1b[36mted')
assert.match(splitAnsiOutput, /\x1b\[32m/)
assert.equal(splitAnsiOutput.replace(TerminalHighlighter.ANSI_FULL, ''), 'connected')
assert.equal(ansiHighlighter.highlightText('\x1b[3'), '')
const completedAnsiOutput = ansiHighlighter.highlightText('2mERROR failed')
assert.match(completedAnsiOutput, /^\x1b\[32m/)
assert.match(completedAnsiOutput, /\x1b\[0m\x1b\[32m$/)

const promptOutput = ansiHighlighter.highlightText('\x1b[?2004hroot@host:~# ')
assert.equal(promptOutput, '\x1b[?2004hroot@host:~# ')
assert.equal(ansiHighlighter.highlightText('\x1b[32mplain text '), '\x1b[32mplain text ')
assert.equal(ansiHighlighter.highlightText('\x1b]0;root@host: ~\x07root@host:~# '), '\x1b]0;root@host: ~\x07root@host:~# ')

const cursorControlInput = '\x1b[?2004h\rroot@host:~# STATUS healthy\x1b[?2004l'
const cursorControlOutput = ansiHighlighter.highlightText(cursorControlInput)
const stripSgr = value => value.replace(/\x1b\[[0-9:;]*m/g, '')
assert.equal(stripSgr(cursorControlOutput), cursorControlInput)

const fixedColorHighlighter = new TerminalHighlighter(null, {
  enabled: true,
  customRules: [{
    id: 'fixed',
    title: 'Fixed',
    pattern: 'fixed',
    flags: 'gi',
    scope: 'match',
    priority: 0,
    enabled: true,
    style: {
      foreground: { source: 'fixed', value: '#ff8000' },
      background: null,
      bold: false,
      italic: false,
      underline: false
    }
  }]
})
assert.match(fixedColorHighlighter.highlightText('fixed'), /\x1b\[38;2;255;128;0m/)

const lineHighlighter = new TerminalHighlighter(null, {
  enabled: true,
  customRules: [{
    id: 'line',
    title: 'Line',
    pattern: 'target',
    flags: 'gi',
    scope: 'line',
    priority: 10,
    enabled: true,
    style: {
      foreground: { source: 'theme', token: 'brightYellow' },
      background: null,
      bold: false,
      italic: false,
      underline: false
    }
  }]
})
assert.match(lineHighlighter.highlightText('before target after\r\nnext'), /^\x1b\[93mbefore target after\x1b\[0m\r\nnext$/)

const disabledHighlighter = new TerminalHighlighter(null, { enabled: false })
assert.equal(disabledHighlighter.highlightText('ERROR'), 'ERROR')
assert.equal(disabledHighlighter.highlightText('\x1b[35mplain'), '\x1b[35mplain')
disabledHighlighter.setEnabled(true)
assert.match(disabledHighlighter.highlightText('ERROR failed'), /\x1b\[0m\x1b\[35m$/)

console.log('terminal appearance tests passed')
