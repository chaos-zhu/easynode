import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'strings_en.dart';
import 'strings_zh.dart';

/// Lightweight hand-rolled localization layer for the mobile app.
///
/// Why not the generated `flutter gen-l10n` flow? Adding the ARB pipeline and
/// keeping it in sync with the Dart codebase is more ceremony than this app
/// currently needs — we only have ~50 strings and two locales. This class plus
/// the two `Map<String, String>` tables gives the same `S.of(context).foo`
/// ergonomics while staying easy to extend or replace with codegen later.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('zh')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(l10n != null, 'AppLocalizations.delegate not added to MaterialApp');
    return l10n!;
  }

  /// Resolve [preferred] to the closest supported locale. Falls back to
  /// English when no language code matches.
  static Locale resolve(Locale? preferred, Iterable<Locale> supported) {
    if (preferred == null) return const Locale('en');
    for (final s in supported) {
      if (s.languageCode == preferred.languageCode) return s;
    }
    return const Locale('en');
  }

  Map<String, String> get _strings =>
      locale.languageCode == 'zh' ? stringsZh : stringsEn;

  String tr(String key) {
    final value = _strings[key] ?? stringsEn[key];
    if (value == null) {
      assert(() {
        debugPrint('Missing localization key: $key');
        return true;
      }());
      return key;
    }
    return value;
  }

  /// Convenience for messages with positional `{0}`, `{1}` placeholders.
  String trf(String key, List<Object?> args) {
    var s = tr(key);
    for (var i = 0; i < args.length; i++) {
      s = s.replaceAll('{$i}', args[i]?.toString() ?? '');
    }
    return s;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales
          .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
