import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../core/storage/app_storage.dart';
import '../features/terminal/terminal_theme_presets.dart';
import 'storage_providers.dart';

class TerminalSettings {
  const TerminalSettings({
    this.fontSize = 12.0,
    this.fontFamily = 'monospace',
    this.themePreset = 'warm',
    this.autoServerStatus = true,
  });

  final double fontSize;
  final String fontFamily;
  final String themePreset;
  final bool autoServerStatus;

  TerminalTheme get terminalTheme => terminalThemeForPreset(themePreset);

  TerminalStyle get terminalStyle =>
      TerminalStyle(fontSize: fontSize, fontFamily: fontFamily);

  TerminalSettings copyWith({
    double? fontSize,
    String? fontFamily,
    String? themePreset,
    bool? autoServerStatus,
  }) {
    return TerminalSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      themePreset: themePreset ?? this.themePreset,
      autoServerStatus: autoServerStatus ?? this.autoServerStatus,
    );
  }
}

class TerminalSettingsNotifier extends StateNotifier<TerminalSettings> {
  TerminalSettingsNotifier(this._storage)
    : super(
        TerminalSettings(
          fontSize: _storage.terminalFontSize,
          fontFamily: _storage.terminalFontFamily,
          themePreset: _storage.terminalThemePreset,
          autoServerStatus: _storage.terminalAutoServerStatus,
        ),
      );

  final AppStorage _storage;

  Future<void> setFontSize(double v) async {
    final clamped = v.clamp(10.0, 24.0);
    await _storage.setTerminalFontSize(clamped);
    state = state.copyWith(fontSize: clamped);
  }

  Future<void> setFontFamily(String v) async {
    await _storage.setTerminalFontFamily(v);
    state = state.copyWith(fontFamily: v);
  }

  Future<void> setThemePreset(String v) async {
    await _storage.setTerminalThemePreset(v);
    state = state.copyWith(themePreset: v);
  }

  Future<void> setAutoServerStatus(bool v) async {
    await _storage.setTerminalAutoServerStatus(v);
    state = state.copyWith(autoServerStatus: v);
  }
}

final terminalSettingsProvider =
    StateNotifierProvider<TerminalSettingsNotifier, TerminalSettings>((ref) {
      return TerminalSettingsNotifier(ref.watch(appStorageProvider));
    });
