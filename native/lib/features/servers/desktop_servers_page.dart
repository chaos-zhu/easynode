import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_dropdown_menu.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../../state/desktop_server_list_config_provider.dart';
import '../../state/proxy_list_notifier.dart';
import 'desktop_server_cell.dart';
import 'desktop_server_form_dialog.dart';
import 'desktop_server_groups_dialog.dart';
import 'desktop_server_list_settings_dialog.dart';
import 'desktop_server_order_draft.dart';
import 'desktop_server_order_view.dart';
import 'server_list_config.dart';
import 'server_model.dart';
import 'server_proxy_model.dart';
import 'server_repository.dart';

/// Desktop catalog and instance management; no SSH configuration is fetched.
class DesktopServersPage extends ConsumerStatefulWidget {
  const DesktopServersPage({super.key, this.onConnect});
  final ValueChanged<ServerModel>? onConnect;

  @override
  ConsumerState<DesktopServersPage> createState() => _DesktopServersPageState();
}

class _DesktopServersPageState extends ConsumerState<DesktopServersPage> {
  final _searchController = TextEditingController();
  final _collapsedGroups = <String>{};
  final _selectedIds = <String>{};
  String _query = '';
  DesktopServerOrderDraft? _orderDraft;
  bool _orderSaving = false;
  String? _orderError;

  void _startOrder() {
    final catalog = ref.read(desktopServerCatalogProvider).valueOrNull;
    if (catalog == null || catalog.hosts.isEmpty) return;
    setState(() {
      _selectedIds.clear();
      _searchController.clear();
      _query = '';
      _orderError = null;
      _orderDraft = DesktopServerOrderDraft(catalog.order);
      // Older catalogs may have no explicit flat order yet.
      _orderDraft!.flat.addAll(
        catalog.hosts
            .map((h) => h.id)
            .where((id) => !_orderDraft!.flat.contains(id)),
      );
    });
  }

  void _cancelOrder() => setState(() {
    _orderDraft = null;
    _orderError = null;
  });

  Future<void> _saveOrder() async {
    if (_orderSaving || _orderDraft == null) return;
    final grouped =
        ref.read(desktopServerListConfigProvider).valueOrNull?.displayMode !=
        'list';
    setState(() {
      _orderSaving = true;
      _orderError = null;
    });
    try {
      await ref
          .read(serverRepositoryProvider)
          .updateOrder(
            _orderDraft!.revision,
            _orderDraft!.instanceChanges(grouped: grouped),
          );
      if (!mounted) return;
      _cancelOrder();
      ref.invalidate(desktopServerCatalogProvider);
      _notify(AppLocalizations.of(context).tr('desktop.servers.orderSaved'));
    } catch (error) {
      if (!mounted) return;
      if (error is ApiFailure && error.statusCode == 409) {
        _cancelOrder();
        ref.invalidate(desktopServerCatalogProvider);
        _notify(AppLocalizations.of(context).tr('order.conflict'));
      } else {
        setState(
          () => _orderError = AppLocalizations.of(
            context,
          ).tr('desktop.servers.orderSaveFailed'),
        );
      }
    } finally {
      if (mounted) setState(() => _orderSaving = false);
    }
  }

  Future<void> _openGroups() => showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const DesktopServerGroupsDialog(),
  );

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

  Future<void> _openListSettings() async {
    final saved = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DesktopServerListSettingsDialog(),
    );
    if (saved != true || !mounted) return;
    if (ref
            .read(desktopServerListConfigProvider)
            .valueOrNull
            ?.shows('selection') ==
        false) {
      setState(_selectedIds.clear);
    }
    _notify(
      AppLocalizations.of(context).tr('desktop.servers.listSettings.saved'),
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
    final config = ref.watch(desktopServerListConfigProvider);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(catalog.valueOrNull),
        if (_orderError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _orderError!,
              style: TextStyle(color: context.colors.danger, fontSize: 13),
            ),
          ),
        if (config.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.tr('desktop.servers.listSettings.loadFailed'),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.danger,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(desktopServerListConfigProvider),
                  child: Text(l.tr('common.retry')),
                ),
              ],
            ),
          ),
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
            data: (catalog) => _orderDraft != null
                ? DesktopServerOrderView(
                    catalog: catalog,
                    config: config.valueOrNull ?? const ServerListConfig(),
                    draft: _orderDraft!,
                    saving: _orderSaving,
                    onReorder: (group, oldIndex, newIndex) {
                      if (_orderSaving) return;
                      setState(
                        () => DesktopServerOrderDraft.move(
                          group == null
                              ? _orderDraft!.flat
                              : _orderDraft!.items[group]!,
                          oldIndex,
                          newIndex,
                        ),
                      );
                    },
                  )
                : _catalogBody(
                    catalog,
                    config.valueOrNull ?? const ServerListConfig(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(HostCatalog? catalog) {
    final l = AppLocalizations.of(context);
    if (_orderDraft != null) {
      final grouped =
          ref.watch(desktopServerListConfigProvider).valueOrNull?.displayMode !=
          'list';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: context.colors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.swap_vert,
                color: context.colors.accent,
                size: 20,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.tr('desktop.servers.orderTitle'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l.tr(
                      grouped
                          ? 'desktop.servers.orderGroupHint'
                          : 'desktop.servers.orderFlatHint',
                    ),
                    style: TextStyle(fontSize: 12, color: context.colors.muted),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              key: const Key('desktop-server-order-cancel'),
              onPressed: _orderSaving ? null : _cancelOrder,
              style: desktopButtonStyle(context),
              child: Text(l.tr('common.cancel')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('desktop-server-order-save'),
              onPressed: _orderSaving ? null : _saveOrder,
              style: desktopButtonStyle(context, primary: true),
              child: _orderSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.tr('desktop.servers.orderSave')),
            ),
          ],
        ),
      );
    }
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
              onSelected: (value) {
                if (value == 'settings') {
                  _openListSettings();
                } else if (value == 'groups') {
                  _openGroups();
                } else if (value == 'order') {
                  _startOrder();
                } else {
                  _comingSoon();
                }
              },
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

  Widget _catalogBody(HostCatalog catalog, ServerListConfig config) {
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
    final flatIds = {
      ...catalog.order.flatItemIds,
      ...sections.expand((section) => section.itemIds),
      ...visibleHosts.map((host) => host.id),
    };
    return Column(
      children: [
        if (config.shows('selection') && _selectedIds.isNotEmpty)
          _batchToolbar(),
        Expanded(
          child: config.displayMode == 'list'
              ? ListView(
                  key: const Key('desktop-servers-flat-list'),
                  padding: const EdgeInsets.only(top: 12, bottom: 16),
                  children: [
                    _serverTable(
                      'flat',
                      flatIds
                          .map((id) => hostById[id])
                          .whereType<ServerModel>()
                          .toList(),
                      catalog,
                      config,
                    ),
                  ],
                )
              : ListView.builder(
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
                      catalog,
                      config,
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

  Widget _group(
    String id,
    String name,
    List<ServerModel> hosts,
    HostCatalog catalog,
    ServerListConfig config,
  ) {
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
        if (!collapsed) _serverTable(id, hosts, catalog, config),
      ],
    );
  }

  Widget _serverTable(
    String id,
    List<ServerModel> hosts,
    HostCatalog catalog,
    ServerListConfig config,
  ) => _ServerTable(
    key: ValueKey('desktop-server-table-$id'),
    hosts: hosts,
    allHosts: catalog.hosts,
    config: config,
    selectedIds: _selectedIds,
    onSelection: (ids, selected) => setState(() {
      selected ? _selectedIds.addAll(ids) : _selectedIds.removeAll(ids);
    }),
    onAction: _comingSoon,
    onConnect: (server) {
      if (!server.canConnect) {
        _openForm(server: server);
      } else if (widget.onConnect != null) {
        widget.onConnect!(server);
      } else {
        _comingSoon();
      }
    },
    onEdit: (server) => _openForm(server: server),
    onDelete: _confirmDelete,
  );

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

class _ServerTable extends ConsumerStatefulWidget {
  const _ServerTable({
    super.key,
    required this.hosts,
    required this.allHosts,
    required this.config,
    required this.selectedIds,
    required this.onSelection,
    required this.onAction,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ServerModel> hosts;
  final List<ServerModel> allHosts;
  final ServerListConfig config;
  final Set<String> selectedIds;
  final void Function(Iterable<String> ids, bool selected) onSelection;
  final VoidCallback onAction;
  final ValueChanged<ServerModel> onConnect;
  final ValueChanged<ServerModel> onEdit;
  final ValueChanged<ServerModel> onDelete;

  @override
  ConsumerState<_ServerTable> createState() => _ServerTableState();
}

class _ServerTableState extends ConsumerState<_ServerTable> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
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
    final selection = widget.config.shows('selection');
    final visibleColumns = ServerListConfig.defaultColumns.keys
        .where((key) => key != 'selection' && widget.config.shows(key))
        .toList();
    final needsProxies =
        widget.config.shows('proxyType') &&
        widget.hosts.any((host) => host.proxyType == 'proxyServer');
    final proxies = needsProxies
        ? ref.watch(proxyListProvider).valueOrNull ?? const <ServerProxyModel>[]
        : const <ServerProxyModel>[];
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
              builder: (context, constraints) => ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: table(
                      selection: selection,
                      columns: [
                        if (visibleColumns.isEmpty)
                          const DataColumn(label: SizedBox.shrink()),
                        for (final key in visibleColumns)
                          DataColumn(
                            label: Text(
                              l.tr(
                                'servers.field.${key == 'tag' ? 'tags' : key}',
                              ),
                            ),
                          ),
                      ],
                      rows: [
                        for (final host in widget.hosts)
                          DataRow(
                            key: ValueKey(host.id),
                            selected:
                                selection &&
                                widget.selectedIds.contains(host.id),
                            onSelectChanged: selection
                                ? (value) => widget.onSelection([
                                    host.id,
                                  ], value ?? false)
                                : null,
                            cells: [
                              if (visibleColumns.isEmpty)
                                const DataCell(SizedBox.shrink()),
                              for (final column in visibleColumns)
                                DataCell(
                                  DesktopServerCell(
                                    host: host,
                                    column: column,
                                    allHosts: widget.allHosts,
                                    proxies: proxies,
                                    onEdit: widget.onEdit,
                                    onAction: widget.onAction,
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
                    selected: selection && widget.selectedIds.contains(host.id),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: actionWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: TextButton.icon(
                                  onPressed: () => widget.onConnect(host),
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
