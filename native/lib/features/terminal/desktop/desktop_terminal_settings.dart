import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../core/api/api_client.dart';
import '../../../state/api_providers.dart';
import '../../../state/storage_providers.dart';

Map<String, dynamic> terminalMap(Object? value) =>
    value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : {};
Map<String, dynamic> cloneTerminalJson(Map<String, dynamic> value) =>
    terminalMap(jsonDecode(jsonEncode(value)));

/// The same v3 document used by Web. Unknown, platform-specific background
/// fields are preserved when editing other sections.
class DesktopTerminalSettings {
  DesktopTerminalSettings(this.json);
  final Map<String, dynamic> json;
  Map<String, dynamic> get appearance =>
      json['appearance'] as Map<String, dynamic>;
  Map<String, dynamic> get font => appearance['font'] as Map<String, dynamic>;
  Map<String, dynamic> get background =>
      appearance['background'] as Map<String, dynamic>;
  Map<String, dynamic> get overrides =>
      appearance['overrides'] as Map<String, dynamic>;
  Map<String, dynamic> get highlighting =>
      json['highlighting'] as Map<String, dynamic>;
  Map<String, dynamic> get behavior => json['behavior'] as Map<String, dynamic>;
  bool get autoReconnect => behavior['autoReconnect'] == true;
  bool get autoExecute => behavior['autoExecuteScript'] == true;
  bool get statusBar => behavior['statusBarEnabled'] != false;
  double get fontSize => (font['size'] as num).toDouble();
  String get fontFamily => font['family'] as String;
  String get themeId => appearance['activeThemeId'] as String;
  DesktopTerminalSettings copy() =>
      DesktopTerminalSettings(cloneTerminalJson(json));

  factory DesktopTerminalSettings.defaults() => DesktopTerminalSettings({
    'version': 3,
    'appearance': {
      'activeThemeId': 'builtin:Cobalt_Neon',
      'customThemes': <dynamic>[],
      'customHtmlThemes': <dynamic>[],
      'font': {'family': 'monospace', 'size': 16},
      'overrides': <String, dynamic>{
        'foreground': null,
        'cursor': null,
        'selectionBackground': null,
      },
      'background': {
        'mode': 'theme',
        'htmlThemeId': 'builtin-html:orbital-grid',
        'assetId': null,
        'fit': 'cover',
        'position': 'center',
        'overlay': {'tone': 'auto', 'opacity': .35},
      },
    },
    'highlighting': {
      'enabled': false,
      'debugMode': false,
      'presetId': 'builtin:standard',
      'presetVersion': 2,
      'builtinOverrides': <dynamic>[],
      'customRules': <dynamic>[],
    },
    'behavior': {
      'autoReconnect': true,
      'autoExecuteScript': false,
      'autoShowContextMenu': true,
      'statusBarEnabled': true,
    },
  });

  factory DesktopTerminalSettings.fromJson(Object? value) {
    final defaults = DesktopTerminalSettings.defaults().json;
    void merge(Map<String, dynamic> target, Map<String, dynamic> source) {
      for (final entry in source.entries) {
        if (!target.containsKey(entry.key)) continue;
        if (target[entry.key] is Map && entry.value is Map) {
          merge(
            target[entry.key] as Map<String, dynamic>,
            terminalMap(entry.value),
          );
        } else {
          target[entry.key] = entry.value;
        }
      }
    }

    merge(defaults, terminalMap(value));
    return DesktopTerminalSettings(defaults);
  }
}

Color terminalColor(Object? value, [Color fallback = Colors.white]) {
  final text = value?.toString().trim() ?? '';
  if (text == 'transparent') return Colors.transparent;
  if (text.startsWith('#')) {
    var hex = text.substring(1);
    if (hex.length == 3 || hex.length == 4) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) {
      hex = 'ff$hex';
    } else if (hex.length == 8) {
      hex = '${hex.substring(6)}${hex.substring(0, 6)}';
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  final rgb = RegExp(r'^rgba?\(([^)]+)\)$').firstMatch(text);
  if (rgb != null) {
    final parts = rgb[1]!.split(',').map((e) => e.trim()).toList();
    if (parts.length >= 3) {
      int channel(String value) =>
          ((double.tryParse(value.replaceAll('%', '')) ?? 0) *
                  (value.endsWith('%') ? 2.55 : 1))
              .round()
              .clamp(0, 255);
      return Color.fromRGBO(
        channel(parts[0]),
        channel(parts[1]),
        channel(parts[2]),
        parts.length == 4 ? (double.tryParse(parts[3]) ?? 1).clamp(0, 1) : 1,
      );
    }
  }
  return fallback;
}

final desktopTerminalThemesProvider = FutureProvider<Map<String, dynamic>>(
  (ref) async => terminalMap(
    jsonDecode(await rootBundle.loadString('assets/terminal/themes.json')),
  ),
);
final desktopHighlightRulesProvider =
    FutureProvider<List<Map<String, dynamic>>>(
      (ref) async =>
          (jsonDecode(
                    await rootBundle.loadString(
                      'assets/terminal/highlight_rules.json',
                    ),
                  )
                  as List)
              .map(terminalMap)
              .toList(),
    );

Map<String, dynamic> resolvedTerminalColors(
  DesktopTerminalSettings settings,
  Map<String, dynamic> themes,
) {
  Map<String, dynamic> selected = {};
  if (settings.themeId.startsWith('custom:')) {
    for (final raw in settings.appearance['customThemes'] as List) {
      final theme = terminalMap(raw);
      if (theme['id'] == settings.themeId) {
        selected = terminalMap(theme['colors']);
      }
    }
  } else {
    selected = terminalMap(
      themes[settings.themeId.replaceFirst('builtin:', '')],
    );
  }
  if (selected.isEmpty) selected = terminalMap(themes['Cobalt_Neon']);
  return {
    ...selected,
    for (final e in settings.overrides.entries)
      if (e.value != null) e.key: e.value,
  };
}

TerminalTheme desktopTerminalTheme(
  DesktopTerminalSettings settings,
  Map<String, dynamic> themes, {
  bool transparent = false,
}) {
  final colors = resolvedTerminalColors(settings, themes);
  Color c(String key, [Color fallback = Colors.white]) =>
      terminalColor(colors[key], fallback);
  return TerminalTheme(
    cursor: c('cursor'),
    selection: c('selectionBackground', const Color(0x553b82f6)),
    foreground: c('foreground'),
    background: transparent
        ? Colors.transparent
        : c('background', const Color(0xff142838)),
    black: c('black', Colors.black),
    red: c('red', Colors.red),
    green: c('green', Colors.green),
    yellow: c('yellow', Colors.yellow),
    blue: c('blue', Colors.blue),
    magenta: c('magenta', Colors.purple),
    cyan: c('cyan', Colors.cyan),
    white: c('white'),
    brightBlack: c('brightBlack', Colors.grey),
    brightRed: c('brightRed', Colors.redAccent),
    brightGreen: c('brightGreen', Colors.greenAccent),
    brightYellow: c('brightYellow', Colors.yellowAccent),
    brightBlue: c('brightBlue', Colors.blueAccent),
    brightMagenta: c('brightMagenta', Colors.purpleAccent),
    brightCyan: c('brightCyan', Colors.cyanAccent),
    brightWhite: c('brightWhite'),
    searchHitBackground: const Color(0x66999900),
    searchHitBackgroundCurrent: const Color(0xffe5b33a),
    searchHitForeground: Colors.black,
  );
}

class DesktopTerminalSettingsRepository {
  DesktopTerminalSettingsRepository(this.api);
  final ApiClient api;
  Future<DesktopTerminalSettings> load() async =>
      DesktopTerminalSettings.fromJson(
        (await api.getJson('/terminal-settings'))['data'],
      );
  Future<DesktopTerminalSettings> save(DesktopTerminalSettings value) async =>
      DesktopTerminalSettings.fromJson(
        (await api.putJson('/terminal-settings', value.json))['data'],
      );
  Future<Uint8List> image(String assetId) =>
      api.getBytes('/terminal-settings/background/$assetId');
  Future<String> upload(Uint8List bytes, String name) async =>
      terminalMap(
            (await api.uploadFile(
              '/terminal-settings/background',
              bytes,
              name,
            ))['data'],
          )['assetId']
          as String;
}

final desktopTerminalSettingsRepositoryProvider = Provider(
  (ref) => DesktopTerminalSettingsRepository(ref.watch(apiClientProvider)),
);

class DesktopTerminalSettingsNotifier
    extends AsyncNotifier<DesktopTerminalSettings> {
  @override
  Future<DesktopTerminalSettings> build() =>
      ref.watch(desktopTerminalSettingsRepositoryProvider).load();
  Future<void> save(DesktopTerminalSettings draft) async {
    final value = await ref
        .read(desktopTerminalSettingsRepositoryProvider)
        .save(draft);
    state = AsyncData(value);
  }
}

final desktopTerminalSettingsProvider =
    AsyncNotifierProvider<
      DesktopTerminalSettingsNotifier,
      DesktopTerminalSettings
    >(DesktopTerminalSettingsNotifier.new);
final desktopTerminalPreviewProvider = StateProvider<DesktopTerminalSettings?>(
  (ref) => null,
);
final effectiveDesktopTerminalSettingsProvider = Provider(
  (ref) =>
      ref.watch(desktopTerminalPreviewProvider) ??
      ref.watch(desktopTerminalSettingsProvider).valueOrNull ??
      DesktopTerminalSettings.defaults(),
);
final desktopTerminalBackgroundProvider =
    FutureProvider.family<Uint8List, String>(
      (ref, id) =>
          ref.watch(desktopTerminalSettingsRepositoryProvider).image(id),
    );

class DesktopTerminalPreferences extends StateNotifier<Map<String, dynamic>> {
  DesktopTerminalPreferences(this._write, String raw) : super(_read(raw));
  static Map<String, dynamic> _read(String raw) {
    try {
      return terminalMap(raw.isEmpty ? null : jsonDecode(raw));
    } on FormatException {
      return {};
    }
  }

  final Future<void> Function(String) _write;
  Future<void> set(String key, Object value) async {
    final next = {...state, key: value};
    await _write(jsonEncode(next));
    state = next;
  }
}

final desktopTerminalPreferencesProvider =
    StateNotifierProvider<DesktopTerminalPreferences, Map<String, dynamic>>((
      ref,
    ) {
      final storage = ref.watch(appStorageProvider);
      return DesktopTerminalPreferences(
        storage.setDesktopTerminalPreferences,
        storage.desktopTerminalPreferences,
      );
    });
