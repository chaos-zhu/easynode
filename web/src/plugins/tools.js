import ping from '../utils/ping'

export default {
  toFixed(value, count = 1) {
    value = Number(value)
    return isNaN(value) ? '--' : value.toFixed(count)
  },
  formatTime(second = 0) {
    let day = Math.floor(second / 60 / 60 / 24)
    let hour = Math.floor(second / 60 / 60 % 24)
    let minute = Math.floor(second / 60 % 60)
    return `${ day }天${ hour }时${ minute }分`
  },
  formatNetSpeed(netSpeedMB) {
    netSpeedMB = Number(netSpeedMB) || 0
    if (netSpeedMB >= 1) return `${ netSpeedMB.toFixed(2) } MB/s`
    return `${ (netSpeedMB * 1024).toFixed(1) } KB/s`
  },
  // format: time OR date
  formatTimestamp: (timestamp, format = 'time') => {
    if(typeof(timestamp) !== 'number') return '--'
    let date = new Date(timestamp)
    let padZero = (num) => String(num).padStart(2, '0')
    let year = date.getFullYear()
    let mounth = padZero(date.getMonth() + 1)
    let day = padZero(date.getDate())
    let hours = padZero(date.getHours())
    let minute = padZero(date.getMinutes())
    let second = padZero(date.getSeconds())
    switch (format) {
      case 'date':
        return `${ year }-${ mounth }-${ day }`
      case 'time':
        return `${ year }-${ mounth }-${ day } ${ hours }:${ minute }:${ second }`
      default:
        return `${ year }-${ mounth }-${ day } ${ hours }:${ minute }:${ second }`
    }
  },
  ping
}
