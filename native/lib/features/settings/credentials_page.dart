import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/credential_list_notifier.dart';
import '../servers/server_credential_model.dart';
import 'credential_edit_page.dart';

class CredentialsPage extends ConsumerStatefulWidget {
  const CredentialsPage({super.key});

  @override
  ConsumerState<CredentialsPage> createState() => _CredentialsPageState();
}

class _CredentialsPageState extends ConsumerState<CredentialsPage> {
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

  Future<void> _openEdit({ServerCredentialModel? credential}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CredentialEditPage(credential: credential)),
    );
  }

  Future<void> _delete(ServerCredentialModel c) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('credentials.deleteConfirmTitle')),
        content: Text(l.trf('credentials.deleteConfirmBody', [c.displayName])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.danger,
              foregroundColor: ctx.colors.fontOnPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = c.id);
    try {
      await ref.read(settingsRepositoryProvider).deleteCredential(c.id);
      if (!mounted) return;
      _showSnack(l.tr('credentials.deleted'));
      await ref.read(credentialListProvider.notifier).refresh();
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('credentials.deleteFailed', [err.message]));
    } catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('credentials.deleteFailed', [err.toString()]));
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  List<ServerCredentialModel> _filter(List<ServerCredentialModel> list) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((e) {
      return e.name.toLowerCase().contains(q) ||
          e.authType.toLowerCase().contains(q);
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
    final async = ref.watch(credentialListProvider);

    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        backgroundColor: context.colors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l.tr('settings.credentials.title')),
        actions: [
          IconButton(
            tooltip: _searchOpen
                ? l.tr('common.closeSearch')
                : l.tr('common.search'),
            onPressed: _toggleSearch,
            icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
            color: context.colors.primary,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _AddButton(onTap: () => _openEdit()),
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
                            fillColor: context.colors.card,
                            hintText: l.tr('credentials.searchHint'),
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: context.colors.softMuted,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: context.colors.softMuted,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: context.colors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: context.colors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: context.colors.accent),
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
                    .read(credentialListProvider.notifier)
                    .refresh(throwOnError: true),
              ),
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => _ErrorBody(
                  message: l.trf('credentials.saveFailed', [err.toString()]),
                  onRetry: () =>
                      ref.read(credentialListProvider.notifier).refresh(),
                ),
                data: (list) {
                  final visible = _filter(list);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      _SectionHeader(
                        label: l.tr('settings.credentials.title'),
                        count: list.length,
                      ),
                      const SizedBox(height: 8),
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              list.isEmpty
                                  ? l.tr('credentials.empty')
                                  : l.tr('credentials.emptyFiltered'),
                              style: TextStyle(
                                color: context.colors.softMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        for (final cred in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _CredentialCard(
                              credential: cred,
                              dateLabel: _formatDate(cred.date),
                              deleting: _deletingId == cred.id,
                              onTap: () => _openEdit(credential: cred),
                              onEdit: () => _openEdit(credential: cred),
                              onDelete: () => _delete(cred),
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
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: context.colors.muted,
          ),
        ),
        Text(
          '· $count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.colors.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.add_rounded,
            size: 20,
            color: context.colors.fontOnPrimary,
          ),
        ),
      ),
    );
  }
}

class _CredentialCard extends StatelessWidget {
  const _CredentialCard({
    required this.credential,
    required this.dateLabel,
    required this.deleting,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ServerCredentialModel credential;
  final String dateLabel;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isKey = credential.isPrivateKey;
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: context.colors.chip,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isKey ? Icons.vpn_key_outlined : Icons.lock_outline,
                      size: 16,
                      color: context.colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      credential.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        color: context.colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _AuthTypeChip(
                    label: isKey
                        ? l.tr('servers.auth.privateKey')
                        : l.tr('servers.auth.password'),
                    isKey: isKey,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: dateLabel.isEmpty
                        ? const SizedBox.shrink()
                        : Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.colors.softMuted,
                            ),
                          ),
                  ),
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    bg: context.colors.accentSoft,
                    fg: context.colors.primary,
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 6),
                  _ActionButton(
                    icon: Icons.delete_outline,
                    bg: context.colors.dangerSoft,
                    fg: context.colors.danger,
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

class _AuthTypeChip extends StatelessWidget {
  const _AuthTypeChip({required this.label, required this.isKey});

  final String label;
  final bool isKey;

  @override
  Widget build(BuildContext context) {
    final bg = isKey
        ? context.colors.success.withValues(alpha: 0.16)
        : context.colors.accentSoft;
    final fg = isKey ? context.colors.success : context.colors.primary;
    final icon = isKey ? Icons.vpn_key : Icons.lock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.4,
            ),
          ),
        ],
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
                Icon(
                  Icons.error_outline,
                  size: 36,
                  color: context.colors.danger,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.colors.text),
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
