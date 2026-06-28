const { exec } = require('child_process')
const crypto = require('crypto')
const os = require('os')
const net = require('net')
const iconv = require('iconv-lite')
const axios = require('axios')
const request = axios.create({ timeout: 3000 })
const { plusServers } = require('./plus-server')

// 为空时请求本地IP
const getNetIPInfo = async (searchIp = '') => {
  // console.log('searchIp:', searchIp)
  if (isLocalIP(searchIp)) {
    return {
      ip: searchIp,
      country: '本地',
      city: '局域网',
      error: null
    }
  }
  try {
    let date = Date.now()
    let ipUrls = [
      // 45次/分钟&支持中文(无限制)
      `http://ip-api.com/json/${ searchIp }?lang=zh-CN`,
      // 10000次/月&支持中文(依赖IP计算调用次数)
      `http://ipwho.is/${ searchIp }?lang=zh-CN`,
      // 1500次/天(依赖密钥, 超出自行注册)
      `https://api.ipdata.co/${ searchIp }?api-key=c6d4d04d5f11f2cd0839ee03c47c58621d74e361c945b5c1b4f668f3`,
      // 50000/月(依赖密钥, 超出自行注册)
      `https://ipinfo.io/${ searchIp }/json?token=41c48b54f6d78f`,
      // 1000次/天(依赖密钥, 超出自行注册)
      `https://api.ipgeolocation.io/ipgeo?apiKey=105fc2c7e8864ec08b98e1ad4e8cbc6d&ip=${ searchIp }`,
      // 1000次/天(依赖IP计算调用次数)
      `https://ipapi.co${ searchIp ? `/${ searchIp }` : '' }/json`,
      // 国内IP138提供(无限制)
      `https://sp1.baidu.com/8aQDcjqpAAV3otqbppnN2DJv/api.php?query=${ searchIp }&resource_id=5809`
    ]
    let result = await Promise.allSettled(ipUrls.map(url => request.get(url)))

    let [ipApi, ipwho, ipdata, ipinfo, ipgeolocation, ipApi01, ip138] = result

    let searchResult = []
    if (ipApi.status === 'fulfilled') {
      let { query: ip, country, regionName, city } = ipApi.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if (ipwho.status === 'fulfilled') {
      let { ip, country, region: regionName, city } = ipwho.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if (ipdata.status === 'fulfilled') {
      let { ip, country_name: country, region: regionName, city } = ipdata.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if (ipinfo.status === 'fulfilled') {
      let { ip, country, region: regionName, city } = ipinfo.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if (ipgeolocation.status === 'fulfilled') {
      let { ip, country_name: country, state_prov: regionName, city } = ipgeolocation.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if (ipApi01.status === 'fulfilled') {
      let { ip, country_name: country, region: regionName, city } = ipApi01.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if (ip138.status === 'fulfilled') {
      let [res] = ip138.value?.data?.data || []
      let { origip: ip, location: country, city = '', regionName = '' } = res || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }
    console.log(searchResult)
    let validInfo = searchResult.find(item => Boolean(item.country))
    return validInfo || { ip: '获取IP信息API出错,请排查或更新API', country: '未知', city: '未知', date }
  } catch (error) {
    return {
      ip: '未知',
      country: '未知',
      city: '未知',
      error
    }
  }
}

const getLocalNetIP = async () => {
  try {
    let ipUrls = [
      'http://whois.pconline.com.cn/ipJson.jsp?json=true',
      'https://www.ip.cn/api/index?ip=&type=0',
      'https://freeipapi.com/api/json'
    ]
    let result = await Promise.allSettled(ipUrls.map(url => axios.get(url)))
    let [pconline, ipCN, freeipapi] = result
    if (pconline.status === 'fulfilled') {
      let ip = pconline.value?.data?.ip
      if (ip) return ip
    }
    if (ipCN.status === 'fulfilled') {
      let ip = ipCN.value?.data?.ip
      if (ip) return ip
    }
    if (freeipapi.status === 'fulfilled') {
      let ip = freeipapi.value?.data?.ipAddress
      if (ip) return ip
    }
    return null
  } catch (error) {
    console.error('getIpInfo Error: ', error?.message || error)
    return null
  }
}

function isLocalIP(ip) {
  // Check if IPv4 or IPv6 address
  const isIPv4 = net.isIPv4(ip)
  const isIPv6 = net.isIPv6(ip)

  // Local IPv4 ranges
  const localIPv4Ranges = [
    { start: '10.0.0.0', end: '10.255.255.255' },
    { start: '172.16.0.0', end: '172.31.255.255' },
    { start: '192.168.0.0', end: '192.168.255.255' },
    { start: '127.0.0.0', end: '127.255.255.255' } // Loopback
  ]

  // Local IPv6 ranges
  const localIPv6Ranges = [
    '::1', // Loopback
    'fc00::', // Unique local address
    'fd00::' // Unique local address
  ]

  function isInRange(ip, start, end) {
    const ipNum = ipToNumber(ip)
    return ipNum >= ipToNumber(start) && ipNum <= ipToNumber(end)
  }

  function ipToNumber(ip) {
    return ip.split('.').reduce((acc, octet) => (acc << 8) + parseInt(octet, 10), 0)
  }

  if (isIPv4) {
    for (const range of localIPv4Ranges) {
      if (isInRange(ip, range.start, range.end)) {
        return true
      }
    }
  }

  if (isIPv6) {
    if (localIPv6Ranges.includes(ip)) {
      return true
    }

    // Handle IPv4-mapped IPv6 addresses (e.g., ::ffff:192.168.1.1)
    if (ip.startsWith('::ffff:')) {
      const ipv4Part = ip.split('::ffff:')[1]
      if (ipv4Part && net.isIPv4(ipv4Part)) {
        for (const range of localIPv4Ranges) {
          if (isInRange(ipv4Part, range.start, range.end)) {
            return true
          }
        }
      }
    }
  }

  return false
}

const throwError = ({ status = 500, msg = 'defalut error' } = {}) => {
  const err = new Error(msg)
  err.status = status // 主动抛错
  throw err
}

const isIP = (ip = '') => {
  const isIPv4 = /^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$/
  const isIPv6 = /^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}|:((:[\da−fA−F]1,4)1,6|:)|:((:[\da−fA−F]1,4)1,6|:)|^[\da-fA-F]{1,4}:((:[\da-fA-F]{1,4}){1,5}|:)|([\da−fA−F]1,4:)2((:[\da−fA−F]1,4)1,4|:)|([\da−fA−F]1,4:)2((:[\da−fA−F]1,4)1,4|:)|^([\da-fA-F]{1,4}:){3}((:[\da-fA-F]{1,4}){1,3}|:)|([\da−fA−F]1,4:)4((:[\da−fA−F]1,4)1,2|:)|([\da−fA−F]1,4:)4((:[\da−fA−F]1,4)1,2|:)|^([\da-fA-F]{1,4}:){5}:([\da-fA-F]{1,4})?|([\da−fA−F]1,4:)6:|([\da−fA−F]1,4:)6:/
  return isIPv4.test(ip) || isIPv6.test(ip)
}

const randomStr = (len = 16) => {
  const str = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678'
  const array = new Uint32Array(len)
  crypto.getRandomValues(array) // 安全随机
  return Array.from(array, x => str[x % str.length]).join('')
}

// 获取UTC-x时间
const getUTCDate = (num = 8) => {
  let date = new Date()
  let now_utc = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(),
    date.getUTCDate(), date.getUTCHours() + num,
    date.getUTCMinutes(), date.getUTCSeconds())
  return new Date(now_utc)
}

const formatTimestamp = (timestamp = Date.now(), format = 'time') => {
  if (typeof (timestamp) !== 'number') return '--'
  let date = new Date(timestamp)
  let padZero = (num) => String(num).padStart(2, '0')
  let year = date.getFullYear()
  let mounth = padZero(date.getMonth() + 1)
  let day = padZero(date.getDate())
  let hours = padZero(date.getHours())
  let minute = padZero(date.getMinutes())
  let second = padZero(date.getSeconds())
  let weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
  let week = weekday[date.getDay()]
  switch (format) {
    case 'date':
      return `${ year }-${ mounth }-${ day }`
    case 'week':
      return `${ year }-${ mounth }-${ day } ${ week }`
    case 'hour':
      return `${ year }-${ mounth }-${ day } ${ hours }`
    case 'time':
      return `${ year }-${ mounth }-${ day } ${ hours }:${ minute }:${ second }`
    default:
      return `${ year }-${ mounth }-${ day } ${ hours }:${ minute }:${ second }`
  }
}

function resolvePath(dir, path) {
  return path.resolve(dir, path)
}

let shellThrottle = (fn, delay = 1000) => {
  let timer = null
  let args = null
  function throttled() {
    args = arguments
    if (!timer) {
      timer = setTimeout(() => {
        fn(...args)
        timer = null
      }, delay)
    }
  }
  function delayMs() {
    return new Promise(resolve => setTimeout(resolve, delay))
  }
  throttled.last = async () => {
    await delayMs()
    fn(...args)
  }
  return throttled
}

const fileTransferThrottle = (fn, delay = 1500) => {
  let lastCall = 0
  return function (...args) {
    const now = Date.now()
    if (now - lastCall >= delay) {
      lastCall = now
      fn(...args)
    }
  }
}

const isProd = () => {
  const EXEC_ENV = process.env.EXEC_ENV || 'production'
  return EXEC_ENV === 'production'
}

// 将 IPv6 映射的 IPv4 地址（::ffff:x.x.x.x）规范化为纯 IPv4，保证比较一致性
const normalizeIP = (ip) => {
  if (typeof ip !== 'string') return ''
  ip = ip.trim().toLowerCase()
  if (ip.startsWith('::ffff:')) {
    const ipv4Part = ip.slice(7)
    if (net.isIPv4(ipv4Part)) return ipv4Part
  }
  return ip
}

const isLoopbackIP = (ip) => {
  if (ip === '::1') return true
  if (!net.isIPv4(ip)) return false
  return Number(ip.split('.')[0]) === 127
}

const isPrivateIPv4 = (ip) => {
  if (!net.isIPv4(ip)) return false
  const [first, second] = ip.split('.').map(Number)
  return first === 10 ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168)
}

const isUniqueLocalIPv6 = (ip) => {
  return net.isIPv6(ip) && /^f[cd][0-9a-f]{2}:/i.test(ip)
}

const isTrustedProxyIP = (ip) => {
  ip = normalizeIP(ip)
  return isLoopbackIP(ip) || isPrivateIPv4(ip) || isUniqueLocalIPv6(ip)
}

/**
 * 从连接中提取可信客户端 IP：
 * - 优先使用 TCP 层真实地址（socketRemoteAddress），不可被客户端伪造
 * - 当该地址来自可信代理（本机或 Docker/内网反代）时，才从 x-forwarded-for 取客户端 IP
 * - nginx 使用 proxy_add_x_forwarded_for 时会将真实 IP 追加到末尾，故取最后一个值
 */
const getClientIP = (socketRemoteAddress, xForwardedFor) => {
  const socketIP = normalizeIP(socketRemoteAddress || '')
  if (!isTrustedProxyIP(socketIP)) return socketIP
  if (!xForwardedFor) return socketIP

  const parts = xForwardedFor.split(',').map(item => normalizeIP(item)).filter(Boolean)
  return parts[parts.length - 1] || socketIP
}

const isAllowedIp = (requestIP) => {
  let allowedIPs = Array.isArray(global.ALLOWED_IPS) ? global.ALLOWED_IPS : []
  if (allowedIPs.length === 0) return true
  let flag = allowedIPs.some(item => requestIP.includes(item))
  if (!flag) logger.warn(`requestIP:${ requestIP } 不在允许的IP列表中. 允许的IP列表:${ allowedIPs.join(',') }`)
  return flag
}

const VALID_HOSTNAME = /^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/

function isValidPingTarget(ip) {
  if (typeof ip !== 'string') return false
  const trimmed = ip.trim()
  if (!trimmed || trimmed.length > 253) return false
  if (net.isIP(trimmed)) return true
  return VALID_HOSTNAME.test(trimmed)
}

const ping = (ip, timeout = 5000) => {
  return new Promise((resolve) => {
    if (!isValidPingTarget(ip)) {
      return resolve({ success: false, msg: 'invalid host' })
    }
    ip = ip.trim()
    setTimeout(() => {
      resolve({ success: false, msg: 'ping timeout!' })
    }, timeout)
    let isWin = os.platform() === 'win32'
    const command = isWin ? `ping -n 1 ${ ip }` : `ping -c 1 ${ ip }`
    const options = isWin ? { encoding: 'buffer' } : {}

    exec(command, options, (error, stdout) => {
      if (error) {
        resolve({ success: false, msg: 'ping error!' })
        return
      }
      let output
      if (isWin) {
        output = iconv.decode(stdout, 'cp936')
      } else {
        output = stdout.toString()
      }
      // console.log('output:', output)
      let match
      if (isWin) {
        match = output.match(/平均 = (\d+)ms/)
        if (!match) {
          match = output.match(/Average = (\d+)ms/)
        }
      } else {
        match = output.match(/rtt min\/avg\/max\/mdev = [\d.]+\/([\d.]+)\/[\d.]+\/[\d.]+/)
      }
      if (match) {
        resolve({ success: true, time: parseFloat(match[1]) })
      } else {
        resolve({ success: false, msg: 'Could not find time in ping output!' })
      }
    })
  })
}

async function requestWithFailover(path, options = {}, timeout = 5000) {
  const { method = 'GET', headers = {}, body = null } = options

  for (let i = 0; i < plusServers.length; i++) {
    const server = plusServers[i]
    try {
      const response = await fetch(server + path, {
        method,
        headers,
        body,
        timeout
      })

      // 200+
      if (response.ok || response.status === 403) {
        return response
      }
      // 403
      if (response.status === 403) {
        logger.info(`Plus服务: ${ i + 1 }/${ plusServers.length }: ${ server }${ path } 响应失败，状态码: ${ response.status }`)
        return response
      }

      // 尝试下一个服务器
      if (i < plusServers.length - 1) {
        logger.info(`Plus服务: ${ i + 1 }/${ plusServers.length }: ${ server }${ path } 响应状态码 ${ response.status }，尝试下一个服务器`)
        continue
      }

      // 最后一个服务失败了
      throw new Error(`Plus服务: 所有服务器请求失败: ${ response.status }`)

    } catch (error) {
      // 如果不是最后一个服务，尝试下一个服务器[防止异常报错]
      if (i < plusServers.length - 1) {
        logger.info(`Plus服务: ${ i + 1 }/${ plusServers.length }: ${ server }${ path } 请求失败: ${ error.message }，尝试下一个服务器`)
        continue
      }
      // 如果是最后一个服务器，抛出错误
      logger.error(`Plus服务: 所有服务器请求失败: ${ error.message }`)
      throw error
    }
  }
}

const timingSafeEqual = (a, b) => {
  const bufA = Buffer.from(a)
  const bufB = Buffer.from(b)
  if (bufA.length !== bufB.length) {
    return crypto.timingSafeEqual(
      Buffer.from(a.padEnd(256)),
      Buffer.from(b.padEnd(256))
    )
  }
  return crypto.timingSafeEqual(bufA, bufB)
}

module.exports = {
  getNetIPInfo,
  getLocalNetIP,
  throwError,
  isIP,
  isLocalIP,
  isLoopbackIP,
  randomStr,
  getUTCDate,
  formatTimestamp,
  resolvePath,
  shellThrottle,
  fileTransferThrottle,
  isProd,
  normalizeIP,
  getClientIP,
  isAllowedIp,
  ping,
  requestWithFailover,
  timingSafeEqual
}
