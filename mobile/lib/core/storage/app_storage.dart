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

  String get serverAddress => _prefs.getString(_keyServerAddress) ?? '';
  Future<void> setServerAddress(String value) => _prefs.setString(_keyServerAddress, value);

  String get username => _prefs.getString(_keyUsername) ?? '';
  Future<void> setUsername(String value) => _prefs.setString(_keyUsername, value);

  bool get savePassword => _prefs.getBool(_keySavePassword) ?? false;
  Future<void> setSavePassword(bool value) => _prefs.setBool(_keySavePassword, value);
}
