import 'package:shared_preferences/shared_preferences.dart';

/// Low-sensitivity persistence — server address, username, save-password
/// preference. Stored in `SharedPreferences` because Android/iOS app sandboxes
/// already isolate these values from other apps and the value of using
/// hardware-backed storage is small here.
class AppStorage {
  AppStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _keyServerAddress = 'serverAddress';
  static const _keyUsername = 'username';
  static const _keySavePassword = 'savePassword';
  static const _keyLocale = 'locale';
  static const _keyEditorFontSize = 'editor.fontSize';
  static const _keyEditorWordWrap = 'editor.wordWrap';
  static const _keyEditorTheme = 'editor.theme';

  String get serverAddress => _prefs.getString(_keyServerAddress) ?? '';
  Future<void> setServerAddress(String value) =>
      _prefs.setString(_keyServerAddress, value);

  String get username => _prefs.getString(_keyUsername) ?? '';
  Future<void> setUsername(String value) =>
      _prefs.setString(_keyUsername, value);

  bool get savePassword => _prefs.getBool(_keySavePassword) ?? false;
  Future<void> setSavePassword(bool value) =>
      _prefs.setBool(_keySavePassword, value);

  /// `null` means "follow system locale". Otherwise a BCP-47-ish language code
  /// like `en` or `zh`.
  String? get localeCode {
    final value = _prefs.getString(_keyLocale);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> setLocaleCode(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_keyLocale);
    } else {
      await _prefs.setString(_keyLocale, value);
    }
  }

  static const editorFontSizeMin = 10;
  static const editorFontSizeMax = 24;
  static const editorFontSizeDefault = 13;

  int get editorFontSize {
    final value = _prefs.getInt(_keyEditorFontSize) ?? editorFontSizeDefault;
    if (value < editorFontSizeMin) return editorFontSizeMin;
    if (value > editorFontSizeMax) return editorFontSizeMax;
    return value;
  }

  Future<void> setEditorFontSize(int value) =>
      _prefs.setInt(_keyEditorFontSize, value);

  bool get editorWordWrap => _prefs.getBool(_keyEditorWordWrap) ?? false;
  Future<void> setEditorWordWrap(bool value) =>
      _prefs.setBool(_keyEditorWordWrap, value);

  /// `'dark'` (default) or `'light'`.
  String get editorTheme => _prefs.getString(_keyEditorTheme) ?? 'dark';
  Future<void> setEditorTheme(String value) =>
      _prefs.setString(_keyEditorTheme, value);

  // ── Terminal settings ──

  static const _keyTermFontSize = 'terminal.fontSize';
  static const _keyTermFontFamily = 'terminal.fontFamily';
  static const _keyTermTheme = 'terminal.themePreset';
  static const _keyTermAutoServerStatus = 'terminal.autoServerStatus';

  double get terminalFontSize => _prefs.getDouble(_keyTermFontSize) ?? 12.0;
  Future<void> setTerminalFontSize(double v) =>
      _prefs.setDouble(_keyTermFontSize, v);

  String get terminalFontFamily =>
      _prefs.getString(_keyTermFontFamily) ?? 'monospace';
  Future<void> setTerminalFontFamily(String v) =>
      _prefs.setString(_keyTermFontFamily, v);

  String get terminalThemePreset => _prefs.getString(_keyTermTheme) ?? 'warm';
  Future<void> setTerminalThemePreset(String v) =>
      _prefs.setString(_keyTermTheme, v);

  bool get terminalAutoServerStatus =>
      _prefs.getBool(_keyTermAutoServerStatus) ?? true;
  Future<void> setTerminalAutoServerStatus(bool v) =>
      _prefs.setBool(_keyTermAutoServerStatus, v);

  // ── App theme ──

  static const _keyThemeMode = 'app.themeMode';

  String get themeMode => _prefs.getString(_keyThemeMode) ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString(_keyThemeMode, v);
}
