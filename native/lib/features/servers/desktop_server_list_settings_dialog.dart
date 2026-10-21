import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../state/desktop_server_list_config_provider.dart';
import 'server_list_config.dart';

class DesktopServerListSettingsDialog extends ConsumerStatefulWidget {
  const DesktopServerListSettingsDialog({super.key});

  @override
  ConsumerState<DesktopServerListSettingsDialog> createState() =>
      _DesktopServerListSettingsDialogState();
}

class _DesktopServerListSettingsDialogState
    extends ConsumerState<DesktopServerListSettingsDialog> {
  ServerListConfig? _draft;
  bool _displayTab = false;
  bool _saving = false;
  String? _error;

  AppLocalizations get l => AppLocalizations.of(context);
  String _tr(String key) => l.tr('desktop.servers.listSettings.$key');

  Future<void> _save() async {
    if (_saving || _draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(desktopServerListConfigProvider.notifier).save(_draft!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _tr('saveFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(desktopServerListConfigProvider);
    _draft ??= config.valueOrNull;
    return DesktopManagementDialog(
      title: l.tr('desktop.servers.settings'),
      width: 600,
      busy: _saving,
      body: _draft == null
          ? config.when(
              data: (_) => const SizedBox.shrink(),
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Column(
                children: [
                  Text(
                    _tr('loadFailed'),
                    style: TextStyle(color: context.colors.danger),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(desktopServerListConfigProvider),
                    child: Text(l.tr('common.retry')),
                  ),
                ],
              ),
            )
          : AbsorbPointer(
              absorbing: _saving,
              child: FocusScope(
                canRequestFocus: !_saving,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tabs(),
                    const SizedBox(height: 20),
                    Text(
                      _tr(_displayTab ? 'layoutTitle' : 'columnsTitle'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tr(_displayTab ? 'layoutHint' : 'columnsHint'),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_displayTab) ...[
                      _displayCard('group', Icons.folder_open_outlined),
                      const SizedBox(height: 12),
                      _displayCard('list', Icons.view_list_outlined),
                    ] else
                      _columns(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: context.colors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.tr('common.cancel')),
        ),
        FilledButton(
          key: const Key('desktop-server-list-settings-save'),
          onPressed: _saving || _draft == null ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_tr('save')),
        ),
      ],
    );
  }

  Widget _tabs() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: context.colors.chip,
      border: Border.all(color: context.colors.border),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        for (final display in [false, true])
          Expanded(
            child: TextButton(
              key: ValueKey(
                'desktop-server-list-settings-tab-${display ? 'display' : 'columns'}',
              ),
              onPressed: () => setState(() => _displayTab = display),
              style: _cardStyle(_displayTab == display, radius: 7).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                alignment: Alignment.center,
              ),
              child: Text(_tr(display ? 'displayTab' : 'columnsTab')),
            ),
          ),
      ],
    ),
  );

  ButtonStyle _cardStyle(bool selected, {double radius = 8}) => ButtonStyle(
    alignment: Alignment.centerLeft,
    minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: WidgetStatePropertyAll(
      selected ? context.colors.accent : context.colors.text,
    ),
    backgroundColor: WidgetStatePropertyAll(
      selected ? context.colors.accentSoft : context.colors.canvas,
    ),
    overlayColor: WidgetStatePropertyAll(
      context.colors.accent.withValues(alpha: .05),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color:
            selected ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)
            ? context.colors.accent
            : context.colors.border,
      ),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    splashFactory: NoSplash.splashFactory,
  );

  Widget _columns() => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final column in ServerListConfig.defaultColumns.keys)
          SizedBox(
            width: (constraints.maxWidth - 10) / 2,
            child: Semantics(
              checked: _draft!.shows(column),
              child: TextButton(
                key: ValueKey('desktop-server-list-settings-column-$column'),
                onPressed: () => setState(
                  () => _draft = _draft!.withColumn(
                    column,
                    !_draft!.shows(column),
                  ),
                ),
                style: _cardStyle(_draft!.shows(column)),
                child: Row(
                  children: [
                    Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        color: _draft!.shows(column)
                            ? context.colors.accent
                            : context.colors.card,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: _draft!.shows(column)
                              ? context.colors.accent
                              : context.colors.strongBorder,
                        ),
                      ),
                      child: _draft!.shows(column)
                          ? Icon(
                              Icons.check,
                              size: 13,
                              color: context.colors.fontOnPrimary,
                            )
                          : null,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        column == 'selection'
                            ? _tr('selection')
                            : l.tr(
                                'servers.field.${column == 'tag' ? 'tags' : column}',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _displayCard(String mode, IconData icon) {
    final selected = _draft!.displayMode == mode;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: TextButton(
        key: ValueKey('desktop-server-list-settings-mode-$mode'),
        onPressed: () => setState(() => _draft = _draft!.withDisplayMode(mode)),
        style: _cardStyle(selected, radius: 10).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(0, 82)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.card,
                border: Border.all(color: context.colors.border),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                size: 19,
                color: selected ? context.colors.accent : context.colors.muted,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('${mode}Title'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? context.colors.accent
                          : context.colors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tr('${mode}Hint'),
                    style: TextStyle(fontSize: 13, color: context.colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 22,
              child: selected
                  ? Icon(
                      Icons.check_circle,
                      size: 22,
                      color: context.colors.accent,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
