import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_storage.dart';
import '../core/ui/app_color_theme.dart';
import 'storage_providers.dart';

enum AppThemePalette {
  light,
  amber;

  AppColorTheme colorsFor(Brightness brightness) {
    return switch ((this, brightness)) {
      (AppThemePalette.light, Brightness.light) => AppColorTheme.defaultLight,
      (AppThemePalette.light, Brightness.dark) => AppColorTheme.defaultDark,
      (AppThemePalette.amber, Brightness.light) => AppColorTheme.amberLight,
      (AppThemePalette.amber, Brightness.dark) => AppColorTheme.amberDark,
    };
  }

  Color get seed => switch (this) {
    AppThemePalette.light => const Color(0xFF2B6FCB),
    AppThemePalette.amber => Colors.amber,
  };
}

class ColorThemeNotifier extends StateNotifier<AppThemePalette> {
  ColorThemeNotifier(this._storage) : super(_fromString(_storage.colorTheme));

  final AppStorage _storage;

  static AppThemePalette _fromString(String value) {
    return switch (value) {
      'amber' => AppThemePalette.amber,
      _ => AppThemePalette.light,
    };
  }

  Future<void> setPalette(AppThemePalette palette) async {
    if (state == palette) return;
    await _storage.setColorTheme(palette.name);
    state = palette;
  }
}

final colorThemeProvider =
    StateNotifierProvider<ColorThemeNotifier, AppThemePalette>((ref) {
      return ColorThemeNotifier(ref.watch(appStorageProvider));
    });
