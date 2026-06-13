import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import '../../state/login_log_notifier.dart';
import 'models/login_session.dart';

class SessionsPage extends ConsumerStatefulWidget {
  const SessionsPage({super.key});

  @override
  ConsumerState<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends ConsumerState<SessionsPage> {
  final _addController = TextEditingController();
  late List<String> _whitelist;
  bool _whitelistDirty = false;
  bool _whitelistSaving = false;
  bool _purging = false;
  String? _revokingId;

  @override
  void initState() {
    super.initState();
    _whitelist = const [];
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _syncWhitelistFrom(LoginLogData data) {
    if (_whitelistDirty) return;
    final next = data.ipWhiteList.where((e) => e.isNotEmpty).toList();
    if (next.length == _whitelist.length &&
        next.every((e) => _whitelist.contains(e))) {
      return;
    }
    _whitelist = next;
  }

  void _addIp() {
    final raw = _addController.text.trim();
    if (raw.isEmpty) return;
    if (!RegExp(r'[\d\.]').hasMatch(raw)) return;
    if (_whitelist.contains(raw)) {
      _addController.clear();
      return;
    }
    setState(() {
      _whitelist = [..._whitelist, raw];
      _whitelistDirty = true;
      _addController.clear();
    });
  }

  void _removeIp(String ip) {
    setState(() {
      _whitelist = _whitelist.where((e) => e != ip).toList();
      _whitelistDirty = true;
    });
  }

  Future<void> _saveWhitelist() async {
    final l = AppLocalizations.of(context);
    setState(() => _whitelistSaving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveIpWhiteList(List.of(_whitelist));
      if (!mounted) return;
      _whitelistDirty = false;
      _showSnack(l.tr('sessions.ipSaved'));
      await ref.read(loginLogProvider.notifier).refresh();
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(err.message);
    } catch (err) {
      if (!mounted) return;
      _showSnack(err.toString());
    } finally {
      if (mounted) setState(() => _whitelistSaving = false);
    }
  }

  Future<void> _purgeOld() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('sessions.purgeConfirmTitle')),
        content: Text(l.tr('sessions.purgeConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.tr('common.continue')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _purging = true);
    try {
      await ref.read(settingsRepositoryProvider).purgeOldSessions();
      if (!mounted) return;
      _showSnack(l.tr('sessions.purgeDone'));
      await ref.read(loginLogProvider.notifier).refresh();
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(err.message);
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  Future<void> _revoke(LoginSession session) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('sessions.revokeConfirmTitle')),
        content: Text(l.tr('sessions.revokeConfirmBody')),
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
            child: Text(l.tr('sessions.revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revokingId = session.id);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .revokeSession(session.id);
      if (!mounted) return;
      _showSnack(l.tr('sessions.revokeDone'));
      await ref.read(loginLogProvider.notifier).refresh();
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(err.message);
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatTimestamp(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final logAsync = ref.watch(loginLogProvider);

    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        backgroundColor: context.colors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l.tr('settings.sessions.title')),
        actions: [
          IconButton(
            tooltip: l.tr('sessions.purgeTooltip'),
            onPressed: _purging || logAsync.isLoading ? null : _purgeOld,
            icon: _purging
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.danger,
                    ),
                  )
                : Icon(
                    Icons.delete_outline,
                    color: context.colors.danger,
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => runRefreshWithFeedback(
          context,
          () =>
              ref.read(loginLogProvider.notifier).refresh(throwOnError: true),
        ),
        child: logAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorBody(
            message: l.trf('sessions.loadFailed', [err.toString()]),
            onRetry: () => ref.read(loginLogProvider.notifier).refresh(),
          ),
          data: (data) {
            _syncWhitelistFrom(data);
            return _buildBody(data);
          },
        ),
      ),
    );
  }

  Widget _buildBody(LoginLogData data) {
    final l = AppLocalizations.of(context);
    final currentDeviceId =
        ref.watch(authProvider).session?.deviceId ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _IpWhitelistCard(
          whitelist: _whitelist,
          controller: _addController,
          saving: _whitelistSaving,
          dirty: _whitelistDirty,
          onAdd: _addIp,
          onRemove: _removeIp,
          onSave: _whitelistDirty && !_whitelistSaving
              ? _saveWhitelist
              : null,
        ),
        const SizedBox(height: 18),
        _SectionHeader(
          label: l.tr('sessions.loginRecordsTitle'),
          count: data.sessions.length,
        ),
        if (data.sessions.isEmpty)
          _EmptyState(label: l.tr('sessions.empty'))
        else
          for (final session in data.sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SessionCard(
                session: session,
                isCurrent: session.deviceId.isNotEmpty &&
                    session.deviceId == currentDeviceId,
                createLabel: _formatTimestamp(session.createAt),
                expireLabel: _formatTimestamp(session.expireAt),
                revoking: _revokingId == session.id,
                onRevoke: session.revoked
                    ? null
                    : () => _revoke(session),
              ),
            ),
      ],
    );
  }
}

class _IpWhitelistCard extends StatelessWidget {
  const _IpWhitelistCard({
    required this.whitelist,
    required this.controller,
    required this.saving,
    required this.dirty,
    required this.onAdd,
    required this.onRemove,
    required this.onSave,
  });

  final List<String> whitelist;
  final TextEditingController controller;
  final bool saving;
  final bool dirty;
  final VoidCallback onAdd;
  final void Function(String ip) onRemove;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.tr('sessions.ipWhitelistTitle'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.info_outline,
                size: 12,
                color: context.colors.softMuted,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.tr('sessions.ipWhitelistHint'),
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 10),
          if (whitelist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l.tr('sessions.ipEmpty'),
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.softMuted,
                ),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final ip in whitelist)
                  _IpChip(label: ip, onRemove: () => onRemove(ip)),
              ],
            ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onSubmitted: (_) => onAdd(),
            textInputAction: TextInputAction.done,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: context.colors.text,
            ),
            decoration: InputDecoration(
              hintText: l.tr('sessions.ipAddHint'),
              hintStyle: TextStyle(
                fontSize: 12,
                color: context.colors.softMuted,
              ),
              isDense: true,
              filled: true,
              fillColor: context.colors.canvas,
              prefixIcon: Icon(
                Icons.add_rounded,
                size: 18,
                color: context.colors.softMuted,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.colors.accent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: context.colors.fontOnPrimary,
                disabledBackgroundColor: context.colors.chip,
                disabledForegroundColor: context.colors.softMuted,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: saving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.fontOnPrimary,
                      ),
                    )
                  : const Icon(Icons.verified_user_outlined, size: 16),
              label: Text(
                l.tr('sessions.ipSave'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IpChip extends StatelessWidget {
  const _IpChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.strongBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.primary,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: context.colors.primary,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Row(
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
          const SizedBox(width: 6),
          Text(
            '· $count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.isCurrent,
    required this.createLabel,
    required this.expireLabel,
    required this.revoking,
    required this.onRevoke,
  });

  final LoginSession session;
  final bool isCurrent;
  final String createLabel;
  final String expireLabel;
  final bool revoking;
  final VoidCallback? onRevoke;

  bool get _expired {
    if (session.expireAt <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch > session.expireAt;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final nativeClient = session.isNativeClient;
    final bg = isCurrent ? context.colors.accentSoft : context.colors.card;
    final borderColor = isCurrent ? context.colors.primary : context.colors.border;
    final borderWidth = isCurrent ? 2.0 : 1.0;

    final ipLabel =
        session.ip.isEmpty ? '-' : session.ip;
    final location = session.location;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                nativeClient
                    ? Icons.smartphone_rounded
                    : Icons.monitor_rounded,
                size: 18,
                color: context.colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ipLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.colors.text,
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        location,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _StatusBadge(
                label: _statusLabel(l),
                tone: _statusTone(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: context.colors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                nativeClient
                    ? Icons.smartphone_outlined
                    : Icons.monitor_outlined,
                size: 14,
                color: context.colors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _agentLabel(l),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetaLine(
                      label: l.tr('sessions.createTime'),
                      value: createLabel,
                    ),
                    const SizedBox(height: 3),
                    _MetaLine(
                      label: l.tr('sessions.expireAt'),
                      value: expireLabel,
                    ),
                  ],
                ),
              ),
              if (onRevoke != null && !_expired)
                _RevokeButton(
                  label: l.tr('sessions.revoke'),
                  loading: revoking,
                  onTap: onRevoke!,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(AppLocalizations l) {
    if (isCurrent) return l.tr('sessions.current');
    if (session.revoked) return l.tr('sessions.revoked');
    if (_expired) return l.tr('terminal.status.disconnected');
    return l.tr('sessions.native');
  }

  _StatusTone _statusTone() {
    if (isCurrent) return _StatusTone.success;
    if (session.revoked) return _StatusTone.muted;
    if (_expired) return _StatusTone.muted;
    return _StatusTone.primary;
  }

  String _agentLabel(AppLocalizations l) {
    final raw = session.agentLabel;
    if (raw.isEmpty) return '-';
    return raw;
  }
}

enum _StatusTone { primary, success, muted }

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.tone});

  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _StatusTone.success => (context.colors.success, context.colors.fontOnPrimary),
      _StatusTone.primary => (context.colors.accentSoft, context.colors.primary),
      _StatusTone.muted => (context.colors.chip, context.colors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$label  ',
          style: TextStyle(
            fontSize: 11,
            color: context.colors.softMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RevokeButton extends StatelessWidget {
  const _RevokeButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.colors.warning),
          ),
          child: loading
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.warning,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.warning,
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: context.colors.softMuted),
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
