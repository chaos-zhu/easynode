import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/terminal_settings_notifier.dart';
import 'terminal_theme_presets.dart';

class TerminalSettingsPage extends ConsumerWidget {
  const TerminalSettingsPage({super.key});

  static const _fonts = ['monospace', 'Courier', 'Menlo', 'SF Mono', 'Consolas'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(terminalSettingsProvider.notifier);
    final l = AppLocalizations.of(context);
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: Text(l.tr('terminal.settings')),
        backgroundColor: c.canvas,
        foregroundColor: c.text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionTitle(l.tr('terminal.settings.themePreset')),
          _ThemePresetGrid(
            selectedId: settings.themePreset,
            onSelected: notifier.setThemePreset,
          ),
          const SizedBox(height: 24),
          _SectionTitle(l.tr('terminal.settings.fontSize')),
          _FontSizeSlider(
            value: settings.fontSize,
            onChanged: notifier.setFontSize,
          ),
          const SizedBox(height: 24),
          _SectionTitle(l.tr('terminal.settings.fontFamily')),
          _FontFamilyPicker(
            selected: settings.fontFamily,
            onSelected: notifier.setFontFamily,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: context.colors.primary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThemePresetGrid extends StatelessWidget {
  const _ThemePresetGrid({
    required this.selectedId,
    required this.onSelected,
  });

  final String selectedId;
  final Future<void> Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.85,
      children: [
        for (final preset in terminalThemePresets)
          _ThemePresetCard(
            label: l.tr('terminal.settings.preset.${preset.id}'),
            theme: preset.theme,
            selected: preset.id == selectedId,
            onTap: () => onSelected(preset.id),
          ),
      ],
    );
  }
}

class _ThemePresetCard extends StatelessWidget {
  const _ThemePresetCard({
    required this.label,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final TerminalTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? c.accent : c.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(9),
                  ),
                ),
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _colorRow([
                      theme.foreground,
                      theme.red,
                      theme.green,
                      theme.yellow,
                    ]),
                    const SizedBox(height: 3),
                    _colorRow([
                      theme.blue,
                      theme.magenta,
                      theme.cyan,
                      theme.cursor,
                    ]),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? c.accent.withValues(alpha: 0.12)
                    : c.card,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(9),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? c.accent : c.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _colorRow(List<Color> colors) {
    return Row(
      children: [
        for (final c in colors) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _FontSizeSlider extends StatelessWidget {
  const _FontSizeSlider({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final Future<void> Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Text(
            '${value.round()}',
            style: TextStyle(
              color: c.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: c.accent,
                inactiveTrackColor: c.border,
                thumbColor: c.accent,
                overlayColor: c.accent.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: value,
                min: 10,
                max: 24,
                divisions: 14,
                onChanged: (v) => onChanged(v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontFamilyPicker extends StatelessWidget {
  const _FontFamilyPicker({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final Future<void> Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final font in TerminalSettingsPage._fonts)
          GestureDetector(
            onTap: () => onSelected(font),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: font == selected ? c.primary : c.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: font == selected
                      ? c.primary
                      : c.border,
                ),
              ),
              child: Text(
                font,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: font == selected
                      ? c.fontOnPrimary
                      : c.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
