import i18n from '@/i18n'
import ping from '../utils/ping'

const t = i18n.global.t
const getLocale = () => i18n.global.locale.value

export default {
  toFixed(value, count = 1) {
    value = Number(value)
    return isNaN(value) ? '--' : value.toFixed(count)
  },
  formatTime(second = 0, target = 'day') {
    let day = Math.floor(second / 60 / 60 / 24)
    let hour = Math.floor(second / 60 / 60 % 24)
    let minute = Math.floor(second / 60 % 60)
    let remainSecond = Math.floor(second % 60)
    if (target === 'day') {
      return t('tools.dayOnly', { day })
    } else if (target === 'hour') {
      return t('tools.dayHour', { day, hour })
    } else if (target === 'minute') {
      return t('tools.dayHourMinute', { day, hour, minute })
    }
    return t('tools.dayHourMinuteSecond', { day, hour, minute, second: remainSecond })
  },
  formatNetSpeed(netSpeedMB) {
    netSpeedMB = Number(netSpeedMB) || 0
    if (netSpeedMB >= 1) return `${ netSpeedMB.toFixed(2) } MB/s`
    return `${ (netSpeedMB * 1024).toFixed(1) } KB/s`
  },
  // format: time OR date
  formatTimestamp: (timestamp, format = 'time', afterSeparator = ':') => {
    if (typeof(timestamp) !== 'number') return '--'
    let date = new Date(timestamp)
    let locale = getLocale() === 'en' ? 'en-US' : 'zh-CN'
    if (format === 'date') {
      return date.toLocaleDateString(locale)
    }
    if (format === 'time') {
      const [datePart] = date.toLocaleDateString(locale).split(',')
      const timePart = [date.getHours(), date.getMinutes(), date.getSeconds()]
        .map(num => String(num).padStart(2, '0'))
        .join(afterSeparator)
      return `${ datePart } ${ timePart }`
    }
    const [datePart] = date.toLocaleDateString(locale).split(',')
    const timePart = [date.getHours(), date.getMinutes(), date.getSeconds()]
      .map(num => String(num).padStart(2, '0'))
      .join(afterSeparator)
    return `${ datePart } ${ timePart }`
  },
  ping
}
