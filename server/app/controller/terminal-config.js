const { TerminalConfigDB } = require('../utils/db-class')

// 终端默认配置
const DEFAULT_TERMINAL_CONFIG = {
  themeName: 'Cobalt_Neon',
  fontFamily: 'monospace', // 使用多平台通用的等宽字体
  fontSize: 16,
  fontColor: '', // 使用主题字体颜色
  cursorColor: '#00ff41', // 使用主题光标颜色
  selectionColor: 'rgb(226, 232, 38)', // 选中颜色
  background: '', // 使用主题背景
  keywordHighlight: false, // 关键词高亮
  highlightDebugMode: false,
  customHighlightRules: null, // null表示使用默认规则
  autoExecuteScript: false, // 自动执行脚本
  autoReconnect: true, // 断线自动重连
  autoShowContextMenu: true // 选中文本后自动显示右键菜单
}

const terminalConfigDB = new TerminalConfigDB().getInstance()

// 获取用户的终端配置
async function getTerminalConfig({ res }) {
  try {
    // 查找最新的用户配置
    let existingConfig = await terminalConfigDB.findOneAsync({}).sort({ updateTime: -1 })

    if (!existingConfig) {
      // 如果没有用户配置，直接返回默认配置
      existingConfig = DEFAULT_TERMINAL_CONFIG
    } else {
      // 合并默认配置和用户配置
      existingConfig = {
        ...DEFAULT_TERMINAL_CONFIG,
        ...existingConfig // 用户配置覆盖默认配置
      }
    }

    res.success({ data: existingConfig })
  } catch (error) {
    console.error('Error in getTerminalConfig:', error)
    res.fail({ msg: '服务器内部错误，请稍后重试' })
  }
}

// 保存用户的终端配置
async function saveTerminalConfig({ res, request }) {
  const configData = request.body || {} // 前端目前只包含纯配置数据，不需要过滤字段

  try {
    const existingConfig = await terminalConfigDB.findOneAsync({}).sort({ updateTime: -1 })

    const updateData = {
      ...configData,
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

    res.success({ msg: '配置保存成功' })
  } catch (error) {
    console.error('Error in saveTerminalConfig:', error)
    res.fail({ msg: '服务器内部错误，请稍后重试' })
  }
}

module.exports = {
  getTerminalConfig,
  saveTerminalConfig
}