import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_storage.dart';
import 'storage_providers.dart';

/// `null` means "follow the system locale".
class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier(this._storage) : super(_loadInitial(_storage));

  final AppStorage _storage;

  static Locale? _loadInitial(AppStorage storage) {
    final code = storage.localeCode;
    if (code == null) return null;
    return Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    if (state?.languageCode == locale?.languageCode) return;
    await _storage.setLocaleCode(locale?.languageCode);
    state = locale;
  }
}

final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier(ref.watch(appStorageProvider));
});
