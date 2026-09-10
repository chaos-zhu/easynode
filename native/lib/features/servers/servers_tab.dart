import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_overflow_menu.dart';
import '../../core/ui/app_reorder_proxy.dart';
import '../../core/ui/app_swipe_actions.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../core/ui/top_notice.dart';
import '../../core/api/api_result.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/host_list_notifier.dart';
import '../../state/group_list_notifier.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/order_notifiers.dart';
import '../../state/server_data_refresh.dart';
import '../../state/terminal_providers.dart';
import 'server_form_page.dart';
import 'server_group_model.dart';
import 'server_repository.dart';
import '../shell/tab_header.dart';
import '../terminal/ssh_connection_config.dart';
import '../terminal/terminal_shell_page.dart';
import '../terminal/terminal_session_manager.dart';
import 'server_model.dart';
import '../order/order_layout.dart';

const _kServerCardHeight = 60.0;

/// First bottom-nav tab — server list + connect action. Was a top-level
/// page that built its own ServerRepository / TerminalSessionManager; now
/// it sources both from providers so state stays consistent across tabs.
class ServersTab extends ConsumerStatefulWidget {
  const ServersTab({super.key});

  @override
  ConsumerState<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends ConsumerState<ServersTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  final AppSwipeActionsController _swipeActionsController =
      AppSwipeActionsController();
  final Set<String> _connectingIds = {};
  final Set<String> _collapsedGroupIds = {};
  String? _expandedServerId;
  String _query = '';
  bool _searchVisible = false;
  bool _orderMode = false;
  bool _orderSaving = false;
  int _orderRevision = 0;
  Map<String, List<String>> _orderDraftByGroup = const {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _swipeActionsController.dispose();
    super.dispose();
  }

  void toggleServerExpanded(String id) {
    _swipeActionsController.close();
    setState(() {
      _expandedServerId = _expandedServerId == id ? null : id;
    });
  }

  void _closeTransientRows({bool collapseDetails = false}) {
    _swipeActionsController.close();
    if (collapseDetails && _expandedServerId != null) {
      setState(() => _expandedServerId = null);
    }
  }

  Future<void> _copyHost(ServerModel server) async {
    await Clipboard.setData(ClipboardData(text: server.host));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).tr('servers.hostCopied')),
      ),
    );
  }

  Future<void> _refresh() async {
    if (_orderMode) return;
    await runRefreshWithFeedback(context, () => refreshServerSharedData(ref));
  }

  Future<void> _connect(ServerModel server) async {
    _swipeActionsController.close();
    if (_connectingIds.contains(server.id)) return;
    if (!server.isConfig) {
      await _openForm(server: server);
      return;
    }
    if (server.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).tr('servers.windowsUnsupported'),
          ),
        ),
      );
      return;
    }
    if (!ref.read(isPlusActiveProvider) &&
        (server.proxyType == 'proxyServer' ||
            server.proxyType == 'jumpHosts')) {
      showTopNotice(
        context,
        AppLocalizations.of(context).tr('plus.serverManagedTip'),
      );
      return;
    }
    final manager = ref.read(terminalSessionManagerProvider);

    setState(() => _connectingIds.add(server.id));
    final SshConnectionConfig config;
    try {
      config = await ref
          .read(serverRepositoryProvider)
          .fetchSshConfig(server.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).trf('servers.fetchSshFailed', [error.toString()]),
          ),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _connectingIds.remove(server.id));
    }

    if (!mounted) return;
    await manager.openSession(config);
    if (!mounted) return;
    _openShell();
  }

  void _handleServerTap(ServerModel server) {
    if (_swipeActionsController.openItemId != null) {
      _swipeActionsController.close();
      return;
    }
    if (_expandedServerId == server.id) {
      setState(() => _expandedServerId = null);
      return;
    }
    _connect(server);
  }

  void _openShell() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TerminalShellPage()));
  }

  Future<void> _openForm({ServerModel? server}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ServerFormPage(server: server)),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  Future<void> _confirmDelete(ServerModel server) async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var deleting = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> delete() async {
              setDialogState(() => deleting = true);
              try {
                final message = await ref
                    .read(serverRepositoryProvider)
                    .deleteHost(server.id);
                if (!mounted) return;
                setState(() {
                  if (_expandedServerId == server.id) {
                    _expandedServerId = null;
                  }
                });
                await _refresh();
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              } catch (error) {
                if (!mounted) return;
                if (dialogContext.mounted) {
                  setDialogState(() => deleting = false);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l.trf('servers.deleteFailed', [error.toString()]),
                    ),
                  ),
                );
              }
            }

            return PopScope(
              canPop: !deleting,
              child: AlertDialog(
                title: Text(l.tr('servers.deleteConfirmTitle')),
                content: Text(
                  l.trf('servers.deleteConfirmBody', [server.displayName]),
                ),
                actions: [
                  TextButton(
                    onPressed: deleting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: Text(l.tr('common.cancel')),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.colors.danger,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: context.colors.danger.withValues(
                        alpha: 0.62,
                      ),
                      disabledForegroundColor: Colors.white,
                    ),
                    onPressed: deleting ? null : delete,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: deleting
                          ? Row(
                              key: const ValueKey('deleting'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(l.tr('common.delete')),
                              ],
                            )
                          : Text(
                              l.tr('common.delete'),
                              key: const ValueKey('delete-label'),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _toggleSearch() {
    if (_orderMode) return;
    _closeTransientRows(collapseDetails: true);
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  Future<void> _confirmCloseAllTerminals() async {
    final manager = ref.read(terminalSessionManagerProvider);
    final count = manager.sessions.length;
    if (count == 0) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('servers.closeAllTitle')),
        content: Text(
          count == 1
              ? l.tr('servers.closeAllBodyOne')
              : l.trf('servers.closeAllBodyMany', [count]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.tr('common.closeAll')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await manager.closeAll();
  }

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostListProvider);
    final groupsAsync = ref.watch(groupListProvider);
    final manager = ref.watch(terminalSessionManagerProvider);
    ref.watch(hostOrderProvider);

    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: RefreshIndicator(
        color: context.colors.primary,
        backgroundColor: context.colors.card,
        displacement: 30,
        edgeOffset: 6,
        strokeWidth: 2,
        onRefresh: _refresh,
        child: AnimatedBuilder(
          animation: manager,
          builder: (context, _) => _buildBody(hostsAsync, groupsAsync, manager),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l) {
    return TabHeader(
      title: l.tr('tabs.servers'),
      actions: [
        if (_orderMode) ...[
          TextButton(
            onPressed: _orderSaving ? null : _cancelOrder,
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: _orderSaving ? null : _saveOrder,
            child: Text(l.tr('common.save')),
          ),
        ] else ...[
          _HeaderIconButton(
            tooltip: l.tr('servers.addServer'),
            icon: Icons.add,
            onPressed: () => _openForm(),
          ),
          const SizedBox(width: 4),
          AppOverflowMenu<String>(
            key: const ValueKey('server-more-menu'),
            tooltip: l.tr('common.moreActions'),
            items: [
              AppOverflowMenuItem(
                value: 'search',
                icon: _searchVisible ? Icons.close : Icons.search,
                label: _searchVisible
                    ? l.tr('common.closeSearch')
                    : l.tr('common.search'),
              ),
              AppOverflowMenuItem(
                value: 'order',
                icon: Icons.swap_vert,
                label: l.tr('common.adjustOrder'),
              ),
            ],
            onSelected: (action) {
              if (action == 'search') {
                _toggleSearch();
              } else if (action == 'order') {
                _startOrder();
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _buildBody(
    AsyncValue<List<ServerModel>> hostsAsync,
    AsyncValue<List<ServerGroupModel>> groupsAsync,
    TerminalSessionManager manager,
  ) {
    final l = AppLocalizations.of(context);
    return hostsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 56),
            Center(child: Text(error.toString(), textAlign: TextAlign.center)),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _refresh,
                child: Text(l.tr('common.retry')),
              ),
            ),
          ],
        );
      },
      data: (servers) {
        final groups = groupsAsync.valueOrNull ?? const <ServerGroupModel>[];
        final searched = _orderMode
            ? servers
            : _searchedServers(servers, groups);
        final sessions = manager.sessions.length;
        return Column(
          children: [
            _buildHeader(l),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_orderMode)
                    _ActiveTerminalBanner(
                      count: sessions,
                      onTap: _openShell,
                      onCloseAll: _confirmCloseAllTerminals,
                    ),
                  if (!_orderMode)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: _searchVisible
                            ? Padding(
                                key: const ValueKey('search-field'),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: _searchCtrl,
                                    autofocus: true,
                                    cursorColor: context.colors.primary,
                                    style: TextStyle(
                                      color: context.colors.text,
                                      fontSize: 14,
                                    ),
                                    decoration: _searchFieldDecoration(
                                      context,
                                      hintText: l.tr('servers.searchHint'),
                                    ),
                                    onChanged: (value) => setState(() {
                                      _query = value.trim().toLowerCase();
                                      _collapsedGroupIds.clear();
                                    }),
                                  ),
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('search-empty'),
                                width: double.infinity,
                              ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (_) {
                  _closeTransientRows(collapseDetails: true);
                  return false;
                },
                child: _buildGroupedList(
                  l: l,
                  servers: servers,
                  groups: groups,
                  searched: searched,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startOrder() async {
    _closeTransientRows(collapseDetails: true);
    final catalog = await ref.read(serverRepositoryProvider).fetchCatalog();
    if (!mounted) return;
    setState(() {
      _searchVisible = false;
      _searchCtrl.clear();
      _query = '';
      _orderRevision = catalog.order.revision;
      _orderDraftByGroup = _createOrderDraft(catalog);
      _collapsedGroupIds.clear();
      _orderMode = true;
    });
  }

  void _cancelOrder() => setState(() {
    _orderMode = false;
    _orderDraftByGroup = const {};
  });

  void _reorder(String groupId, int oldIndex, int newIndex) {
    setState(() {
      final draft = [...?_orderDraftByGroup[groupId]];
      final id = draft.removeAt(oldIndex);
      draft.insert(newIndex, id);
      _orderDraftByGroup = {..._orderDraftByGroup, groupId: draft};
    });
  }

  Future<void> _saveOrder() async {
    setState(() => _orderSaving = true);
    try {
      await ref
          .read(serverRepositoryProvider)
          .updateOrder(
            _orderRevision,
            _orderDraftByGroup.entries
                .map(
                  (entry) => OrderChange(
                    scope: 'groupItems',
                    groupId: entry.key,
                    orderedIds: entry.value,
                  ),
                )
                .toList(growable: false),
          );
      await refreshServerSharedData(ref);
      if (!mounted) return;
      _cancelOrder();
    } catch (error) {
      if (!mounted) return;
      _cancelOrder();
      if (error is ApiFailure && error.statusCode == 409) {
        await refreshServerSharedData(ref);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).tr('order.conflict')),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _orderSaving = false);
    }
  }

  List<ServerModel> _searchedServers(
    List<ServerModel> servers,
    List<ServerGroupModel> groups,
  ) {
    if (_query.isEmpty) return servers;
    return servers
        .where((server) {
          final groupName = _groupDisplayName(server, groups);
          final haystack = [
            server.name,
            server.host,
            server.username,
            server.group,
            groupName,
            ...server.tag,
          ].join(' ').toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
  }

  static String _normalizedGroupId(String groupId) {
    return groupId.isEmpty ? 'default' : groupId;
  }

  Map<String, List<String>> _createOrderDraft(HostCatalog catalog) {
    final hostsById = {for (final host in catalog.hosts) host.id: host};
    final groupIds = <String>[];

    void addGroup(String groupId) {
      if (!groupIds.contains(groupId)) groupIds.add(groupId);
    }

    for (final section in catalog.order.sections) {
      addGroup(section.groupId);
    }
    for (final group in catalog.groups) {
      addGroup(group.id);
    }
    for (final host in catalog.hosts) {
      addGroup(_normalizedGroupId(host.group));
    }

    final draft = <String, List<String>>{};
    for (final groupId in groupIds) {
      final orderedIds = catalog.order.sections
          .where((section) => section.groupId == groupId)
          .expand((section) => section.itemIds)
          .where(
            (id) =>
                hostsById.containsKey(id) &&
                _normalizedGroupId(hostsById[id]!.group) == groupId,
          )
          .toList();
      final seen = orderedIds.toSet();
      orderedIds.addAll(
        catalog.hosts
            .where(
              (host) =>
                  _normalizedGroupId(host.group) == groupId &&
                  !seen.contains(host.id),
            )
            .map((host) => host.id),
      );
      draft[groupId] = orderedIds;
    }
    return draft;
  }

  List<_ServerGroupSection> _serverSections({
    required List<ServerModel> servers,
    required List<ServerGroupModel> groups,
    required AppLocalizations l,
  }) {
    final hostsById = {for (final host in servers) host.id: host};
    final groupNames = {
      for (final group in groups) group.id: group.displayName,
    };
    final order = ref.read(hostOrderProvider);
    final orderedIdsByGroup = _orderMode
        ? _orderDraftByGroup
        : <String, List<String>>{
            for (final section in order?.sections ?? const <OrderSection>[])
              section.groupId: section.itemIds,
          };
    final groupIds = <String>[];

    void addGroup(String groupId) {
      if (!groupIds.contains(groupId)) groupIds.add(groupId);
    }

    for (final groupId in orderedIdsByGroup.keys) {
      addGroup(groupId);
    }
    for (final group in groups) {
      addGroup(group.id);
    }
    for (final host in servers) {
      addGroup(_normalizedGroupId(host.group));
    }

    return groupIds
        .map((groupId) {
          final orderedHosts = <ServerModel>[];
          final seen = <String>{};
          for (final id in orderedIdsByGroup[groupId] ?? const <String>[]) {
            final host = hostsById[id];
            if (host != null &&
                _normalizedGroupId(host.group) == groupId &&
                seen.add(id)) {
              orderedHosts.add(host);
            }
          }
          for (final host in servers) {
            if (_normalizedGroupId(host.group) == groupId &&
                seen.add(host.id)) {
              orderedHosts.add(host);
            }
          }
          return _ServerGroupSection(
            id: groupId,
            name:
                groupNames[groupId] ??
                (groupId == 'default' ? l.tr('servers.defaultGroup') : groupId),
            servers: orderedHosts,
          );
        })
        .where((section) => section.servers.isNotEmpty)
        .toList(growable: false);
  }

  Widget _buildGroupedList({
    required AppLocalizations l,
    required List<ServerModel> servers,
    required List<ServerGroupModel> groups,
    required List<ServerModel> searched,
  }) {
    final sections = _serverSections(servers: searched, groups: groups, l: l);
    final slivers = <Widget>[];

    if (servers.isEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _MessageState(message: l.tr('servers.emptyHint')),
          ),
        ),
      );
    } else if (sections.isEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _MessageState(message: l.tr('servers.emptyFiltered')),
          ),
        ),
      );
    } else {
      for (
        var sectionIndex = 0;
        sectionIndex < sections.length;
        sectionIndex++
      ) {
        final section = sections[sectionIndex];
        final expanded = !_collapsedGroupIds.contains(section.id);
        if (sectionIndex > 0) {
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 5, 20, 1),
              sliver: SliverToBoxAdapter(
                child: Divider(
                  key: ValueKey('server-group-divider-$sectionIndex'),
                  height: 1,
                  thickness: 1,
                  color: context.colors.border.withValues(alpha: 0.55),
                ),
              ),
            ),
          );
        }
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, sectionIndex == 0 ? 2 : 1, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _ServerGroupHeader(
                groupId: section.id,
                name: section.name,
                count: section.servers.length,
                expanded: expanded,
                onTap: () {
                  _closeTransientRows(collapseDetails: true);
                  setState(() {
                    if (expanded) {
                      _collapsedGroupIds.add(section.id);
                    } else {
                      _collapsedGroupIds.remove(section.id);
                    }
                  });
                },
              ),
            ),
          ),
        );
        if (!expanded) continue;

        if (_orderMode) {
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverReorderableList(
                itemCount: section.servers.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _reorder(section.id, oldIndex, newIndex),
                proxyDecorator: buildAppReorderProxy,
                itemBuilder: (context, index) {
                  final server = section.servers[index];
                  return _ServerCard(
                    key: ValueKey('order-${section.id}-${server.id}'),
                    server: server,
                    state: this,
                    groupName: '',
                    orderMode: true,
                    orderIndex: index,
                  );
                },
              ),
            ),
          );
        } else {
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final server = section.servers[index];
                  return _ServerCard(
                    server: server,
                    state: this,
                    groupName: '',
                  );
                }, childCount: section.servers.length),
              ),
            ),
          );
        }
      }
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 110)));

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }

  String _groupDisplayName(ServerModel server, List<ServerGroupModel> groups) {
    final groupId = _normalizedGroupId(server.group);
    for (final group in groups) {
      if (group.id == groupId) return group.displayName;
    }
    return server.group;
  }

  String _actionText(ServerModel server) {
    final l = AppLocalizations.of(context);
    if (!server.isConfig) return l.tr('servers.notConfigured');
    return l.tr('common.connect');
  }

  String _authTypeLabel(ServerModel server) {
    final l = AppLocalizations.of(context);
    if (server.authType.isEmpty) return l.tr('servers.authFallback');
    if (server.authType == 'password') return l.tr('servers.auth.password');
    return l.tr('servers.auth.privateKey');
  }
}

class _ServerGroupSection {
  const _ServerGroupSection({
    required this.id,
    required this.name,
    required this.servers,
  });

  final String id;
  final String name;
  final List<ServerModel> servers;
}

class _ServerGroupHeader extends StatelessWidget {
  const _ServerGroupHeader({
    required this.groupId,
    required this.name,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String groupId;
  final String name;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('server-group-$groupId'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        key: ValueKey('server-group-toggle-$groupId'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.chip,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveTerminalBanner extends StatelessWidget {
  const _ActiveTerminalBanner({
    required this.count,
    required this.onTap,
    required this.onCloseAll,
  });

  final int count;
  final VoidCallback onTap;
  final VoidCallback onCloseAll;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.banner,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: context.colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 1
                        ? l.tr('servers.activeTerminalsOne')
                        : l.trf('servers.activeTerminalsMany', [count]),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.colors.primary,
                ),
                const SizedBox(width: 4),
                InkResponse(
                  onTap: onCloseAll,
                  radius: 16,
                  child: Tooltip(
                    message: l.tr('servers.closeAllTooltip'),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: context.colors.softMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    super.key,
    required this.server,
    required this.state,
    required this.groupName,
    this.orderMode = false,
    this.orderIndex,
  });

  final ServerModel server;
  final _ServersTabState state;
  final String groupName;
  final bool orderMode;
  final int? orderIndex;

  @override
  Widget build(BuildContext context) {
    final connecting = state._connectingIds.contains(server.id);
    final expanded = state._expandedServerId == server.id;
    final l = AppLocalizations.of(context);
    final proxyLabel = switch (server.proxyType) {
      'proxyServer' => l.tr('servers.proxy.proxyServerShort'),
      'jumpHosts' => l.tr('servers.proxy.jumpHostsShort'),
      _ => '-',
    };
    final expiryLabel = server.expiredAt == null
        ? '-'
        : DateFormat('yyyy-MM-dd').format(server.expiredAt!.toLocal());
    final consoleUrl = server.consoleUrl.trim().isEmpty
        ? '-'
        : server.consoleUrl.trim();
    final loginCommand = server.command.trim().isEmpty
        ? '-'
        : server.command.trim();
    if (orderMode) return _buildOrderCard(context);

    return Container(
      key: Key('server-${server.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? context.colors.strongBorder : context.colors.border,
        ),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: context.colors.primary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSwipeActions(
              key: ValueKey('server-swipe-${server.id}'),
              itemId: server.id,
              controller: state._swipeActionsController,
              actions: [
                AppSwipeAction(
                  key: ValueKey('server-action-details-${server.id}'),
                  icon: expanded
                      ? Icons.expand_less_rounded
                      : Icons.info_outline_rounded,
                  label: expanded
                      ? l.tr('common.collapse')
                      : l.tr('common.details'),
                  onPressed: () => state.toggleServerExpanded(server.id),
                ),
                AppSwipeAction(
                  key: ValueKey('server-action-edit-${server.id}'),
                  icon: Icons.edit_outlined,
                  label: l.tr('common.edit'),
                  tone: AppSwipeActionTone.primary,
                  onPressed: () => state._openForm(server: server),
                ),
                AppSwipeAction(
                  key: ValueKey('server-action-delete-${server.id}'),
                  icon: Icons.delete_outline,
                  label: l.tr('common.delete'),
                  tone: AppSwipeActionTone.danger,
                  onPressed: () => state._confirmDelete(server),
                ),
              ],
              child: SizedBox(
                height: _kServerCardHeight - 2,
                child: Semantics(
                  button: true,
                  enabled: !connecting,
                  label: state._actionText(server),
                  child: InkWell(
                    onTap: connecting
                        ? null
                        : () => state._handleServerTap(server),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
                      child: Row(
                        children: [
                          _ServerOsIcon(
                            enabled: server.canConnect,
                            isWindows: server.isWindows,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    server.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.colors.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          server.connectionLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: context.colors.softMuted,
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                      if (groupName.isNotEmpty) ...[
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          child: Container(
                                            width: 3,
                                            height: 3,
                                            decoration: BoxDecoration(
                                              color: context.colors.softMuted,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 92,
                                          ),
                                          child: Text(
                                            groupName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: context.colors.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (connecting) ...[
                            const SizedBox(width: 10),
                            SizedBox(
                              key: const ValueKey('connecting'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.colors.text,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Container(
                      key: ValueKey('server-details-${server.id}'),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: context.colors.border),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        children: [
                          _CopyableHostRow(
                            host: server.host,
                            onCopy: () => state._copyHost(server),
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final tileWidth = (constraints.maxWidth - 8) / 2;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: tileWidth,
                                    child: _ServerDetailTile(
                                      label: l.tr('servers.field.authType'),
                                      value: state._authTypeLabel(server),
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _ServerDetailTile(
                                      label: l.tr('servers.field.tags'),
                                      value: server.tag.isEmpty
                                          ? '-'
                                          : server.tag.join(', '),
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _ServerDetailTile(
                                      label: l.tr('servers.field.proxyType'),
                                      value: proxyLabel,
                                      emphasized:
                                          server.proxyType != 'none' &&
                                          server.proxyType.isNotEmpty,
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _ServerDetailTile(
                                      label: l.tr('servers.field.expired'),
                                      value: expiryLabel,
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _ServerDetailTile(
                                      label: l.tr('servers.field.consoleUrl'),
                                      value: consoleUrl,
                                    ),
                                  ),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _ServerDetailTile(
                                      label: l.tr('servers.field.command'),
                                      value: loginCommand,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('server-details-collapsed'),
                      width: double.infinity,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context) {
    return Container(
      key: Key('server-${server.id}'),
      height: _kServerCardHeight,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          _ServerOsIcon(
            enabled: server.canConnect,
            isWindows: server.isWindows,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  server.connectionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.softMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (groupName.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 78),
              child: _InfoChip(label: groupName),
            ),
          ],
          const SizedBox(width: 6),
          ReorderableDragStartListener(
            index: orderIndex!,
            child: Container(
              width: 40,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.canvas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.drag_handle,
                color: context.colors.muted,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 22,
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: context.colors.muted, size: 22),
        ),
      ),
    );
  }
}

class _ServerOsIcon extends StatelessWidget {
  const _ServerOsIcon({required this.enabled, required this.isWindows});

  final bool enabled;
  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final asset = isWindows ? 'assets/windows.svg' : 'assets/linux.svg';
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? context.colors.banner : context.colors.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: SvgPicture.asset(
          asset,
          width: 22,
          height: 22,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.banner,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CopyableHostRow extends StatelessWidget {
  const _CopyableHostRow({required this.host, required this.onCopy});

  final String host;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: l.tr('servers.copyHost'),
      child: Material(
        color: context.colors.banner,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onCopy,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 16,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      host.isEmpty ? '-' : host,
                      key: const ValueKey('server-copy-host-value'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.text,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.copy_outlined,
                    size: 17,
                    color: context.colors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerDetailTile extends StatelessWidget {
  const _ServerDetailTile({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.colors.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.softMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: emphasized ? context.colors.primary : context.colors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.muted),
        ),
      ),
    );
  }
}

InputDecoration _searchFieldDecoration(
  BuildContext context, {
  required String hintText,
}) {
  return InputDecoration(
    hintText: hintText,
    isDense: true,
    filled: true,
    fillColor: context.colors.card,
    prefixIcon: const Icon(Icons.search, size: 18),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    hintStyle: TextStyle(color: context.colors.softMuted, fontSize: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.colors.primary, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.colors.border),
    ),
  );
}
