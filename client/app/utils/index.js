const axios = require('axios')

const getLocalNetIP = async () => {
  try {
    let ipUrls = ['http://ip-api.com/json/?lang=zh-CN', 'http://whois.pconline.com.cn/ipJson.jsp?json=true']
    let { data } = await Promise.race(ipUrls.map(url => axios.get(url)))
    return data.ip || data.query
  } catch (error) {
    console.error('getIpInfo Error: ', error)
    return {
      ip: '未知',
      country: '未知',
      city: '未知',
      error
    }
  }
}

module.exports = {
  getLocalNetIP
}