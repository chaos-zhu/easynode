import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_reorder_proxy.dart';
import '../../l10n/app_localizations.dart';
import '../../state/proxy_list_notifier.dart';
import 'desktop_server_cell.dart';
import 'desktop_server_order_draft.dart';
import 'server_list_config.dart';
import 'server_model.dart';
import 'server_proxy_model.dart';
import 'server_repository.dart';

/// One vertical scroll view keeps row dragging and auto-scroll consistent across groups.
class DesktopServerOrderView extends ConsumerStatefulWidget {
  const DesktopServerOrderView({
    super.key,
    required this.catalog,
    required this.config,
    required this.draft,
    required this.onReorder,
    required this.saving,
  });

  final HostCatalog catalog;
  final ServerListConfig config;
  final DesktopServerOrderDraft draft;
  final void Function(String? groupId, int oldIndex, int newIndex) onReorder;
  final bool saving;

  @override
  ConsumerState<DesktopServerOrderView> createState() =>
      _DesktopServerOrderViewState();
}

class _DesktopServerOrderViewState
    extends ConsumerState<DesktopServerOrderView> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l = AppLocalizations.of(context);
    final columns = ServerListConfig.defaultColumns.keys
        .where((key) => key != 'selection' && widget.config.shows(key))
        .toList();
    final hostById = {for (final host in widget.catalog.hosts) host.id: host};
    final groupById = {
      for (final group in widget.catalog.groups) group.id: group,
    };
    final grouped = widget.config.displayMode != 'list';
    final rows = <String?, List<ServerModel>>{
      if (!grouped)
        null: widget.draft.flat
            .map((id) => hostById[id])
            .whereType<ServerModel>()
            .toList()
      else
        for (final group in widget.draft.groups)
          if (widget.draft.items[group]!.isNotEmpty)
            group: widget.draft.items[group]!
                .map((id) => hostById[id])
                .whereType<ServerModel>()
                .toList(),
    };
    final needsProxies =
        columns.contains('proxyType') &&
        widget.catalog.hosts.any((h) => h.proxyType == 'proxyServer');
    final proxies = needsProxies
        ? ref.watch(proxyListProvider).valueOrNull ?? const <ServerProxyModel>[]
        : const <ServerProxyModel>[];
    final rowHeight = math.max(
      56.0,
      MediaQuery.textScalerOf(context).scale(36),
    );

    Widget cells(ServerModel? host) => Row(
      children: [
        SizedBox(
          width: 64,
          child: host == null
              ? null
              : Icon(Icons.drag_indicator, size: 18, color: colors.muted),
        ),
        for (final column in columns)
          SizedBox(
            width: DesktopServerCell.columnWidth(column) + 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: host == null
                  ? Text(
                      l.tr(
                        'servers.field.${column == 'tag' ? 'tags' : column}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.muted,
                      ),
                    )
                  : DesktopServerCell(
                      host: host,
                      column: column,
                      allHosts: widget.catalog.hosts,
                      proxies: proxies,
                      ordering: true,
                    ),
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth - 32,
          64 +
              columns.fold<double>(
                0,
                (sum, c) => sum + DesktopServerCell.columnWidth(c) + 32,
              ),
        );
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SizedBox(
              width: width,
              height: math.max(0, constraints.maxHeight - 24),
              child: CustomScrollView(
                key: const Key('desktop-server-order-scroll'),
                slivers: [
                  for (final entry in rows.entries) ...[
                    if (entry.key != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '${groupById[entry.key]?.displayName ?? l.tr('servers.defaultGroup')}  ${entry.value.length}',
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Container(
                        height: math.max(
                          46,
                          MediaQuery.textScalerOf(context).scale(30),
                        ),
                        decoration: BoxDecoration(
                          color: colors.chip,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                        ),
                        child: cells(null),
                      ),
                    ),
                    SliverReorderableList(
                      key: ValueKey(
                        'desktop-server-order-${entry.key ?? 'flat'}',
                      ),
                      itemCount: entry.value.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          widget.onReorder(entry.key, oldIndex, newIndex),
                      proxyDecorator: buildAppReorderProxy,
                      itemBuilder: (context, index) {
                        final host = entry.value[index];
                        return ReorderableDragStartListener(
                          key: ValueKey('desktop-server-order-row-${host.id}'),
                          index: index,
                          enabled: !widget.saving,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Material(
                              color: colors.card,
                              child: Container(
                                height: rowHeight,
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: colors.border,
                                      width: .5,
                                    ),
                                  ),
                                ),
                                child: cells(host),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
