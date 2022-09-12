const axios = require('axios')
const request = axios.create({ timeout: 3000 })

// 为空时请求本地IP
const getNetIPInfo = async (searchIp = '') => {
  searchIp = searchIp.replace(/::ffff:/g, '') || '' // fix: nginx反代
  if(['::ffff:', '::1'].includes(searchIp)) searchIp = '127.0.0.1'
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
    if(ipApi.status === 'fulfilled') {
      let { query: ip, country, regionName, city } = ipApi.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if(ipwho.status === 'fulfilled') {
      let { ip, country, region: regionName, city } = ipwho.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if(ipdata.status === 'fulfilled') {
      let { ip, country_name: country, region: regionName, city } = ipdata.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if(ipinfo.status === 'fulfilled') {
      let { ip, country, region: regionName, city } = ipinfo.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if(ipgeolocation.status === 'fulfilled') {
      let { ip, country_name: country, state_prov: regionName, city } = ipgeolocation.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if(ipApi01.status === 'fulfilled') {
      let { ip, country_name: country, region: regionName, city } = ipApi01.value?.data || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }

    if(ip138.status === 'fulfilled') {
      let [res] = ip138.value?.data?.data || []
      let { origip: ip, location: country, city = '', regionName = '' } = res || {}
      searchResult.push({ ip, country, city: `${ regionName } ${ city }`, date })
    }
    console.log(searchResult)
    let validInfo = searchResult.find(item => Boolean(item.country))
    consola.info('查询IP信息：', validInfo)
    return validInfo || { ip: '获取IP信息API出错,请排查或更新API', country: '未知', city: '未知', date }
  } catch (error) {
    consola.error('getIpInfo Error: ', error)
    return {
      ip: '未知',
      country: '未知',
      city: '未知',
      error
    }
  }
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

const randomStr = (len) =>{
  len = len || 16
  let str = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678',
    a = str.length,
    res = ''
  for (let i = 0; i < len; i++) res += str.charAt(Math.floor(Math.random() * a))
  return res
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
  if(typeof(timestamp) !== 'number') return '--'
  let date = new Date(timestamp)
  let padZero = (num) => String(num).padStart(2, '0')
  let year = date.getFullYear()
  let mounth = padZero(date.getMonth() + 1)
  let day = padZero(date.getDate())
  let hours = padZero(date.getHours())
  let minute = padZero(date.getMinutes())
  let second = padZero(date.getSeconds())
  let weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六' ]
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

module.exports = {
  getNetIPInfo,
  throwError,
  isIP,
  randomStr,
  getUTCDate,
  formatTimestamp
}