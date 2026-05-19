/// English UI strings. Treated as the source of truth — every key referenced
/// from the app must exist here. [AppLocalizations.tr] falls back to this
/// table when a key is missing in another locale.
const Map<String, String> stringsEn = {
  // App
  'app.title': 'EasyNode',
  'app.subtitle': 'Mobile terminal access',

  // Common
  'common.cancel': 'Cancel',
  'common.continue': 'Continue',
  'common.retry': 'Retry',
  'common.connect': 'Connect',
  'common.close': 'Close',
  'common.closeAll': 'Close all',
  'common.search': 'Search',
  'common.closeSearch': 'Close search',
  'common.system': 'System default',

  // Login page
  'login.serverAddress': 'Server address',
  'login.serverAddressHint': 'https://example.com',
  'login.username': 'Username',
  'login.password': 'Password',
  'login.showPassword': 'Show password',
  'login.hidePassword': 'Hide password',
  'login.mfa': 'MFA code (optional)',
  'login.sessionDuration': 'Session duration',
  'login.savePassword': 'Save password securely',
  'login.submit': 'Log in',
  'login.failed': 'Login failed',
  'login.httpRiskTitle': 'HTTP is not encrypted',
  'login.httpRiskBody':
      'Your token and session cookie can be intercepted. Use HTTPS when possible.',
  'login.errEmptyUsername': 'Please enter a username',
  'login.errEmptyPassword': 'Please enter a password',
  'login.errInvalidServer': 'Please enter a valid server address',
  'login.errSchemeUnsupported': 'Server address must use http or https',
  'login.errLoginGeneric': 'Login failed',
  'login.errMissingFields': 'Server login response is missing required fields',

  // Login expiry options
  'login.expiry.temporary': 'Temporary, 1 hour',
  'login.expiry.currentDay': 'Today',
  'login.expiry.threeDays': '3 days',
  'login.expiry.sevenDays': '7 days',

  // Main shell tabs
  'tabs.servers': 'Servers',
  'tabs.sftp': 'SFTP',
  'tabs.scripts': 'Scripts',
  'tabs.settings': 'Settings',

  // Servers tab
  'servers.title': 'Servers',
  'servers.addServer': 'Add server',
  'servers.searchHint': 'Search by name, host, user, tag, or group',
  'servers.emptyHint': 'No servers yet. Pull to refresh after adding hosts on web.',
  'servers.emptyFiltered': 'No matching servers.',
  'servers.notConfigured': 'Not configured',
  'servers.fetchSshFailed': 'Failed to get SSH config: {0}',
  'servers.activeTerminalsOne': '1 active terminal',
  'servers.activeTerminalsMany': '{0} active terminals',
  'servers.closeAllTitle': 'Close all terminals?',
  'servers.closeAllBodyOne': 'This will disconnect 1 active terminal.',
  'servers.closeAllBodyMany': 'This will disconnect {0} active terminals.',
  'servers.closeAllTooltip': 'Close all terminals',
  'servers.authFallback': 'auth',

  // SFTP / Scripts placeholders
  'sftp.placeholder': 'Coming soon: browse and manage remote files',
  'scripts.placeholder': 'Coming soon: script library',

  // Settings
  'settings.title': 'Settings',
  'settings.logout': 'Log out',
  'settings.logoutConfirmTitle': 'Log out?',
  'settings.logoutConfirmBody': 'This will clear the saved login session.',
  'settings.language': 'Language',
  'settings.languageEnglish': 'English',
  'settings.languageChinese': '中文',

  // Terminal shell
  'terminal.title': 'Terminal',
  'terminal.noActive': 'No active terminal',
  'terminal.reconnect': 'Reconnect',
  'terminal.closeTerminal': 'Close terminal',
  'terminal.newTerminal': 'New terminal',
  'terminal.noServers': 'No servers available',
  'terminal.loadServersFailed': 'Failed to load servers: {0}',
  'terminal.openFailed': 'Failed to open terminal: {0}',

  'terminal.status.connecting': 'Connecting',
  'terminal.status.connected': 'Connected',
  'terminal.status.disconnected': 'Disconnected',
  'terminal.status.error': 'Error',
};
