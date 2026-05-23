import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_storage.dart';
import '../../../state/storage_providers.dart';

enum EditorThemeMode { dark, light }

class EditorPreferences {
  const EditorPreferences({
    required this.fontSize,
    required this.wordWrap,
    required this.theme,
  });

  final int fontSize;
  final bool wordWrap;
  final EditorThemeMode theme;

  EditorPreferences copyWith({
    int? fontSize,
    bool? wordWrap,
    EditorThemeMode? theme,
  }) {
    return EditorPreferences(
      fontSize: fontSize ?? this.fontSize,
      wordWrap: wordWrap ?? this.wordWrap,
      theme: theme ?? this.theme,
    );
  }
}

class EditorPreferencesNotifier extends StateNotifier<EditorPreferences> {
  EditorPreferencesNotifier(this._storage) : super(_loadInitial(_storage));

  final AppStorage _storage;

  static EditorPreferences _loadInitial(AppStorage storage) {
    return EditorPreferences(
      fontSize: storage.editorFontSize,
      wordWrap: storage.editorWordWrap,
      theme: storage.editorTheme == 'light'
          ? EditorThemeMode.light
          : EditorThemeMode.dark,
    );
  }

  Future<void> setFontSize(int value) async {
    final clamped =
        value.clamp(AppStorage.editorFontSizeMin, AppStorage.editorFontSizeMax);
    if (clamped == state.fontSize) return;
    await _storage.setEditorFontSize(clamped);
    state = state.copyWith(fontSize: clamped);
  }

  Future<void> setWordWrap(bool value) async {
    if (value == state.wordWrap) return;
    await _storage.setEditorWordWrap(value);
    state = state.copyWith(wordWrap: value);
  }

  Future<void> setTheme(EditorThemeMode value) async {
    if (value == state.theme) return;
    await _storage.setEditorTheme(value == EditorThemeMode.light ? 'light' : 'dark');
    state = state.copyWith(theme: value);
  }
}

final editorPreferencesProvider =
    StateNotifierProvider<EditorPreferencesNotifier, EditorPreferences>((ref) {
  return EditorPreferencesNotifier(ref.watch(appStorageProvider));
});
