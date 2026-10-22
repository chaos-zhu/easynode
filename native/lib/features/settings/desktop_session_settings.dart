import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_management.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import 'models/login_session.dart';

class DesktopSessionSettings extends ConsumerStatefulWidget {
  const DesktopSessionSettings({super.key});
  @override
  ConsumerState<DesktopSessionSettings> createState() =>
      _DesktopSessionSettingsState();
}

class _DesktopSessionSettingsState
    extends ConsumerState<DesktopSessionSettings> {
  List<LoginSession> _sessions = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final log = await ref.read(settingsRepositoryProvider).getLoginLog();
      if (mounted) setState(() => _sessions = log.sessions);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke([LoginSession? session]) async {
    if (!await managementConfirm(
          context,
          session == null
              ? mx(
                  context,
                  '注销所有会话？所有设备（包括当前设备）都将立即退出登录。',
                  'Revoke all sessions? All devices, including this one, will be signed out.',
                )
              : mx(
                  context,
                  '确定注销该设备登录凭证？',
                  'Revoke this device’s login session?',
                ),
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final current = ref.read(authProvider).session?.deviceId;
      final repo = ref.read(settingsRepositoryProvider);
      if (session == null) {
        await repo.revokeAllSessions();
      } else {
        await repo.revokeSession(session.id);
      }
      if (session == null || session.deviceId == current) {
        await ref.read(authProvider.notifier).signOutSafely();
      } else if (mounted) {
        await _load();
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(authProvider).session?.deviceId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          mx(
            context,
            '登录记录默认保留 90 天，超过 90 天的记录将自动清理。',
            'Login records are kept for 90 days and then removed automatically.',
          ),
          style: TextStyle(color: context.colors.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            ManagementLink(
              label: mx(context, '刷新', 'Refresh'),
              onPressed: _busy ? null : _load,
            ),
            ManagementButton(
              label: mx(context, '注销所有会话', 'Revoke all sessions'),
              onPressed: _busy ? null : () => _revoke(),
            ),
          ],
        ),
        if (_error != null) ManagementError(message: _error!, onRetry: _load),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        SizedBox(
          height: 500,
          child: ManagementTable(
            columns: [
              const ManagementColumn('IP', width: 140),
              ManagementColumn(mx(context, '地点', 'Location'), width: 130),
              ManagementColumn(mx(context, '设备信息', 'Device'), width: 200),
              ManagementColumn(mx(context, '登录时间', 'Login time'), width: 170),
              ManagementColumn(mx(context, '过期时间', 'Expires'), width: 170),
              ManagementColumn(mx(context, '状态', 'Status'), width: 100),
              ManagementColumn.actions(mx(context, '操作', 'Actions'), width: 90),
            ],
            rows: [
              for (final s in _sessions)
                [
                  Text(s.ip),
                  Text(s.location),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.os),
                      Text(s.browser),
                      if (s.deviceId == current)
                        ManagementTag(
                          mx(context, '当前设备', 'Current device'),
                          color: context.colors.success,
                        ),
                    ],
                  ),
                  Text(
                    managementDate(
                      DateTime.fromMillisecondsSinceEpoch(s.createAt),
                    ),
                  ),
                  Text(
                    managementDate(
                      DateTime.fromMillisecondsSinceEpoch(s.expireAt),
                    ),
                  ),
                  ManagementTag(
                    DateTime.now().millisecondsSinceEpoch > s.expireAt
                        ? mx(context, '已过期', 'Expired')
                        : s.revoked
                        ? mx(context, '已注销', 'Revoked')
                        : mx(context, '正常', 'Active'),
                    color: s.revoked
                        ? context.colors.warning
                        : context.colors.success,
                  ),
                  s.revoked ||
                          s.expireAt <= DateTime.now().millisecondsSinceEpoch
                      ? const Text('—')
                      : ManagementLink(
                          label: mx(context, '注销', 'Revoke'),
                          danger: true,
                          onPressed: _busy ? null : () => _revoke(s),
                        ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
