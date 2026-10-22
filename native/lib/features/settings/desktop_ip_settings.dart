import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../state/api_access_notifier.dart';
import '../../state/api_providers.dart';
import 'models/ip_access_rule.dart';

class DesktopIpSettings extends ConsumerStatefulWidget {
  const DesktopIpSettings({super.key});
  @override
  ConsumerState<DesktopIpSettings> createState() => _DesktopIpSettingsState();
}

class _DesktopIpSettingsState extends ConsumerState<DesktopIpSettings> {
  final _input = TextEditingController();
  IpAccessConfig? _config;
  List<String> _rules = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref.read(settingsRepositoryProvider).getIpAccessRules();
      if (mounted) {
        setState(() {
          _config = c;
          _rules = [...c.ipWhiteList];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _add() {
    final rule = classifyIpAccessRule(_input.text);
    if (rule.kind != IpAccessRuleKind.exact &&
        rule.kind != IpAccessRuleKind.cidr) {
      setState(
        () => _error = mx(
          context,
          '只能新增精确 IP 或 CIDR 网段。',
          'Enter an exact IP or CIDR range.',
        ),
      );
      return;
    }
    setState(() {
      _rules = normalizeIpAccessRules([..._rules, rule.value]);
      _input.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_rules.isEmpty &&
            !await managementConfirm(
              context,
              mx(
                context,
                '移除所有规则后，所有来源 IP 都能访问。继续保存？',
                'Removing all rules allows access from any IP. Continue?',
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
      await _persist();
    } on ApiFailure catch (e) {
      if (e.statusCode == 409 &&
          e.data is Map &&
          (e.data as Map)['code'] == 'CURRENT_IP_NOT_ALLOWED' &&
          mounted) {
        final ip =
            '${(e.data as Map)['currentIp'] ?? _config?.currentIp ?? ''}';
        final action = await showAppDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => DesktopManagementDialog(
            width: 500,
            title: mx(context, '当前 IP 将被阻止', 'Current IP will be blocked'),
            body: Text(
              mx(
                context,
                '规则不包含当前 IP $ip。你可以返回修改、加入当前 IP，或强制保存。',
                'The rules exclude your current IP $ip. Go back, add this IP, or force save.',
              ),
            ),
            actions: [
              ManagementButton(
                label: mx(context, '返回修改', 'Go back'),
                onPressed: () => Navigator.pop(context),
              ),
              ManagementButton(
                label: mx(context, '强制保存', 'Force save'),
                onPressed: () => Navigator.pop(context, 'force'),
              ),
              ManagementButton(
                label: mx(context, '加入当前 IP 并保存', 'Add current IP and save'),
                primary: true,
                onPressed: () => Navigator.pop(context, 'add'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        try {
          if (action == 'add') {
            setState(() => _rules = normalizeIpAccessRules([..._rules, ip]));
            await _persist();
          } else if (action == 'force') {
            await _persist(force: true);
          }
        } catch (error) {
          if (mounted) setState(() => _error = managementError(error));
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persist({bool force = false}) async {
    final c = await ref
        .read(settingsRepositoryProvider)
        .saveIpAccessRules(_rules, allowCurrentIpMismatch: force);
    if (!mounted) return;
    setState(() {
      _config = c;
      _rules = [...c.ipWhiteList];
    });
    if (!c.currentIpAllowed) {
      ref.read(apiAccessProvider.notifier).markIpAccessDenied();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _config != null && !listEquals(_rules, _config!.ipWhiteList);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          ManagementError(
            message: _error!,
            onRetry: _config == null ? _load : null,
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                mx(context, '允许访问的 IP 规则', 'Allowed IP rules'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ManagementTag(
              _rules.isEmpty
                  ? mx(context, '未限制', 'Unrestricted')
                  : mx(
                      context,
                      '限制中 · ${_rules.length} 条规则',
                      'Restricted · ${_rules.length} rules',
                    ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_config?.currentIp.isNotEmpty == true)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectableText(
                '${mx(context, '当前来源 IP', 'Current source IP')}: ${_config!.currentIp}',
                style: const TextStyle(fontSize: 13),
              ),
              ManagementLink(
                label: mx(context, '加入当前 IP', 'Add current IP'),
                onPressed: _busy || _rules.contains(_config!.currentIp)
                    ? null
                    : () => setState(
                        () => _rules = normalizeIpAccessRules([
                          ..._rules,
                          _config!.currentIp,
                        ]),
                      ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (_rules.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              mx(
                context,
                '尚未设置规则，当前允许所有来源 IP 访问。',
                'No rules configured. All source IPs are allowed.',
              ),
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
          ),
        for (final rule in _rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DesktopFormTag(
                  label: rule,
                  onRemove: _busy
                      ? null
                      : () => setState(() => _rules.remove(rule)),
                ),
                if (classifyIpAccessRule(rule).kind == IpAccessRuleKind.legacy)
                  Text(
                    mx(
                      context,
                      '旧版模糊规则，建议替换为 ${suggestCidrForLegacyRule(rule)}',
                      'Legacy fuzzy rule; suggested CIDR: ${suggestCidrForLegacyRule(rule)}',
                    ),
                    style: TextStyle(
                      color: context.colors.warning,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_busy && _config != null,
                onSubmitted: (_) => _add(),
                style: const TextStyle(fontSize: 13),
                decoration: desktopInputDecoration(
                  context,
                  hint: '192.168.1.0/24',
                ),
              ),
            ),
            const SizedBox(width: 12),
            ManagementButton(
              label: mx(context, '添加', 'Add'),
              primary: true,
              onPressed: _busy || _config == null ? null : _add,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            mx(
              context,
              '支持 IPv4、IPv6 与 CIDR 网段；旧版模糊规则可保留，但不能新增。',
              'Supports IPv4, IPv6 and CIDR. Existing legacy fuzzy rules can be kept, but new ones cannot be added.',
            ),
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ManagementButton(
              label: mx(context, '撤销修改', 'Undo changes'),
              onPressed: !dirty || _busy
                  ? null
                  : () => setState(() {
                      _rules = [..._config!.ipWhiteList];
                      _error = null;
                      _input.clear();
                    }),
            ),
            ManagementButton(
              label: mx(context, '保存设置', 'Save settings'),
              primary: true,
              onPressed: !dirty || _busy ? null : _save,
            ),
            if (dirty)
              Text(
                mx(context, '有未保存的修改', 'Unsaved changes'),
                style: TextStyle(color: context.colors.warning, fontSize: 12),
              ),
          ],
        ),
      ],
    );
  }
}
