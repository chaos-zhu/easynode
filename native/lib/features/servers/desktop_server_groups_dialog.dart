import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/app_reorder_proxy.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../../state/desktop_server_group_provider.dart';
import '../order/order_layout.dart';
import 'desktop_server_order_draft.dart';
import 'server_group_model.dart';
import 'server_repository.dart';

class DesktopServerGroupsDialog extends ConsumerStatefulWidget {
  const DesktopServerGroupsDialog({super.key});

  @override
  ConsumerState<DesktopServerGroupsDialog> createState() =>
      _DesktopServerGroupsDialogState();
}

class _DesktopServerGroupsDialogState
    extends ConsumerState<DesktopServerGroupsDialog> {
  DesktopServerOrderDraft? _draft;
  bool _saving = false;
  String? _error;

  AppLocalizations get l => AppLocalizations.of(context);
  String tr(String key) => l.tr('desktop.servers.group.$key');

  Future<void> _mutate({ServerGroupModel? group, bool delete = false}) async {
    final changed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GroupMutationDialog(group: group, delete: delete),
    );
    if (changed != true || !mounted) return;
    ref.invalidate(desktopServerCatalogProvider);
  }

  Future<void> _saveOrder() async {
    if (_saving || _draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(serverRepositoryProvider).updateOrder(_draft!.revision, [
        OrderChange(scope: 'groups', orderedIds: [..._draft!.groups]),
      ]);
      if (!mounted) return;
      setState(() => _draft = null);
      ref.invalidate(desktopServerCatalogProvider);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiFailure && error.statusCode == 409) {
        setState(() {
          _draft = null;
          _error = l.tr('order.conflict');
        });
        ref.invalidate(desktopServerCatalogProvider);
      } else {
        setState(() => _error = l.tr('desktop.servers.orderSaveFailed'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(desktopServerCatalogProvider);
    return DesktopManagementDialog(
      title: tr('title'),
      width: 640,
      busy: _saving,
      body: catalog.when(
        skipLoadingOnRefresh: false,
        loading: () => const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Column(
          children: [
            Text(
              tr('loadFailed'),
              style: TextStyle(color: context.colors.danger),
            ),
            TextButton(
              onPressed: () => ref.invalidate(desktopServerCatalogProvider),
              child: Text(l.tr('common.retry')),
            ),
          ],
        ),
        data: _body,
      ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.tr('common.close')),
        ),
      ],
    );
  }

  Widget _body(HostCatalog catalog) {
    final actionWidth = MediaQuery.textScalerOf(context).scale(104);
    final byId = {for (final group in catalog.groups) group.id: group};
    final groups =
        (_draft?.groups ?? catalog.order.sections.map((s) => s.groupId))
            .map((id) => byId[id])
            .whereType<ServerGroupModel>()
            .toList();
    final ordering = _draft != null;
    return AbsorbPointer(
      absorbing: _saving,
      child: FocusScope(
        canRequestFocus: !_saving,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Text(
                  ordering
                      ? tr('orderHint')
                      : l.trf('desktop.servers.group.total', [groups.length]),
                  style: TextStyle(fontSize: 13, color: context.colors.muted),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('desktop-group-order-cancel'),
                      onPressed: ordering
                          ? () => setState(() {
                              _draft = null;
                              _error = null;
                            })
                          : groups.length < 2
                          ? null
                          : () => setState(() {
                              _draft = DesktopServerOrderDraft(catalog.order);
                              _error = null;
                            }),
                      child: Text(
                        l.tr(
                          ordering ? 'common.cancel' : 'desktop.servers.order',
                        ),
                      ),
                    ),
                    FilledButton(
                      key: Key(
                        ordering
                            ? 'desktop-group-order-save'
                            : 'desktop-group-add',
                      ),
                      onPressed: _saving
                          ? null
                          : ordering
                          ? _saveOrder
                          : () => _mutate(),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              ordering
                                  ? l.tr('desktop.servers.orderSave')
                                  : tr('add'),
                            ),
                    ),
                  ],
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.colors.danger),
                ),
              ),
            const SizedBox(height: 14),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Container(
                    color: context.colors.chip,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        if (ordering) const SizedBox(width: 30),
                        Expanded(child: Text(tr('name'))),
                        SizedBox(
                          width: 90,
                          child: Text(tr('count'), textAlign: TextAlign.center),
                        ),
                        if (!ordering)
                          SizedBox(
                            width: actionWidth,
                            child: Text(
                              l.tr('desktop.servers.actions'),
                              textAlign: TextAlign.right,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: math.min(
                      groups.length *
                          math.max(
                            56,
                            MediaQuery.textScalerOf(context).scale(38),
                          ),
                      MediaQuery.sizeOf(context).height * .42,
                    ),
                    child: ReorderableListView.builder(
                      key: const Key('desktop-group-list'),
                      buildDefaultDragHandles: false,
                      proxyDecorator: buildAppReorderProxy,
                      itemCount: groups.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (_draft == null || _saving) return;
                        setState(
                          () => DesktopServerOrderDraft.move(
                            _draft!.groups,
                            oldIndex,
                            newIndex,
                          ),
                        );
                      },
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        final hosts = catalog.hosts
                            .where((h) => h.group == group.id)
                            .toList();
                        final row = Material(
                          color: context.colors.card,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                if (ordering)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      size: 18,
                                      color: context.colors.muted,
                                    ),
                                  ),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          group.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (group.isDefault)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: context.colors.accent
                                                  .withValues(alpha: .3),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            tr('default'),
                                            style: TextStyle(
                                              color: context.colors.accent,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: Center(
                                    child: Tooltip(
                                      message: ordering
                                          ? ''
                                          : hosts
                                                .map(
                                                  (h) =>
                                                      '${h.displayName}  ${h.host}',
                                                )
                                                .join('\n'),
                                      waitDuration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      textStyle: TextStyle(
                                        color: context.colors.text,
                                        fontSize: 12,
                                        height: 1.7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.colors.card,
                                        border: Border.all(
                                          color: context.colors.border,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: hosts.isEmpty
                                              ? context.colors.chip
                                              : context.colors.accentSoft,
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: Text(
                                          '${hosts.length}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: hosts.isEmpty
                                                ? context.colors.muted
                                                : context.colors.accent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!ordering)
                                  SizedBox(
                                    width: actionWidth,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        _action(
                                          'edit',
                                          group,
                                          () => _mutate(group: group),
                                        ),
                                        if (!group.isDefault)
                                          _action(
                                            'delete',
                                            group,
                                            () => _mutate(
                                              group: group,
                                              delete: true,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                        return ReorderableDragStartListener(
                          key: ValueKey('desktop-group-row-${group.id}'),
                          index: index,
                          enabled: ordering && !_saving,
                          child: MouseRegion(
                            cursor: ordering
                                ? SystemMouseCursors.grab
                                : MouseCursor.defer,
                            child: row,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    String action,
    ServerGroupModel group,
    VoidCallback onPressed,
  ) => Flexible(
    child: TextButton(
      key: ValueKey('desktop-group-$action-${group.id}'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        foregroundColor: action == 'delete'
            ? context.colors.danger
            : context.colors.accent,
      ),
      child: Text(
        l.tr('common.$action'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    ),
  );
}

class _GroupMutationDialog extends ConsumerStatefulWidget {
  const _GroupMutationDialog({this.group, this.delete = false});
  final ServerGroupModel? group;
  final bool delete;

  @override
  ConsumerState<_GroupMutationDialog> createState() =>
      _GroupMutationDialogState();
}

class _GroupMutationDialogState extends ConsumerState<_GroupMutationDialog> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || (!widget.delete && !_formKey.currentState!.validate())) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(desktopServerGroupRepositoryProvider);
      if (widget.delete) {
        await repo.delete(widget.group!.id);
      } else if (widget.group != null) {
        await repo.rename(widget.group!.id, _name.text.trim());
      } else {
        await repo.create(_name.text.trim());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiFailure
            ? error.message
            : AppLocalizations.of(
                context,
              ).tr('desktop.servers.form.operationFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final action = widget.delete
        ? 'delete'
        : widget.group == null
        ? 'add'
        : 'edit';
    return DesktopManagementDialog(
      title: l.tr('desktop.servers.group.$action'),
      width: 420,
      busy: _saving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.delete)
            Text(
              l.trf('desktop.servers.group.deleteBody', [
                widget.group!.displayName,
              ]),
            )
          else
            Form(
              key: _formKey,
              child: TextFormField(
                key: const Key('desktop-group-name'),
                controller: _name,
                autofocus: true,
                enabled: !_saving,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 13, color: context.colors.text),
                decoration: desktopInputDecoration(
                  context,
                  hint: l.tr('desktop.servers.group.nameHint'),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l.tr('desktop.servers.group.nameRequired')
                    : null,
                onFieldSubmitted: (_) => _save(),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: context.colors.danger),
              ),
            ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.tr('common.cancel')),
        ),
        FilledButton(
          key: const Key('desktop-group-form-save'),
          onPressed: _saving ? null : _save,
          style: widget.delete
              ? FilledButton.styleFrom(backgroundColor: context.colors.danger)
              : null,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  l.tr(
                    widget.delete
                        ? 'common.delete'
                        : widget.group == null
                        ? 'desktop.servers.group.create'
                        : 'common.save',
                  ),
                ),
        ),
      ],
    );
  }
}
