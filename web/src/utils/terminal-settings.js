import themeList from 'xterm-theme'
import { DEFAULT_TERMINAL_HTML_THEME_ID, getTerminalHtmlThemes } from './terminal-html-themes.js'
import { createDefaultHighlightingSettings } from './highlighter.js'

export const DEFAULT_THEME_ID = 'builtin:Cobalt_Neon'

export const TERMINAL_WELCOME_LINES = [
  '\x1b[1;32mWelcome to EasyNode terminal\x1b[0m.',
  '\x1b[1;32mAn experimental Web-SSH Terminal\x1b[0m.',
]

export const ANSI_COLOR_KEYS = [
  'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white',
  'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
  'brightBlue', 'brightMagenta', 'brightCyan', 'brightWhite',
]

export const THEME_COLOR_FIELDS = [
  'foreground', 'background', 'cursor', 'cursorAccent',
  'selectionBackground', 'selectionForeground', 'selectionInactiveBackground',
  ...ANSI_COLOR_KEYS,
]

export const EASY_NODE_CUSTOM_THEME_COLORS = {
  foreground: '#d8dee9',
  background: '#10151d',
  cursor: '#7dd3fc',
  cursorAccent: '#10151d',
  selectionBackground: '#334155',
  selectionForeground: '#f8fafc',
  selectionInactiveBackground: '#263244',
  black: '#1e293b',
  red: '#fb7185',
  green: '#86efac',
  yellow: '#fde68a',
  blue: '#7dd3fc',
  magenta: '#c4b5fd',
  cyan: '#67e8f9',
  white: '#e2e8f0',
  brightBlack: '#64748b',
  brightRed: '#fda4af',
  brightGreen: '#bbf7d0',
  brightYellow: '#fef3c7',
  brightBlue: '#bae6fd',
  brightMagenta: '#ddd6fe',
  brightCyan: '#a5f3fc',
  brightWhite: '#f8fafc'
}

export function createDefaultTerminalSettings() {
  return {
    version: 3,
    appearance: {
      activeThemeId: DEFAULT_THEME_ID,
      customThemes: [],
      customHtmlThemes: [],
      font: { family: 'monospace', size: 16 },
      overrides: { foreground: null, cursor: null, selectionBackground: null },
      background: {
        mode: 'theme',
        htmlThemeId: DEFAULT_TERMINAL_HTML_THEME_ID,
        assetId: null,
        fit: 'cover',
        position: 'center',
        overlay: { tone: 'auto', opacity: 0.35 }
      }
    },
    highlighting: createDefaultHighlightingSettings(),
    behavior: {
      autoReconnect: true,
      autoExecuteScript: false,
      autoShowContextMenu: true,
      statusBarEnabled: true
    }
  }
}

export function cloneTerminalSettings(settings) {
  return JSON.parse(JSON.stringify(settings || createDefaultTerminalSettings()))
}

export function createCustomThemeId() {
  if (globalThis.crypto?.randomUUID) return `custom:${ globalThis.crypto.randomUUID() }`
  const uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, character => {
    const random = Math.floor(Math.random() * 16)
    return (character === 'x' ? random : (random & 0x3) | 0x8).toString(16)
  })
  return `custom:${ uuid }`
}

export function createCustomHtmlThemeId() {
  const id = createCustomThemeId().slice('custom:'.length)
  return `custom-html:${ id }`
}

export function getBuiltinThemes() {
  return Object.entries(themeList).map(([name, colors,]) => ({
    id: `builtin:${ name }`,
    name,
    colors,
    builtin: true
  }))
}

export function resolveThemeEntity(settings) {
  const appearance = settings?.appearance || createDefaultTerminalSettings().appearance
  const activeId = appearance.activeThemeId || DEFAULT_THEME_ID
  if (activeId.startsWith('custom:')) {
    const customTheme = appearance.customThemes?.find(item => item.id === activeId)
    if (customTheme) return { ...customTheme, builtin: false }
  }

  const builtinName = activeId.startsWith('builtin:') ? activeId.slice(8) : ''
  const fallbackName = DEFAULT_THEME_ID.slice(8)
  const resolvedName = themeList[builtinName] ? builtinName : fallbackName
  return {
    id: `builtin:${ resolvedName }`,
    name: resolvedName,
    colors: themeList[resolvedName] || EASY_NODE_CUSTOM_THEME_COLORS,
    builtin: true
  }
}

export function resolveTerminalTheme(settings, transparent = false) {
  const appearance = settings?.appearance || createDefaultTerminalSettings().appearance
  const theme = {
    ...resolveThemeEntity(settings).colors
  }
  if (appearance.overrides?.foreground) theme.foreground = appearance.overrides.foreground
  if (appearance.overrides?.cursor) theme.cursor = appearance.overrides.cursor
  if (appearance.overrides?.selectionBackground) theme.selectionBackground = appearance.overrides.selectionBackground
  if (transparent) theme.background = '#00000000'
  return theme
}

export function hasDecorativeBackground(settings) {
  const background = settings?.appearance?.background
  if (background?.mode === 'image') return Boolean(background.previewUrl || background.assetId)
  return background?.mode === 'html' && getTerminalHtmlThemes(settings?.appearance?.customHtmlThemes)
    .some(theme => theme.id === background.htmlThemeId)
}

function colorChannels(color) {
  const value = String(color || '').trim()
  const hex = value.match(/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i)?.[1]
  if (hex) {
    const rgbHex = hex.length <= 4
      ? hex.slice(0, 3).split('').map(character => character + character).join('')
      : hex.slice(0, 6)
    return [0, 2, 4,].map(index => parseInt(rgbHex.slice(index, index + 2), 16))
  }

  const rgb = value.match(/^rgba?\(\s*([\d.]+%?)\s*,\s*([\d.]+%?)\s*,\s*([\d.]+%?)(?:\s*,\s*[\d.]+%?)?\s*\)$/i)
  if (!rgb) return null
  return rgb.slice(1, 4).map(channel => {
    const numericValue = Number.parseFloat(channel)
    if (!Number.isFinite(numericValue)) return 0
    const normalizedValue = channel.endsWith('%') ? numericValue * 2.55 : numericValue
    return Math.max(0, Math.min(255, normalizedValue))
  })
}

function colorLuminance(color) {
  const rgb = colorChannels(color)
  if (!rgb) return 1
  const channels = rgb.map(channel => channel / 255)
  const [red, green, blue,] = channels.map(channel => channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4)
  return red * 0.2126 + green * 0.7152 + blue * 0.0722
}

export function resolveOverlayColor(settings) {
  const overlay = settings?.appearance?.background?.overlay
  if (overlay?.tone === 'light') return '255, 255, 255'
  if (overlay?.tone === 'dark') return '0, 0, 0'
  const foreground = resolveTerminalTheme(settings).foreground
  return colorLuminance(foreground) > 0.45 ? '0, 0, 0' : '255, 255, 255'
}
