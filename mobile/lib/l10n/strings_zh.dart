/// Simplified Chinese UI strings. Keys must mirror `stringsEn`; missing keys
/// will fall back to English at runtime.
const Map<String, String> stringsZh = {
  // App
  'app.title': 'EasyNode',
  'app.subtitle': '移动端终端访问',

  // Common
  'common.cancel': '取消',
  'common.continue': '继续',
  'common.retry': '重试',
  'common.connect': '连接',
  'common.close': '关闭',
  'common.closeAll': '全部关闭',
  'common.all': '全部',
  'common.search': '搜索',
  'common.closeSearch': '关闭搜索',
  'common.system': '跟随系统',

  // Login
  'login.serverAddress': '服务端地址',
  'login.serverAddressHint': 'https://example.com',
  'login.username': '用户名',
  'login.password': '密码',
  'login.showPassword': '显示密码',
  'login.hidePassword': '隐藏密码',
  'login.mfa': 'MFA 验证码（可选）',
  'login.sessionDuration': '会话有效期',
  'login.savePassword': '安全保存密码',
  'login.submit': '登录',
  'login.failed': '登录失败',
  'login.httpRiskTitle': 'HTTP 连接未加密',
  'login.httpRiskBody': '您的所有数据可能会被盗取，建议使用 HTTPS。',
  'login.errEmptyUsername': '请输入用户名',
  'login.errEmptyPassword': '请输入密码',
  'login.errInvalidServer': '请输入有效的服务端地址',
  'login.errSchemeUnsupported': '服务端地址仅支持 http 或 https',
  'login.errLoginGeneric': '登录失败',
  'login.errMissingFields': '服务端登录响应缺少必要字段',
  'login.expiry.temporary': '临时会话，1 小时',
  'login.expiry.currentDay': '今天',
  'login.expiry.threeDays': '3 天',
  'login.expiry.sevenDays': '7 天',

  // Tabs
  'tabs.servers': '服务器',
  'tabs.sftp': '文件',
  'tabs.scripts': '脚本',
  'tabs.settings': '设置',

  // Servers tab
  'servers.title': '服务器',
  'servers.addServer': '新增服务器',
  'servers.searchHint': '按名称 / 主机 / 用户名 / 标签 / 分组搜索',
  'servers.emptyHint': '还没有服务器，请在 Web 端添加后下拉刷新。',
  'servers.emptyFiltered': '没有匹配的服务器。',
  'servers.notConfigured': '未配置',
  'servers.fetchSshFailed': '获取 SSH 连接信息失败：{0}',
  'servers.windowsUnsupported': 'Windows 连接暂不支持。',
  'servers.activeTerminalsOne': '1 个活动终端',
  'servers.activeTerminalsMany': '{0} 个活动终端',
  'servers.closeAllTitle': '关闭所有终端？',
  'servers.closeAllBodyOne': '将断开 1 个活动终端。',
  'servers.closeAllBodyMany': '将断开 {0} 个活动终端。',
  'servers.closeAllTooltip': '关闭所有终端',
  'servers.authFallback': '认证',

  // Placeholders
  'sftp.placeholder': '即将上线：浏览和管理远程文件',
  'scripts.placeholder': '即将上线：脚本库',

  // Settings
  'settings.title': '设置',
  'settings.logout': '退出登录',
  'settings.logoutConfirmTitle': '退出登录？',
  'settings.logoutConfirmBody': '这会清除已保存的登录会话。',
  'settings.language': '语言',
  'settings.languageEnglish': 'English',
  'settings.languageChinese': '中文',

  // Terminal
  'terminal.title': '终端',
  'terminal.noActive': '没有活动的终端',
  'terminal.reconnect': '重新连接',
  'terminal.closeTerminal': '关闭终端',
  'terminal.closeAllTerminals': '关闭所有终端',
  'terminal.closeAllTitle': '关闭所有终端？',
  'terminal.closeAllBodyMany': '将断开 {0} 个活动终端。',
  'terminal.newTerminal': '新建终端',
  'terminal.noServers': '没有可用的服务器',
  'terminal.loadServersFailed': '加载服务器失败：{0}',
  'terminal.openFailed': '打开终端失败：{0}',

  'terminal.status.connecting': '正在连接',
  'terminal.status.connected': '已连接',
  'terminal.status.disconnected': '已断开',
  'terminal.status.error': '错误',
};
