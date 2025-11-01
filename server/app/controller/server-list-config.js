const { ServerListDB } = require('../utils/db-class')
const serverListDB = new ServerListDB().getInstance()

// 获取服务器列表配置
async function getServerListConfig({ res }) {
  try {
    const config = await serverListDB.findOneAsync({})
    if (!config) {
      // 返回默认配置
      const defaultConfig = {
        columnSettings: {
          selection: true,
          index: true,
          name: true,
          username: true,
          host: true,
          port: true,
          authType: true,
          proxyType: false,
          expired: false,
          consoleUrl: false,
          tag: true
        },
        displayMode: 'group'
      }
      return res.success({ data: defaultConfig })
    }
    // eslint-disable-next-line no-unused-vars
    const { _id, ...configData } = config
    res.success({ data: configData })
  } catch (error) {
    console.error('getServerListConfig error: ', error)
    res.fail({ msg: '获取配置失败' })
  }
}

// 保存服务器列表配置
async function saveServerListConfig({ res, request }) {
  try {
    const { body } = request
    if (!body || typeof body !== 'object') {
      return res.fail({ msg: '参数错误' })
    }

    const existingConfig = await serverListDB.findOneAsync({})

    if (existingConfig) {
      // 更新现有配置
      await serverListDB.updateAsync(
        { _id: existingConfig._id },
        { $set: body },
        {}
      )
    } else {
      // 插入新配置
      await serverListDB.insertAsync(body)
    }

    res.success({ msg: '保存成功' })
  } catch (error) {
    console.error('saveServerListConfig error: ', error)
    res.fail({ msg: '保存配置失败' })
  }
}

module.exports = {
  getServerListConfig,
  saveServerListConfig
}

