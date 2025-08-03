const { ProxyDB, HostListDB } = require('../utils/db-class')

const proxyDB = new ProxyDB().getInstance()
const hostListDB = new HostListDB().getInstance()

const getProxyList = async ({ res }) => {
  try {
    let data = await proxyDB.findAsync({})

    data = data.map(item => ({ ...item, id: item._id }))
    data?.sort((a, b) => new Date(b.createTime || 0) - new Date(a.createTime || 0))

    res.success({ data })
  } catch (error) {
    res.fail({ data: false, msg: '获取代理列表失败' })
  }
}

const addProxy = async ({ res, request }) => {
  try {
    let { body: { type, name, host, port, username, password } } = request

    if (!type || !name || !host || !port) {
      return res.fail({ data: false, msg: '参数错误：类型、名称、主机、端口为必填项' })
    }

    // 验证端口号
    const portNum = Number(port)
    if (!Number.isInteger(portNum) || portNum < 1 || portNum > 65535) {
      return res.fail({ data: false, msg: '端口号必须是1-65535之间的整数' })
    }

    let record = {
      type,
      name,
      host,
      port: portNum,
      username: username || '',
      password: password || '',
      createTime: new Date().toISOString()
    }

    await proxyDB.insertAsync(record)
    res.success({ data: '添加成功' })
  } catch (error) {
    res.fail({ data: false, msg: '添加代理失败' })
  }
}

const updateProxy = async ({ res, request }) => {
  try {
    let { params: { id } } = request
    let { body: { type, name, host, port, username, password } } = request

    if (!id || !type || !name || !host || !port) {
      return res.fail({ data: false, msg: '参数错误：ID、类型、名称、主机、端口为必填项' })
    }

    // 验证端口号
    const portNum = Number(port)
    if (!Number.isInteger(portNum) || portNum < 1 || portNum > 65535) {
      return res.fail({ data: false, msg: '端口号必须是1-65535之间的整数' })
    }

    let target = await proxyDB.findOneAsync({ _id: id })
    if (!target) {
      return res.fail({ data: false, msg: `代理ID ${ id } 不存在` })
    }

    await proxyDB.updateAsync(
      { _id: id },
      {
        $set: {
          type,
          name,
          host,
          port: portNum,
          username: username || '',
          password: password || '',
          updateTime: new Date().toISOString()
        }
      }
    )

    res.success({ data: '修改成功' })
  } catch (error) {
    res.fail({ data: false, msg: '修改代理失败' })
  }
}

const removeProxy = async ({ res, request }) => {
  try {
    let { params: { id } } = request

    if (!id) {
      return res.fail({ data: false, msg: '参数错误：缺少代理ID' })
    }

    let target = await proxyDB.findOneAsync({ _id: id })
    if (!target) {
      return res.fail({ data: false, msg: `代理ID ${ id } 不存在` })
    }
    await proxyDB.removeAsync({ _id: id })
    // 删除代理后，将所有使用该代理的实例的proxyServer设置为空
    await hostListDB.updateAsync({ proxyServer: id }, { $set: { proxyServer: '' } })
    res.success({ data: '删除成功' })
  } catch (error) {
    res.fail({ data: false, msg: '删除代理失败' })
  }
}

module.exports = {
  getProxyList,
  addProxy,
  updateProxy,
  removeProxy
}
