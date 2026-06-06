import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/palette.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/proxy_list_notifier.dart';
import '../servers/server_proxy_model.dart';
import 'proxy_edit_page.dart';

class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key});

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  String _query = '';
  bool _searchOpen = false;
  late final TextEditingController _searchCtrl;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  Future<void> _openEdit({ServerProxyModel? proxy, required bool plus}) async {
    if (!plus) {
      _showPlusGate();
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProxyEditPage(proxy: proxy)),
    );
  }

  Future<void> _delete(ServerProxyModel p) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('proxy.deleteConfirmTitle')),
        content: Text(l.trf('proxy.deleteConfirmBody', [p.displayName])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.danger,
              foregroundColor: AppPalette.fontOnPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = p.id);
    try {
      await ref.read(settingsRepositoryProvider).deleteProxy(p.id);
      if (!mounted) return;
      _showSnack(l.tr('proxy.deleted'));
      await ref.read(proxyListProvider.notifier).refresh();
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.deleteFailed', [err.message]));
    } catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.deleteFailed', [err.toString()]));
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _clone(ServerProxyModel p) async {
    final l = AppLocalizations.of(context);
    final clone = ServerProxyModel(
      id: '',
      name: '${p.name}_copy',
      type: p.type,
      host: p.host,
      port: p.port,
      username: p.username,
      password: p.password,
    );
    try {
      await ref.read(settingsRepositoryProvider).createProxy(clone);
      if (!mounted) return;
      _showSnack(l.tr('proxy.saved'));
      await ref.read(proxyListProvider.notifier).refresh();
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.saveFailed', [err.message]));
    } catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.saveFailed', [err.toString()]));
    }
  }

  void _showPlusGate() {
    final l = AppLocalizations.of(context);
    _showSnack(l.tr('proxy.plusTipBody'));
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  List<ServerProxyModel> _filter(List<ServerProxyModel> list) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((e) {
      return e.name.toLowerCase().contains(q) ||
          e.host.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q) ||
          e.type.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  String _formatDate(int? ms) {
    if (ms == null || ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(proxyListProvider);
    final plusActive = ref.watch(plusInfoProvider).valueOrNull?.isActive ?? false;

    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: AppBar(
        backgroundColor: AppPalette.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l.tr('settings.proxy.title')),
        actions: [
          IconButton(
            tooltip: _searchOpen
                ? l.tr('common.closeSearch')
                : l.tr('common.search'),
            onPressed: _toggleSearch,
            icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
            color: AppPalette.primary,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _AddButton(
              onTap: () => _openEdit(plus: plusActive),
              enabled: plusActive,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _searchOpen
                    ? Padding(
                        key: const ValueKey('search'),
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: AppPalette.card,
                            hintText: l.tr('credentials.searchHint'),
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: AppPalette.softMuted,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: AppPalette.softMuted,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppPalette.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppPalette.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppPalette.accent),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('search-empty'),
                        width: double.infinity,
                      ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => runRefreshWithFeedback(
                context,
                () => ref
                    .read(proxyListProvider.notifier)
                    .refresh(throwOnError: true),
              ),
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => _ErrorBody(
                  message: l.trf('proxy.saveFailed', [err.toString()]),
                  onRetry: () => ref.read(proxyListProvider.notifier).refresh(),
                ),
                data: (list) {
                  final visible = _filter(list);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      if (!plusActive) const _PlusTip(),
                      if (!plusActive) const SizedBox(height: 12),
                      _SectionHeader(
                        label: l.tr('settings.proxy.title'),
                        count: list.length,
                      ),
                      const SizedBox(height: 8),
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              l.tr('proxy.empty'),
                              style: const TextStyle(
                                color: AppPalette.softMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        for (final proxy in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ProxyCard(
                              proxy: proxy,
                              dateLabel: _formatDate(
                                proxy.updateTime ?? proxy.createTime,
                              ),
                              deleting: _deletingId == proxy.id,
                              onTap: () =>
                                  _openEdit(proxy: proxy, plus: plusActive),
                              onEdit: () =>
                                  _openEdit(proxy: proxy, plus: plusActive),
                              onClone: () => _clone(proxy),
                              onDelete: () => _delete(proxy),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlusTip extends StatelessWidget {
  const _PlusTip();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.accent),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            size: 16,
            color: AppPalette.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('proxy.plusTipTitle'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.tr('proxy.plusTipBody'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppPalette.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: AppPalette.muted,
          ),
        ),
        Text(
          '· $count',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppPalette.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, required this.enabled});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? AppPalette.primary : AppPalette.chip;
    final fg = enabled ? AppPalette.fontOnPrimary : AppPalette.softMuted;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.add_rounded, size: 20, color: fg),
        ),
      ),
    );
  }
}

class _ProxyCard extends StatelessWidget {
  const _ProxyCard({
    required this.proxy,
    required this.dateLabel,
    required this.deleting,
    required this.onTap,
    required this.onEdit,
    required this.onClone,
    required this.onDelete,
  });

  final ServerProxyModel proxy;
  final String dateLabel;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onClone;
  final VoidCallback onDelete;

  bool get _isSocks => proxy.type.toLowerCase() == 'socks5';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _TypeChip(label: proxy.typeLabel, primary: !_isSocks),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            proxy.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (dateLabel.isNotEmpty)
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppPalette.softMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.chip,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lan_outlined,
                      size: 14,
                      color: AppPalette.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        proxy.endpoint.isEmpty ? '-' : proxy.endpoint,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: AppPalette.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (proxy.username.isNotEmpty) ...[
                          const Icon(
                            Icons.person_outline,
                            size: 13,
                            color: AppPalette.softMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              proxy.username,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppPalette.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    bg: AppPalette.accentSoft,
                    fg: AppPalette.primary,
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 6),
                  _ActionButton(
                    icon: Icons.copy_all_outlined,
                    bg: AppPalette.success.withValues(alpha: 0.16),
                    fg: AppPalette.success,
                    onTap: onClone,
                  ),
                  const SizedBox(width: 6),
                  _ActionButton(
                    icon: Icons.delete_outline,
                    bg: AppPalette.dangerSoft,
                    fg: AppPalette.danger,
                    loading: deleting,
                    onTap: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.primary});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppPalette.accentSoft : const Color(0xFFCFFAFE);
    final fg = primary ? AppPalette.primary : const Color(0xFF0E7490);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: loading ? null : onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                : Icon(icon, size: 14, color: fg),
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 36,
                  color: AppPalette.danger,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppPalette.text),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => onRetry(),
                  child: Text(l.tr('common.retry')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
