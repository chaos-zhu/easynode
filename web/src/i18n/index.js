import { createI18n } from 'vue-i18n'
import zhCN from './locales/zh-CN'
import en from './locales/en'

const SUPPORT_LOCALES = ['zh-CN', 'en']
const DEFAULT_LOCALE = 'zh-CN'

const normalizeLocale = (locale) => {
  if (!locale) return DEFAULT_LOCALE
  if (SUPPORT_LOCALES.includes(locale)) return locale
  if (locale.toLowerCase().startsWith('zh')) return 'zh-CN'
  if (locale.toLowerCase().startsWith('en')) return 'en'
  return DEFAULT_LOCALE
}

const savedLocale = localStorage.getItem('locale')
const browserLocale = navigator.language
const locale = normalizeLocale(savedLocale || browserLocale)

const messages = {
  'zh-CN': zhCN,
  en
}

const i18n = createI18n({
  legacy: false,
  locale,
  fallbackLocale: DEFAULT_LOCALE,
  messages,
  missingWarn: import.meta.env.DEV,
  fallbackWarn: import.meta.env.DEV
})

export const setLocale = (lang) => {
  const nextLocale = normalizeLocale(lang)
  i18n.global.locale.value = nextLocale
  localStorage.setItem('locale', nextLocale)
  document.cookie = `locale=${nextLocale}; path=/; max-age=31536000`
}

export const getLocale = () => i18n.global.locale.value
export const getElementLocaleKey = () => normalizeLocale(i18n.global.locale.value)

export default i18n
