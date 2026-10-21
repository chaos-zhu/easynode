import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_dropdown_menu.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_server_catalog_provider.dart';
import 'desktop_server_form_dialog.dart';
import 'server_model.dart';
import 'server_repository.dart';

/// Desktop catalog and instance management; no SSH configuration is fetched.
class DesktopServersPage extends ConsumerStatefulWidget {
  const DesktopServersPage({super.key});

  @override
  ConsumerState<DesktopServersPage> createState() => _DesktopServersPageState();
}

class _DesktopServersPageState extends ConsumerState<DesktopServersPage> {
  final _searchController = TextEditingController();
  final _collapsedGroups = <String>{};
  final _selectedIds = <String>{};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _comingSoon() {
    _notify(AppLocalizations.of(context).tr('desktop.comingSoon'));
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _openForm({ServerModel? server}) async {
    final catalog = ref.read(desktopServerCatalogProvider).valueOrNull;
    if (catalog == null) return;
    final changed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      closeOnPressEscape: false,
      builder: (context) =>
          DesktopServerFormDialog(catalog: catalog, server: server),
    );
    if (changed != true || !mounted) return;
    ref.invalidate(desktopServerCatalogProvider);
    _notify(
      AppLocalizations.of(
        context,
      ).tr(server == null ? 'desktop.servers.form.created' : 'common.saved'),
    );
  }

  Future<void> _confirmDelete(ServerModel server) async {
    final l = AppLocalizations.of(context);
    var deleting = false;
    String? failure;
    final deleted = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => DesktopManagementDialog(
          title: l.tr('desktop.servers.deleteInstance'),
          width: 440,
          busy: deleting,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.trf('servers.deleteConfirmBody', [server.displayName])),
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    failure!,
                    style: TextStyle(color: context.colors.danger),
                  ),
                ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: deleting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(l.tr('common.cancel')),
            ),
            FilledButton(
              key: const Key('desktop-server-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.danger,
                foregroundColor: context.colors.card,
              ),
              onPressed: deleting
                  ? null
                  : () async {
                      setDialogState(() {
                        deleting = true;
                        failure = null;
                      });
                      try {
                        await ref
                            .read(serverRepositoryProvider)
                            .deleteHost(server.id);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            deleting = false;
                            failure = l.trf('servers.deleteFailed', [
                              error is ApiFailure
                                  ? error.message
                                  : l.tr(
                                      'desktop.servers.form.operationFailed',
                                    ),
                            ]);
                          });
                        }
                      }
                    },
              child: deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.tr('common.delete')),
            ),
          ],
        ),
      ),
    );
    if (deleted != true || !mounted) return;
    setState(() => _selectedIds.remove(server.id));
    ref.invalidate(desktopServerCatalogProvider);
    _notify(l.tr('desktop.servers.form.deleted'));
  }

  bool _matches(ServerModel host) => [
    host.name,
    host.username,
    host.host,
    ...host.tag,
  ].any((value) => value.toLowerCase().contains(_query.trim().toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(desktopServerCatalogProvider);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(catalog.valueOrNull),
        Expanded(
          child: catalog.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _message(
              Icons.cloud_off_outlined,
              l.tr('desktop.servers.loadFailed'),
              actions: [
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(desktopServerCatalogProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l.tr('common.retry')),
                ),
              ],
            ),
            data: _catalogBody,
          ),
        ),
      ],
    );
  }

  Widget _toolbar(HostCatalog? catalog) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: (catalog?.hosts.length ?? 0) > 2
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: math.min(380, constraints.maxWidth * .48),
                        child: TextField(
                          key: const Key('desktop-servers-search'),
                          controller: _searchController,
                          autocorrect: false,
                          style: const TextStyle(fontSize: 13),
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: l.tr('desktop.servers.searchHint'),
                            isDense: true,
                            filled: true,
                            fillColor: context.colors.chip,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: l.tr(
                                      'desktop.servers.clearSearch',
                                    ),
                                    onPressed: _clearSearch,
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Text(
                      l.trf('desktop.servers.total', [
                        catalog?.hosts.length ?? 0,
                      ]),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 13,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const Key('desktop-servers-add'),
              onPressed: catalog == null ? null : _openForm,
              style: desktopButtonStyle(context, primary: true),
              icon: const Icon(Icons.add, size: 17),
              label: Text(l.tr('desktop.servers.add')),
            ),
            const SizedBox(width: 8),
            DesktopDropdownMenu<String>(
              key: const Key('desktop-servers-more'),
              tooltip: l.tr('desktop.servers.more'),
              onSelected: (_) => _comingSoon(),
              items: [
                _menuItem(
                  'groups',
                  Icons.folder_open,
                  'desktop.servers.groups',
                ),
                _menuItem('settings', Icons.tune, 'desktop.servers.settings'),
                _menuItem('order', Icons.swap_vert, 'desktop.servers.order'),
                _menuItem(
                  'import',
                  Icons.file_upload_outlined,
                  'desktop.servers.import',
                  divided: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DesktopDropdownItem<String> _menuItem(
    String value,
    IconData icon,
    String key, {
    bool divided = false,
  }) => DesktopDropdownItem(
    value: value,
    icon: icon,
    label: AppLocalizations.of(context).tr(key),
    divided: divided,
  );

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  Widget _catalogBody(HostCatalog catalog) {
    final l = AppLocalizations.of(context);
    if (catalog.hosts.isEmpty) {
      return _message(
        Icons.dns_outlined,
        l.tr('desktop.servers.empty'),
        actions: [
          FilledButton.icon(
            onPressed: _openForm,
            style: desktopButtonStyle(context, primary: true),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l.tr('desktop.servers.addConfig')),
          ),
          OutlinedButton.icon(
            onPressed: _comingSoon,
            icon: const Icon(Icons.file_upload_outlined, size: 16),
            label: Text(l.tr('desktop.servers.import')),
          ),
        ],
      );
    }
    final visibleHosts = catalog.hosts.where(_matches).toList();
    if (visibleHosts.isEmpty) {
      return _message(Icons.search_off, l.tr('servers.emptyFiltered'));
    }
    final hostById = {for (final host in visibleHosts) host.id: host};
    final groupById = {for (final group in catalog.groups) group.id: group};
    final sections = catalog.order.sections
        .where((section) => section.itemIds.any(hostById.containsKey))
        .toList();
    return Column(
      children: [
        if (_selectedIds.isNotEmpty) _batchToolbar(),
        Expanded(
          child: ListView.builder(
            key: const Key('desktop-servers-list'),
            padding: const EdgeInsets.only(top: 12, bottom: 16),
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final section = sections[index];
              return _group(
                section.groupId,
                groupById[section.groupId]?.displayName ??
                    l.tr('servers.defaultGroup'),
                section.itemIds
                    .map((id) => hostById[id])
                    .whereType<ServerModel>()
                    .toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _batchToolbar() {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l.trf('desktop.servers.selected', [_selectedIds.length])),
          for (final action in [
            'batchConnect',
            'batchEdit',
            'export',
            'delete',
            'invert',
            'clearSelection',
          ])
            TextButton(
              onPressed: _comingSoon,
              child: Text(l.tr('desktop.servers.$action')),
            ),
        ],
      ),
    );
  }

  Widget _group(String id, String name, List<ServerModel> hosts) {
    final collapsed = _collapsedGroups.contains(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('desktop-server-group-$id'),
          onTap: () => setState(() {
            if (collapsed) {
              _collapsedGroups.remove(id);
            } else {
              _collapsedGroups.add(id);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.chip,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${hosts.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: context.colors.muted,
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          _ServerTable(
            key: ValueKey('desktop-server-table-$id'),
            hosts: hosts,
            selectedIds: _selectedIds,
            onSelection: (ids, selected) => setState(() {
              selected ? _selectedIds.addAll(ids) : _selectedIds.removeAll(ids);
            }),
            onAction: _comingSoon,
            onEdit: (server) => _openForm(server: server),
            onDelete: _confirmDelete,
          ),
      ],
    );
  }

  Widget _message(
    IconData icon,
    String title, {
    List<Widget> actions = const [],
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: context.colors.softMuted),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    ),
  );
}

class _ServerTable extends StatefulWidget {
  const _ServerTable({
    super.key,
    required this.hosts,
    required this.selectedIds,
    required this.onSelection,
    required this.onAction,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ServerModel> hosts;
  final Set<String> selectedIds;
  final void Function(Iterable<String> ids, bool selected) onSelection;
  final VoidCallback onAction;
  final ValueChanged<ServerModel> onEdit;
  final ValueChanged<ServerModel> onDelete;

  @override
  State<_ServerTable> createState() => _ServerTableState();
}

class _ServerTableState extends State<_ServerTable> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  Widget _text(String value, double width) => SizedBox(
    width: width,
    child: Text(
      value.isEmpty ? '--' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Future<void> _copyHost(String host) async {
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: host));
      message = 'servers.hostCopied';
    } catch (_) {
      message = 'desktop.servers.copyFailed';
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).tr(message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final headingHeight = math.max(
      46.0,
      MediaQuery.textScalerOf(context).scale(30),
    );
    final actionWidth = math.max(
      128.0,
      MediaQuery.textScalerOf(context).scale(90) + 30,
    );
    final rowHeight = math.max(
      56.0,
      MediaQuery.textScalerOf(context).scale(36),
    );
    DataTable table({
      required List<DataColumn> columns,
      required List<DataRow> rows,
      bool selection = false,
    }) => DataTable(
      headingRowHeight: headingHeight,
      dataRowMinHeight: rowHeight,
      dataRowMaxHeight: rowHeight,
      horizontalMargin: 16,
      columnSpacing: 24,
      showCheckboxColumn: selection,
      onSelectAll: selection
          ? (value) => widget.onSelection(
              widget.hosts.map((host) => host.id),
              value ?? false,
            )
          : null,
      headingRowColor: WidgetStatePropertyAll(colors.chip),
      headingTextStyle: TextStyle(
        color: colors.muted,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      dataTextStyle: TextStyle(color: colors.text, fontSize: 13),
      dividerThickness: .5,
      columns: columns,
      rows: rows,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: table(
                      selection: true,
                      columns: [
                        for (final key in [
                          'name',
                          'username',
                          'host',
                          'port',
                          'authType',
                          'tags',
                        ])
                          DataColumn(label: Text(l.tr('servers.field.$key'))),
                      ],
                      rows: [
                        for (final host in widget.hosts)
                          DataRow(
                            key: ValueKey(host.id),
                            selected: widget.selectedIds.contains(host.id),
                            onSelectChanged: (value) =>
                                widget.onSelection([host.id], value ?? false),
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 180,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _ServerCellLink(
                                      key: ValueKey(
                                        'desktop-server-name-${host.id}',
                                      ),
                                      label: host.displayName,
                                      tooltip: l.tr('desktop.servers.edit'),
                                      icon: host.isWindows
                                          ? 'assets/windows.svg'
                                          : 'assets/linux.svg',
                                      onPressed: () => widget.onEdit(host),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(_text(host.username, 90)),
                              DataCell(
                                SizedBox(
                                  width: 150,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _ServerCellLink(
                                      key: ValueKey(
                                        'desktop-server-host-${host.id}',
                                      ),
                                      label: host.host.isEmpty
                                          ? '--'
                                          : host.host,
                                      tooltip: l.tr('servers.copyHost'),
                                      copy: true,
                                      onPressed: host.host.isEmpty
                                          ? null
                                          : () => _copyHost(host.host),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(_text('${host.port}', 48)),
                              DataCell(
                                _text(
                                  l.tr(
                                    'servers.auth.${host.authType == 'password' ? 'password' : 'privateKey'}',
                                  ),
                                  85,
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 140,
                                  child: host.tag.isEmpty
                                      ? const Text('--')
                                      : SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              for (final tag in host.tag)
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    right: 4,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: colors.success
                                                        .withValues(alpha: .08),
                                                    border: Border.all(
                                                      color: colors.success
                                                          .withValues(
                                                            alpha: .3,
                                                          ),
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    tag,
                                                    style: TextStyle(
                                                      color: colors.success,
                                                      fontSize: 12,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colors.border)),
            ),
            child: table(
              columns: [
                DataColumn(
                  label: SizedBox(
                    width: actionWidth,
                    child: Text(
                      l.tr('desktop.servers.actions'),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              ],
              rows: [
                for (final host in widget.hosts)
                  DataRow(
                    selected: widget.selectedIds.contains(host.id),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: actionWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: TextButton.icon(
                                  onPressed: widget.onAction,
                                  icon: const Icon(Icons.link, size: 16),
                                  label: Text(
                                    l.tr('desktop.servers.connect'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                ),
                              ),
                              DesktopDropdownMenu<String>(
                                key: ValueKey(
                                  'desktop-server-actions-${host.id}',
                                ),
                                tooltip: l.tr('desktop.servers.actions'),
                                buttonSize: const Size(30, 32),
                                onSelected: (value) {
                                  if (value == 'edit') widget.onEdit(host);
                                  if (value == 'delete') widget.onDelete(host);
                                },
                                items: [
                                  DesktopDropdownItem(
                                    value: 'edit',
                                    label: l.tr('desktop.servers.edit'),
                                    icon: Icons.edit_outlined,
                                  ),
                                  DesktopDropdownItem(
                                    value: 'delete',
                                    label: l.tr(
                                      'desktop.servers.deleteInstance',
                                    ),
                                    icon: Icons.delete_outline,
                                    divided: true,
                                    danger: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Text-only table actions matching Web's name and copyable host cells.
class _ServerCellLink extends StatelessWidget {
  const _ServerCellLink({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.copy = false,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? icon;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    bool highlighted(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 3),
          ),
          alignment: Alignment.centerLeft,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          mouseCursor: WidgetStatePropertyAll(
            copy ? SystemMouseCursors.copy : SystemMouseCursors.click,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => highlighted(states) ? colors.accent : colors.text,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 13,
              fontWeight: copy ? FontWeight.w400 : FontWeight.w600,
              decoration: highlighted(states)
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationStyle: TextDecorationStyle.dashed,
              decorationColor: colors.accent.withValues(alpha: .5),
            ),
          ),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? colors.accent
                  : Colors.transparent,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          ),
          animationDuration: const Duration(milliseconds: 180),
          splashFactory: NoSplash.splashFactory,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              SvgPicture.asset(icon!, width: 17, height: 17),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
