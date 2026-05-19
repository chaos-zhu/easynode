# Mobile Redesign and I18n Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign all existing Flutter mobile screens using the confirmed DESIGN.md-inspired visual system and add English / Simplified Chinese language switching on Login and Settings.

**Architecture:** Add focused theme and i18n units under `mobile/lib/core`, then apply them to existing pages without changing auth, host-list, SSH, or terminal-session behavior. Locale state is owned by `_AppRoot`, persisted through `AppStorage`, and passed to Login/Main Shell for switch controls.

**Tech Stack:** Flutter 3 / Dart, Material 3, Riverpod, SharedPreferences, flutter_test.

---

## File Structure

- Create `mobile/lib/core/i18n/app_locale.dart`: locale enum, system-locale resolver, display names.
- Create `mobile/lib/core/i18n/app_strings.dart`: English and Simplified Chinese string bundles plus lookup helpers.
- Create `mobile/lib/core/i18n/app_localizations.dart`: inherited localization scope and `context.strings`.
- Modify `mobile/lib/core/storage/app_storage.dart`: persist optional locale code.
- Create `mobile/lib/core/ui/app_tokens.dart`: semantic colors, spacing, radii, and terminal surface tokens.
- Create `mobile/lib/core/ui/app_theme.dart`: Material 3 light/dark-compatible theme definitions.
- Create `mobile/lib/core/ui/language_switcher.dart`: reusable language switch button/sheet.
- Create `mobile/lib/core/ui/notice_box.dart`: shared warning/error notice.
- Create `mobile/lib/core/ui/empty_state.dart`: shared empty-state view for SFTP/Scripts and list states.
- Modify `mobile/lib/app.dart`: bootstrap locale, install app theme/localization scope, pass language controls.
- Modify `mobile/lib/features/auth/login_page.dart`: redesign and localize Login.
- Modify `mobile/lib/features/shell/main_shell_page.dart`: localize navigation and pass locale callback to Settings.
- Modify `mobile/lib/features/shell/settings_tab.dart`: redesign and add language switching.
- Modify `mobile/lib/features/shell/sftp_tab.dart`: replace garbled text with localized empty state.
- Modify `mobile/lib/features/shell/scripts_tab.dart`: replace garbled text with localized empty state.
- Modify `mobile/lib/features/servers/servers_tab.dart`: redesign and localize Servers tab.
- Modify `mobile/lib/features/terminal/terminal_shell_page.dart`: token-driven toolbar styling.
- Modify `mobile/lib/features/terminal/terminal_toolbar.dart`: token-driven shortcut styling.
- Update tests under `mobile/test/features` and add tests under `mobile/test/core`.

## Task 1: I18n Model and Storage

**Files:**
- Create: `mobile/lib/core/i18n/app_locale.dart`
- Create: `mobile/lib/core/i18n/app_strings.dart`
- Create: `mobile/lib/core/i18n/app_localizations.dart`
- Modify: `mobile/lib/core/storage/app_storage.dart`
- Test: `mobile/test/core/i18n/app_locale_test.dart`
- Test: `mobile/test/core/storage/app_storage_locale_test.dart`

- [ ] **Step 1: Write failing locale resolver tests**

Create `mobile/test/core/i18n/app_locale_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/i18n/app_locale.dart';

void main() {
  test('resolves saved locale before system locale', () {
    expect(
      AppLocale.resolve(savedCode: 'en', systemLocale: const Locale('zh', 'CN')),
      AppLocale.english,
    );
    expect(
      AppLocale.resolve(savedCode: 'zh_Hans', systemLocale: const Locale('en')),
      AppLocale.simplifiedChinese,
    );
  });

  test('falls back to system Chinese when no saved locale exists', () {
    expect(
      AppLocale.resolve(savedCode: null, systemLocale: const Locale('zh', 'TW')),
      AppLocale.simplifiedChinese,
    );
  });

  test('falls back to English for unsupported saved or system locale', () {
    expect(
      AppLocale.resolve(savedCode: 'fr', systemLocale: const Locale('ja')),
      AppLocale.english,
    );
  });
}
```

- [ ] **Step 2: Run locale resolver test and verify it fails**

Run:

```bash
cd mobile
flutter test test/core/i18n/app_locale_test.dart
```

Expected: FAIL because `mobile/core/i18n/app_locale.dart` does not exist.

- [ ] **Step 3: Implement locale enum and resolver**

Create `mobile/lib/core/i18n/app_locale.dart`:

```dart
import 'package:flutter/widgets.dart';

enum AppLocale {
  english('en', Locale('en'), 'English'),
  simplifiedChinese('zh_Hans', Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'), '中文');

  const AppLocale(this.storageCode, this.flutterLocale, this.label);

  final String storageCode;
  final Locale flutterLocale;
  final String label;

  static AppLocale fromStorageCode(String? code) {
    return switch (code) {
      'zh_Hans' => AppLocale.simplifiedChinese,
      'en' => AppLocale.english,
      _ => AppLocale.english,
    };
  }

  static AppLocale resolve({
    required String? savedCode,
    required Locale? systemLocale,
  }) {
    if (savedCode == AppLocale.english.storageCode ||
        savedCode == AppLocale.simplifiedChinese.storageCode) {
      return fromStorageCode(savedCode);
    }
    if (systemLocale?.languageCode.toLowerCase() == 'zh') {
      return AppLocale.simplifiedChinese;
    }
    return AppLocale.english;
  }
}
```

- [ ] **Step 4: Run locale resolver test and verify it passes**

Run:

```bash
cd mobile
flutter test test/core/i18n/app_locale_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing storage locale tests**

Create `mobile/test/core/storage/app_storage_locale_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists and clears locale code', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = AppStorage(prefs);

    expect(storage.localeCode, isNull);

    await storage.setLocaleCode('zh_Hans');
    expect(storage.localeCode, 'zh_Hans');

    await storage.setLocaleCode(null);
    expect(storage.localeCode, isNull);
  });
}
```

- [ ] **Step 6: Run storage locale test and verify it fails**

Run:

```bash
cd mobile
flutter test test/core/storage/app_storage_locale_test.dart
```

Expected: FAIL because `AppStorage.localeCode` is not implemented.

- [ ] **Step 7: Add locale persistence to AppStorage**

Modify `mobile/lib/core/storage/app_storage.dart`:

```dart
static const _keyLocaleCode = 'localeCode';

String? get localeCode => _prefs.getString(_keyLocaleCode);
Future<void> setLocaleCode(String? value) {
  if (value == null || value.isEmpty) {
    return _prefs.remove(_keyLocaleCode);
  }
  return _prefs.setString(_keyLocaleCode, value);
}
```

Keep the existing server address, username, and save-password methods unchanged.

- [ ] **Step 8: Run Task 1 tests**

Run:

```bash
cd mobile
flutter test test/core/i18n/app_locale_test.dart test/core/storage/app_storage_locale_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit Task 1**

Run:

```bash
git add mobile/lib/core/i18n/app_locale.dart mobile/lib/core/storage/app_storage.dart mobile/test/core/i18n/app_locale_test.dart mobile/test/core/storage/app_storage_locale_test.dart
git commit -m "feat(mobile): add locale model and storage"
```

## Task 2: String Bundles and Localization Scope

**Files:**
- Modify: `mobile/lib/core/i18n/app_strings.dart`
- Modify: `mobile/lib/core/i18n/app_localizations.dart`
- Test: `mobile/test/core/i18n/app_strings_test.dart`

- [ ] **Step 1: Write failing string bundle tests**

Create `mobile/test/core/i18n/app_strings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/i18n/app_locale.dart';
import 'package:mobile/core/i18n/app_strings.dart';

void main() {
  test('returns English strings', () {
    final strings = AppStrings.forLocale(AppLocale.english);
    expect(strings.loginTitle, 'Connect to your servers.');
    expect(strings.settingsTitle, 'Settings');
    expect(strings.languageSimplifiedChinese, 'Chinese');
  });

  test('returns Simplified Chinese strings', () {
    final strings = AppStrings.forLocale(AppLocale.simplifiedChinese);
    expect(strings.loginTitle, '连接到你的服务器。');
    expect(strings.settingsTitle, '设置');
    expect(strings.languageSimplifiedChinese, '中文');
  });
}
```

- [ ] **Step 2: Run string bundle test and verify it fails**

Run:

```bash
cd mobile
flutter test test/core/i18n/app_strings_test.dart
```

Expected: FAIL because `app_strings.dart` does not exist.

- [ ] **Step 3: Implement AppStrings**

Create `mobile/lib/core/i18n/app_strings.dart` with a const class containing at least these fields:

```dart
import 'app_locale.dart';

class AppStrings {
  const AppStrings({
    required this.appName,
    required this.loginTitle,
    required this.loginSubtitle,
    required this.serverAddress,
    required this.username,
    required this.password,
    required this.mfaCodeOptional,
    required this.sessionDuration,
    required this.savePassword,
    required this.loginButton,
    required this.httpWarningTitle,
    required this.httpWarningBody,
    required this.continueButton,
    required this.serversTitle,
    required this.searchHosts,
    required this.activeTerminal,
    required this.activeTerminals,
    required this.closeAllTerminals,
    required this.connect,
    required this.notConfigured,
    required this.retry,
    required this.settingsTitle,
    required this.language,
    required this.languageEnglish,
    required this.languageSimplifiedChinese,
    required this.logout,
    required this.logoutTitle,
    required this.logoutBody,
    required this.cancel,
    required this.sftpTitle,
    required this.sftpEmptyTitle,
    required this.sftpEmptyBody,
    required this.scriptsTitle,
    required this.scriptsEmptyTitle,
    required this.scriptsEmptyBody,
  });

  final String appName;
  final String loginTitle;
  final String loginSubtitle;
  final String serverAddress;
  final String username;
  final String password;
  final String mfaCodeOptional;
  final String sessionDuration;
  final String savePassword;
  final String loginButton;
  final String httpWarningTitle;
  final String httpWarningBody;
  final String continueButton;
  final String serversTitle;
  final String searchHosts;
  final String activeTerminal;
  final String activeTerminals;
  final String closeAllTerminals;
  final String connect;
  final String notConfigured;
  final String retry;
  final String settingsTitle;
  final String language;
  final String languageEnglish;
  final String languageSimplifiedChinese;
  final String logout;
  final String logoutTitle;
  final String logoutBody;
  final String cancel;
  final String sftpTitle;
  final String sftpEmptyTitle;
  final String sftpEmptyBody;
  final String scriptsTitle;
  final String scriptsEmptyTitle;
  final String scriptsEmptyBody;

  static const english = AppStrings(
    appName: 'EasyNode',
    loginTitle: 'Connect to your servers.',
    loginSubtitle: 'Secure mobile access for SSH operations.',
    serverAddress: 'Server address',
    username: 'Username',
    password: 'Password',
    mfaCodeOptional: 'MFA code (optional)',
    sessionDuration: 'Session duration',
    savePassword: 'Save password securely',
    loginButton: 'Log in',
    httpWarningTitle: 'HTTP is not encrypted',
    httpWarningBody: 'Your token and session cookie can be intercepted. Use HTTPS when possible.',
    continueButton: 'Continue',
    serversTitle: 'Servers',
    searchHosts: 'Search hosts',
    activeTerminal: '1 active terminal',
    activeTerminals: '{count} active terminals',
    closeAllTerminals: 'Close all terminals',
    connect: 'Connect',
    notConfigured: 'Not configured',
    retry: 'Retry',
    settingsTitle: 'Settings',
    language: 'Language',
    languageEnglish: 'English',
    languageSimplifiedChinese: 'Chinese',
    logout: 'Log out',
    logoutTitle: 'Log out?',
    logoutBody: 'This will clear the saved login session.',
    cancel: 'Cancel',
    sftpTitle: 'SFTP',
    sftpEmptyTitle: 'SFTP is not available yet',
    sftpEmptyBody: 'Remote file browsing and management will be added in a later version.',
    scriptsTitle: 'Scripts',
    scriptsEmptyTitle: 'Scripts are not available yet',
    scriptsEmptyBody: 'Script library features will be added in a later version.',
  );

  static const simplifiedChinese = AppStrings(
    appName: 'EasyNode',
    loginTitle: '连接到你的服务器。',
    loginSubtitle: '为 SSH 运维提供安全的移动端访问。',
    serverAddress: '服务器地址',
    username: '用户名',
    password: '密码',
    mfaCodeOptional: 'MFA 验证码（可选）',
    sessionDuration: '会话有效期',
    savePassword: '安全保存密码',
    loginButton: '登录',
    httpWarningTitle: 'HTTP 未加密',
    httpWarningBody: '登录 token 和 session cookie 可能被截获。建议尽量使用 HTTPS。',
    continueButton: '继续',
    serversTitle: '服务器',
    searchHosts: '搜索主机',
    activeTerminal: '1 个终端运行中',
    activeTerminals: '{count} 个终端运行中',
    closeAllTerminals: '关闭所有终端',
    connect: '连接',
    notConfigured: '未配置',
    retry: '重试',
    settingsTitle: '设置',
    language: '语言',
    languageEnglish: '英语',
    languageSimplifiedChinese: '中文',
    logout: '退出登录',
    logoutTitle: '退出登录？',
    logoutBody: '这会清除当前保存的登录会话。',
    cancel: '取消',
    sftpTitle: 'SFTP',
    sftpEmptyTitle: 'SFTP 暂未开放',
    sftpEmptyBody: '远程文件浏览和管理将在后续版本加入。',
    scriptsTitle: '脚本',
    scriptsEmptyTitle: '脚本库暂未开放',
    scriptsEmptyBody: '脚本库功能将在后续版本加入。',
  );

  static AppStrings forLocale(AppLocale locale) {
    return switch (locale) {
      AppLocale.english => english,
      AppLocale.simplifiedChinese => simplifiedChinese,
    };
  }
}
```

- [ ] **Step 4: Implement localization scope**

Create `mobile/lib/core/i18n/app_localizations.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'app_locale.dart';
import 'app_strings.dart';

class AppLocalizations extends InheritedWidget {
  const AppLocalizations({
    super.key,
    required this.locale,
    required this.strings,
    required super.child,
  });

  final AppLocale locale;
  final AppStrings strings;

  static AppLocalizations of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppLocalizations>();
    assert(result != null, 'No AppLocalizations found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(AppLocalizations oldWidget) {
    return locale != oldWidget.locale || strings != oldWidget.strings;
  }
}

extension AppLocalizationsContext on BuildContext {
  AppStrings get strings => AppLocalizations.of(this).strings;
  AppLocale get appLocale => AppLocalizations.of(this).locale;
}
```

- [ ] **Step 5: Run Task 2 tests**

Run:

```bash
cd mobile
flutter test test/core/i18n/app_strings_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
git add mobile/lib/core/i18n/app_strings.dart mobile/lib/core/i18n/app_localizations.dart mobile/test/core/i18n/app_strings_test.dart
git commit -m "feat(mobile): add localized string bundles"
```

## Task 3: Theme Tokens and Shared UI Components

**Files:**
- Create: `mobile/lib/core/ui/app_tokens.dart`
- Create: `mobile/lib/core/ui/app_theme.dart`
- Create: `mobile/lib/core/ui/language_switcher.dart`
- Create: `mobile/lib/core/ui/notice_box.dart`
- Create: `mobile/lib/core/ui/empty_state.dart`
- Test: `mobile/test/core/ui/app_theme_test.dart`

- [ ] **Step 1: Write failing theme smoke test**

Create `mobile/test/core/ui/app_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/app_theme.dart';
import 'package:mobile/core/ui/app_tokens.dart';

void main() {
  test('light theme exposes EasyNode tokens and black primary button color', () {
    final theme = EasyNodeTheme.light();
    final tokens = theme.extension<EasyNodeTokens>();

    expect(tokens, isNotNull);
    expect(tokens!.canvas, const Color(0xffffffff));
    expect(theme.filledButtonTheme.style?.backgroundColor?.resolve({}), const Color(0xff000000));
  });
}
```

- [ ] **Step 2: Run theme test and verify it fails**

Run:

```bash
cd mobile
flutter test test/core/ui/app_theme_test.dart
```

Expected: FAIL because theme files do not exist.

- [ ] **Step 3: Implement tokens**

Create `mobile/lib/core/ui/app_tokens.dart`:

```dart
import 'package:flutter/material.dart';

@immutable
class EasyNodeTokens extends ThemeExtension<EasyNodeTokens> {
  const EasyNodeTokens({
    required this.canvas,
    required this.canvasSoft,
    required this.card,
    required this.ink,
    required this.body,
    required this.muted,
    required this.hairline,
    required this.hairlineStrong,
    required this.primaryAction,
    required this.onPrimaryAction,
    required this.terminalBackground,
    required this.terminalForeground,
    required this.success,
    required this.warning,
  });

  final Color canvas;
  final Color canvasSoft;
  final Color card;
  final Color ink;
  final Color body;
  final Color muted;
  final Color hairline;
  final Color hairlineStrong;
  final Color primaryAction;
  final Color onPrimaryAction;
  final Color terminalBackground;
  final Color terminalForeground;
  final Color success;
  final Color warning;

  static const light = EasyNodeTokens(
    canvas: Color(0xffffffff),
    canvasSoft: Color(0xfffafafa),
    card: Color(0xffffffff),
    ink: Color(0xff171717),
    body: Color(0xff60646c),
    muted: Color(0xff999999),
    hairline: Color(0xfff0f0f3),
    hairlineStrong: Color(0xffdcdee0),
    primaryAction: Color(0xff000000),
    onPrimaryAction: Color(0xffffffff),
    terminalBackground: Color(0xff171717),
    terminalForeground: Color(0xfff5f5f7),
    success: Color(0xff16a34a),
    warning: Color(0xffab6400),
  );

  static const dark = EasyNodeTokens(
    canvas: Color(0xff0f0f0f),
    canvasSoft: Color(0xff171717),
    card: Color(0xff171717),
    ink: Color(0xffffffff),
    body: Color(0xffb0b4ba),
    muted: Color(0xff8a8f98),
    hairline: Color(0xff2a2a2a),
    hairlineStrong: Color(0xff3a3a3a),
    primaryAction: Color(0xffffffff),
    onPrimaryAction: Color(0xff000000),
    terminalBackground: Color(0xff0b0b0b),
    terminalForeground: Color(0xfff5f5f7),
    success: Color(0xff22c55e),
    warning: Color(0xfff59e0b),
  );

  @override
  EasyNodeTokens copyWith({
    Color? canvas,
    Color? canvasSoft,
    Color? card,
    Color? ink,
    Color? body,
    Color? muted,
    Color? hairline,
    Color? hairlineStrong,
    Color? primaryAction,
    Color? onPrimaryAction,
    Color? terminalBackground,
    Color? terminalForeground,
    Color? success,
    Color? warning,
  }) {
    return EasyNodeTokens(
      canvas: canvas ?? this.canvas,
      canvasSoft: canvasSoft ?? this.canvasSoft,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      body: body ?? this.body,
      muted: muted ?? this.muted,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      primaryAction: primaryAction ?? this.primaryAction,
      onPrimaryAction: onPrimaryAction ?? this.onPrimaryAction,
      terminalBackground: terminalBackground ?? this.terminalBackground,
      terminalForeground: terminalForeground ?? this.terminalForeground,
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  EasyNodeTokens lerp(ThemeExtension<EasyNodeTokens>? other, double t) {
    if (other is! EasyNodeTokens) return this;
    return EasyNodeTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasSoft: Color.lerp(canvasSoft, other.canvasSoft, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      body: Color.lerp(body, other.body, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t)!,
      onPrimaryAction: Color.lerp(onPrimaryAction, other.onPrimaryAction, t)!,
      terminalBackground: Color.lerp(terminalBackground, other.terminalBackground, t)!,
      terminalForeground: Color.lerp(terminalForeground, other.terminalForeground, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension EasyNodeTokensContext on BuildContext {
  EasyNodeTokens get tokens => Theme.of(this).extension<EasyNodeTokens>()!;
}
```

- [ ] **Step 4: Implement theme**

Create `mobile/lib/core/ui/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_tokens.dart';

class EasyNodeTheme {
  const EasyNodeTheme._();

  static ThemeData light() => _build(Brightness.light, EasyNodeTokens.light);
  static ThemeData dark() => _build(Brightness.dark, EasyNodeTokens.dark);

  static ThemeData _build(Brightness brightness, EasyNodeTokens tokens) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.primaryAction,
      brightness: brightness,
      primary: tokens.primaryAction,
      onPrimary: tokens.onPrimaryAction,
      surface: tokens.canvas,
      onSurface: tokens.ink,
      error: const Color(0xffeb8e90),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      extensions: [tokens],
      dividerColor: tokens.hairlineStrong,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.ink,
        titleTextStyle: TextStyle(
          color: tokens.ink,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: tokens.hairlineStrong),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primaryAction,
          foregroundColor: tokens.onPrimaryAction,
          minimumSize: const Size.fromHeight(40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tokens.hairlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tokens.ink, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 58,
        backgroundColor: tokens.canvas,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? tokens.ink : tokens.muted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? tokens.ink : tokens.muted);
        }),
      ),
    );
  }
}
```

- [ ] **Step 5: Implement shared UI components**

Create:

`mobile/lib/core/ui/notice_box.dart`
```dart
import 'package:flutter/material.dart';

class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final background = color.withValues(alpha: 0.10);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body),
                if (action != null) Align(alignment: Alignment.centerRight, child: action),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

`mobile/lib/core/ui/empty_state.dart`
```dart
import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: colors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
```

`mobile/lib/core/ui/language_switcher.dart`
```dart
import 'package:flutter/material.dart';

import '../i18n/app_locale.dart';
import '../i18n/app_localizations.dart';

class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AppLocale value;
  final ValueChanged<AppLocale> onChanged;

  Future<void> _showPicker(BuildContext context) async {
    final strings = context.strings;
    final selected = await showModalBottomSheet<AppLocale>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(strings.languageEnglish),
              trailing: value == AppLocale.english ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(AppLocale.english),
            ),
            ListTile(
              title: Text(strings.languageSimplifiedChinese),
              trailing: value == AppLocale.simplifiedChinese ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(AppLocale.simplifiedChinese),
            ),
          ],
        ),
      ),
    );
    if (selected != null && selected != value) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('language-switcher'),
      onPressed: () => _showPicker(context),
      icon: const Icon(Icons.language, size: 18),
      label: Text(value == AppLocale.english ? 'EN' : '中文'),
    );
  }
}
```

- [ ] **Step 6: Run Task 3 tests**

Run:

```bash
cd mobile
flutter test test/core/ui/app_theme_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add mobile/lib/core/ui mobile/test/core/ui/app_theme_test.dart
git commit -m "feat(mobile): add redesign theme tokens"
```

## Task 4: App Bootstrap Locale and Theme Wiring

**Files:**
- Modify: `mobile/lib/app.dart`
- Test: `mobile/test/features/auth/login_page_test.dart`

- [ ] **Step 1: Write failing app wiring expectation in login test**

Update `mobile/test/features/auth/login_page_test.dart` helper to wrap Login with `AppLocalizations`, then add:

```dart
testWidgets('renders Chinese labels when locale is Chinese', (tester) async {
  final controller = LoginController.fake();
  await tester.pumpWidget(
    wrapLocalized(
      LoginPage(
        controller: controller,
        initialServerAddress: 'https://example.com',
        initialUsername: 'root',
        initialSavePassword: false,
        currentLocale: AppLocale.simplifiedChinese,
        onLocaleChanged: (_) {},
        onLoginSuccess: (_) {},
      ),
      locale: AppLocale.simplifiedChinese,
    ),
  );

  expect(find.text('连接到你的服务器。'), findsOneWidget);
  expect(find.text('服务器地址'), findsOneWidget);
});
```

Expected imports:

```dart
import 'package:mobile/core/i18n/app_locale.dart';
import 'package:mobile/core/i18n/app_localizations.dart';
import 'package:mobile/core/i18n/app_strings.dart';
import 'package:mobile/core/ui/app_theme.dart';
```

Add helper:

```dart
Widget wrapLocalized(Widget child, {AppLocale locale = AppLocale.english}) {
  return AppLocalizations(
    locale: locale,
    strings: AppStrings.forLocale(locale),
    child: MaterialApp(theme: EasyNodeTheme.light(), home: child),
  );
}
```

- [ ] **Step 2: Run updated login test and verify it fails**

Run:

```bash
cd mobile
flutter test test/features/auth/login_page_test.dart
```

Expected: FAIL because LoginPage has no locale parameters and app wiring is absent.

- [ ] **Step 3: Modify AppRoot to own locale**

In `mobile/lib/app.dart`:

- Add imports:

```dart
import 'core/i18n/app_locale.dart';
import 'core/i18n/app_localizations.dart';
import 'core/i18n/app_strings.dart';
import 'core/ui/app_theme.dart';
```

- Add `initialLocale` to `_Bootstrap`.
- In `bootstrap()`, compute:

```dart
final initialLocale = AppLocale.resolve(
  savedCode: appStorage.localeCode,
  systemLocale: WidgetsBinding.instance.platformDispatcher.locale,
);
```

- Pass `initialLocale` into `_AppRoot`.
- In `_AppRootState`, add:

```dart
late AppLocale _locale;

@override
void initState() {
  super.initState();
  _locale = widget.initialLocale;
  _loginController = LoginController(apiClientFactory: _buildApiClient)
    ..onLoginSuccess(_onLoginSuccess);
}

Future<void> _setLocale(AppLocale locale) async {
  if (_locale == locale) return;
  setState(() => _locale = locale);
  await ref.read(appStorageProvider).setLocaleCode(locale.storageCode);
}
```

- Wrap `MaterialApp` with `AppLocalizations`:

```dart
return AppLocalizations(
  locale: _locale,
  strings: AppStrings.forLocale(_locale),
  child: MaterialApp(
    title: 'EasyNode',
    locale: _locale.flutterLocale,
    supportedLocales: AppLocale.values.map((locale) => locale.flutterLocale),
    themeMode: ThemeMode.system,
    theme: EasyNodeTheme.light(),
    darkTheme: EasyNodeTheme.dark(),
    home: home,
  ),
);
```

- Pass `currentLocale: _locale` and `onLocaleChanged: _setLocale` to Login and Main Shell.

- [ ] **Step 4: Run login test and fix compile errors only**

Run:

```bash
cd mobile
flutter test test/features/auth/login_page_test.dart
```

Expected: Still FAIL in LoginPage until Task 5 implements the page, but app-level compile errors from `_AppRoot` should be resolved.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add mobile/lib/app.dart mobile/test/features/auth/login_page_test.dart
git commit -m "feat(mobile): wire locale and theme at app root"
```

## Task 5: Login Redesign and Localization

**Files:**
- Modify: `mobile/lib/features/auth/login_page.dart`
- Test: `mobile/test/features/auth/login_page_test.dart`

- [ ] **Step 1: Update LoginPage constructor**

Add required parameters:

```dart
final AppLocale currentLocale;
final ValueChanged<AppLocale> onLocaleChanged;
```

Keep existing controller, initial values, and `onLoginSuccess`.

- [ ] **Step 2: Replace hard-coded Login copy with strings**

In `build`, add:

```dart
final strings = context.strings;
final tokens = context.tokens;
```

Replace labels:

- `EasyNode` -> `strings.appName`
- `Mobile terminal access` -> `strings.loginSubtitle`
- `Server address` -> `strings.serverAddress`
- `Username` -> `strings.username`
- `Password` -> `strings.password`
- `MFA code (optional)` -> `strings.mfaCodeOptional`
- `Session duration` -> `strings.sessionDuration`
- `Save password securely` -> `strings.savePassword`
- `Log in` -> `strings.loginButton`

- [ ] **Step 3: Redesign Login layout**

Change Scaffold to no AppBar and use:

```dart
return Scaffold(
  body: SafeArea(
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        _LoginHero(
          locale: widget.currentLocale,
          onLocaleChanged: widget.onLocaleChanged,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            children: [
              // existing fields and controls
            ],
          ),
        ),
      ],
    ),
  ),
);
```

Add `_LoginHero` that uses `LanguageSwitcher`, `strings.loginTitle`, and `strings.loginSubtitle`, with a subtle sky-blue vertical gradient.

- [ ] **Step 4: Replace HTTP warning and error boxes with NoticeBox**

Change `_HttpRiskBanner` to use localized strings:

```dart
NoticeBox(
  icon: Icons.warning_amber,
  title: context.strings.httpWarningTitle,
  body: context.strings.httpWarningBody,
  color: context.tokens.warning,
  action: TextButton(onPressed: onConfirm, child: Text(context.strings.continueButton)),
)
```

Change `_ErrorBox` to:

```dart
NoticeBox(
  key: const Key('login-error'),
  icon: Icons.error_outline,
  title: message,
  body: '',
  color: Theme.of(context).colorScheme.error,
)
```

If an empty `body` creates extra spacing, make `NoticeBox` hide the body `Text` when the body is empty.

- [ ] **Step 5: Run Login tests**

Run:

```bash
cd mobile
flutter test test/features/auth/login_page_test.dart
```

Expected: PASS after updating tests to expect localized labels and preserving existing keys.

- [ ] **Step 6: Commit Task 5**

Run:

```bash
git add mobile/lib/features/auth/login_page.dart mobile/test/features/auth/login_page_test.dart mobile/lib/core/ui/notice_box.dart
git commit -m "feat(mobile): redesign localized login page"
```

## Task 6: Shell, Settings, and Empty Screens

**Files:**
- Modify: `mobile/lib/features/shell/main_shell_page.dart`
- Modify: `mobile/lib/features/shell/settings_tab.dart`
- Modify: `mobile/lib/features/shell/sftp_tab.dart`
- Modify: `mobile/lib/features/shell/scripts_tab.dart`
- Test: `mobile/test/features/shell/settings_tab_test.dart`
- Test: `mobile/test/features/shell/placeholder_tabs_test.dart`

- [ ] **Step 1: Update MainShellPage API**

Add:

```dart
const MainShellPage({
  super.key,
  required this.currentLocale,
  required this.onLocaleChanged,
});

final AppLocale currentLocale;
final ValueChanged<AppLocale> onLocaleChanged;
```

Build `_tabs` as an instance getter so Settings can receive the callback:

```dart
List<Widget> get _tabs => [
  const ServersTab(),
  const SftpTab(),
  const ScriptsTab(),
  SettingsTab(currentLocale: widget.currentLocale, onLocaleChanged: widget.onLocaleChanged),
];
```

Use `context.strings` for navigation labels.

- [ ] **Step 2: Write failing Settings language test**

Create `mobile/test/features/shell/settings_tab_test.dart` with a ProviderScope and AppLocalizations wrapper. Assert it renders `Language`, current account, and `Log out`; tap the language row and expect `English` and `Chinese` options.

- [ ] **Step 3: Redesign Settings**

In `settings_tab.dart`:

- Add required locale parameters.
- Replace hard-coded copy with `context.strings`.
- Render account/server in a `Card`.
- Add a `ListTile` with `Icons.language`, `strings.language`, and current locale label.
- Reuse the same picker behavior from `LanguageSwitcher`, or embed `LanguageSwitcher` as trailing.

- [ ] **Step 4: Write failing empty-screen tests**

Create `mobile/test/features/shell/placeholder_tabs_test.dart`:

```dart
testWidgets('SFTP tab renders localized empty state', (tester) async {
  await tester.pumpWidget(wrapLocalized(const SftpTab()));
  expect(find.text('SFTP is not available yet'), findsOneWidget);
});

testWidgets('Scripts tab renders localized empty state', (tester) async {
  await tester.pumpWidget(wrapLocalized(const ScriptsTab()));
  expect(find.text('Scripts are not available yet'), findsOneWidget);
});
```

- [ ] **Step 5: Replace SFTP and Scripts garbled text**

Use `EmptyState`:

```dart
EmptyState(
  icon: Icons.folder_outlined,
  title: context.strings.sftpEmptyTitle,
  body: context.strings.sftpEmptyBody,
)
```

and:

```dart
EmptyState(
  icon: Icons.library_books_outlined,
  title: context.strings.scriptsEmptyTitle,
  body: context.strings.scriptsEmptyBody,
)
```

- [ ] **Step 6: Run Task 6 tests**

Run:

```bash
cd mobile
flutter test test/features/shell/settings_tab_test.dart test/features/shell/placeholder_tabs_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 6**

Run:

```bash
git add mobile/lib/features/shell mobile/test/features/shell
git commit -m "feat(mobile): localize shell settings and empty states"
```

## Task 7: Servers Tab Redesign

**Files:**
- Modify: `mobile/lib/features/servers/servers_tab.dart`
- Test: `mobile/test/features/servers/servers_tab_test.dart`

- [ ] **Step 1: Update Servers tests to use localization wrapper**

Modify `_wrap` in `servers_tab_test.dart` to include `AppLocalizations` and `EasyNodeTheme.light()`. Keep all existing repository overrides.

- [ ] **Step 2: Add failing localized search/action assertions**

Add expectations:

```dart
expect(find.text('Servers'), findsOneWidget);
expect(find.text('Connect'), findsOneWidget);
expect(find.text('Not configured'), findsOneWidget);
```

Add a Chinese wrapper variant and assert:

```dart
expect(find.text('服务器'), findsOneWidget);
expect(find.text('连接'), findsOneWidget);
```

- [ ] **Step 3: Localize Servers copy**

Replace hard-coded:

- `Servers` -> `strings.serversTitle`
- `Search by name, host, user, tag, or group` -> `strings.searchHosts`
- `Connect` -> `strings.connect`
- `Not configured` -> `strings.notConfigured`
- `Retry` -> `strings.retry`
- active terminal text -> `strings.activeTerminal` or `strings.activeTerminals.replaceFirst('{count}', '$count')`
- close-all tooltip -> `strings.closeAllTerminals`

- [ ] **Step 4: Redesign cards and banner**

Keep `_ServerCard` private, but change layout from `ListTile` to a custom `Card` with:

```dart
Card(
  child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Expanded(child: Text(server.displayName)), action]),
        Text(server.connectionLabel, style: const TextStyle(fontFamily: 'monospace')),
        Wrap(children: chips),
      ],
    ),
  ),
)
```

Use token border/card defaults from theme. Keep keys like `Key('server-${server.id}')`.

- [ ] **Step 5: Run Servers tests**

Run:

```bash
cd mobile
flutter test test/features/servers/servers_tab_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit Task 7**

Run:

```bash
git add mobile/lib/features/servers/servers_tab.dart mobile/test/features/servers/servers_tab_test.dart
git commit -m "feat(mobile): redesign localized server list"
```

## Task 8: Terminal Shell and Toolbar Styling

**Files:**
- Modify: `mobile/lib/features/terminal/terminal_shell_page.dart`
- Modify: `mobile/lib/features/terminal/terminal_toolbar.dart`
- Test: `mobile/test/features/terminal/terminal_toolbar_test.dart`

- [ ] **Step 1: Update terminal toolbar test wrapper**

Wrap `TerminalToolbar` with `AppLocalizations` and `EasyNodeTheme.light()` so theme tokens are present.

- [ ] **Step 2: Run toolbar test before edits**

Run:

```bash
cd mobile
flutter test test/features/terminal/terminal_toolbar_test.dart
```

Expected: PASS before visual edits.

- [ ] **Step 3: Make terminal toolbar token-driven**

In `terminal_toolbar.dart`:

- Import `app_tokens.dart`.
- Use `context.tokens.canvasSoft`, `context.tokens.hairlineStrong`, `context.tokens.card`, and `context.tokens.ink`.
- Keep button keys unchanged (`toolbar-Esc`, etc.).
- Keep emitted escape sequences unchanged.

- [ ] **Step 4: Make terminal top bar token-driven**

In `terminal_shell_page.dart`:

- Import `app_tokens.dart`.
- Replace direct surface/divider colors in `_TerminalTopBar` with `context.tokens.canvas` and `context.tokens.hairlineStrong`.
- Replace terminal background `Colors.black` with `context.tokens.terminalBackground`.
- Keep `TerminalView` and `IndexedStack` behavior unchanged.
- Keep `_statusText` values in English for now unless AppStrings is already available in this subtree; do not change session behavior.

- [ ] **Step 5: Run terminal test**

Run:

```bash
cd mobile
flutter test test/features/terminal/terminal_toolbar_test.dart
```

Expected: PASS with the same input sequence list.

- [ ] **Step 6: Commit Task 8**

Run:

```bash
git add mobile/lib/features/terminal/terminal_shell_page.dart mobile/lib/features/terminal/terminal_toolbar.dart mobile/test/features/terminal/terminal_toolbar_test.dart
git commit -m "feat(mobile): align terminal chrome with redesign tokens"
```

## Task 9: Full Verification and Polish

**Files:**
- Inspect: `mobile/lib`
- Inspect: `mobile/test`

- [ ] **Step 1: Scan for garbled text and old seed color usage**

Run:

```bash
rg -n "鍗|绾|Colors\\.indigo|colorSchemeSeed|Mobile terminal access|即将|脚本库" mobile/lib mobile/test
```

Expected: No garbled text, no `Colors.indigo` or `colorSchemeSeed` in active mobile app code, no old Login subtitle.

- [ ] **Step 2: Run all mobile tests**

Run:

```bash
cd mobile
flutter test
```

Expected: PASS.

- [ ] **Step 3: Run Flutter analyzer**

Run:

```bash
cd mobile
flutter analyze
```

Expected: No errors. Existing warnings must be reviewed; new warnings from this work must be fixed.

- [ ] **Step 4: Manual smoke check**

Run an emulator/device build if available:

```bash
cd mobile
flutter run
```

Expected:

- Login starts in system language when no preference exists.
- Login language switch changes labels immediately.
- Login still validates and submits through existing controller.
- Servers tab still loads host cards.
- Terminal connect path still opens TerminalShellPage.
- Settings language switch changes labels immediately.
- SFTP/Scripts show readable localized empty states.

- [ ] **Step 5: Commit final polish if needed**

If Step 1-4 required fixes:

```bash
git add mobile/lib mobile/test
git commit -m "fix(mobile): polish redesign verification issues"
```

If no fixes were needed, do not create an empty commit.

## Self-Review

- Spec coverage: Tasks cover theme/token architecture, all existing mobile screens, English/Chinese i18n, Login and Settings language switching, locale persistence, system-locale defaulting, dark-mode compatibility, tests, and verification.
- Placeholder scan: No deferred or empty steps remain. "Placeholder tabs" refers to existing SFTP/Scripts empty screens and includes concrete implementation steps.
- Type consistency: `AppLocale`, `AppStrings`, `AppLocalizations`, `EasyNodeTokens`, `EasyNodeTheme`, `LanguageSwitcher`, `NoticeBox`, and `EmptyState` names are introduced before use and remain consistent across tasks.
