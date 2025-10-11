const { TerminalConfigDB } = require('../utils/db-class')

// 终端默认配置
const DEFAULT_TERMINAL_CONFIG = {
  themeName: 'Afterglow',
  fontFamily: 'monospace', // 使用多平台通用的等宽字体
  fontSize: 16,
  fontColor: '', // 使用主题字体颜色
  cursorColor: '', // 使用主题光标颜色
  selectionColor: '#264f78', // 深蓝色选中颜色，适合深色主题
  background: '', // 使用主题背景
  keywordHighlight: true,
  highlightDebugMode: false,
  customHighlightRules: null, // null表示使用默认规则
  autoExecuteScript: false, // 脚本执行模式
  autoReconnect: false, // 自动重连
  autoShowContextMenu: true // 选中文本后自动显示右键菜单
}

const terminalConfigDB = new TerminalConfigDB().getInstance()

// 获取用户的终端配置
async function getTerminalConfig(ctx) {
  const { uid } = ctx.request.query

  if (!uid || typeof uid !== 'string' || uid.trim() === '') {
    ctx.body = { success: false, message: '无效的uid参数' }
    return
  }

  try {
    // 查找用户配置
    let userConfig = await terminalConfigDB.findOneAsync({ uid, isDefault: { $ne: true } })

    if (!userConfig) {
      // 如果没有用户配置，直接返回默认配置
      userConfig = {
        ...DEFAULT_TERMINAL_CONFIG,
        uid
      }
    } else {
      // 合并默认配置和用户配置
      userConfig = {
        ...DEFAULT_TERMINAL_CONFIG,
        ...userConfig // 用户配置覆盖默认配置
      }
    }

    ctx.body = { success: true, data: userConfig }
  } catch (error) {
    console.error('Error in getTerminalConfig:', error)
    ctx.body = { success: false, message: '服务器内部错误，请稍后重试' }
  }
}

// 保存用户的终端配置
async function saveTerminalConfig(ctx) {
  const { uid, isDefault, name, _id, createTime, ...configData } = ctx.request.body

  if (!uid || typeof uid !== 'string' || uid.trim() === '') {
    ctx.body = { success: false, message: '无效的uid参数' }
    return
  }

  try {
    const existingConfig = await terminalConfigDB.findOneAsync({ uid, isDefault: { $ne: true } })

    const updateData = {
      ...configData,
      uid,
      updateTime: new Date().toISOString()
    }

    if (existingConfig) {
      // 更新现有配置
      await terminalConfigDB.updateAsync(
        { _id: existingConfig._id },
        { $set: updateData }
      )
    } else {
      // 创建新配置
      updateData.createTime = new Date().toISOString()
      await terminalConfigDB.insertAsync(updateData)
    }

    ctx.body = { success: true, message: '配置保存成功' }
  } catch (error) {
    console.error('Error in saveTerminalConfig:', error)
    ctx.body = { success: false, message: '服务器内部错误，请稍后重试' }
  }
}

module.exports = {
  getTerminalConfig,
  saveTerminalConfig
}