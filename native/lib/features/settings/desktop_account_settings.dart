import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_management.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import 'desktop_settings_widgets.dart';
import 'settings_repository.dart';

class DesktopAccountSettings extends ConsumerStatefulWidget {
  const DesktopAccountSettings({super.key});
  @override
  ConsumerState<DesktopAccountSettings> createState() =>
      _DesktopAccountSettingsState();
}

class _DesktopAccountSettingsState
    extends ConsumerState<DesktopAccountSettings> {
  final _form = GlobalKey<FormState>();
  final _oldName = TextEditingController(),
      _oldPassword = TextEditingController(),
      _newName = TextEditingController(),
      _newPassword = TextEditingController(),
      _code = TextEditingController();
  bool _busy = false, _loading = true, _mfa = false, _disabling = false;
  Mfa2Setup? _setup;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_oldName, _oldPassword, _newName, _newPassword, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enabled = await ref
          .read(settingsRepositoryProvider)
          .getMfa2Status();
      if (mounted) setState(() => _mfa = enabled);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() ||
        !await managementConfirm(
          context,
          mx(
            context,
            '修改用户名或密码后会清除所有登录态，需重新登录。',
            'Changing the username or password signs out all devices. Continue?',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _action(() async {
      await ref
          .read(settingsRepositoryProvider)
          .updateAccount(
            oldLoginName: _oldName.text.trim(),
            oldPwd: _oldPassword.text,
            newLoginName: _newName.text.trim(),
            newPwd: _newPassword.text,
          );
      await ref.read(authProvider.notifier).signOutSafely();
    });
  }

  Future<void> _mfaSubmit() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(
        () => _error = mx(
          context,
          '请输入 6 位数字验证码',
          'Enter a six-digit verification code',
        ),
      );
      return;
    }
    await _action(() async {
      final repo = ref.read(settingsRepositoryProvider);
      if (_disabling) {
        await repo.disableMfa2(_code.text);
      } else {
        await repo.enableMfa2(_code.text);
      }
      if (!mounted) return;
      setState(() {
        _mfa = !_disabling;
        _setup = null;
        _disabling = false;
        _code.clear();
      });
      managementNotice(
        context,
        mx(context, '两步验证设置已更新', 'Two-step verification updated'),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null) ManagementError(message: _error!, onRetry: _load),
      Form(
        key: _form,
        child: Column(
          children: [
            for (final item in [
              (mx(context, '原用户名', 'Current username'), _oldName, false),
              (mx(context, '原密码', 'Current password'), _oldPassword, true),
              (mx(context, '新用户名', 'New username'), _newName, false),
              (mx(context, '新密码', 'New password'), _newPassword, true),
            ])
              DesktopSettingRow(
                label: item.$1,
                child: DesktopSettingInput(
                  controller: item.$2,
                  secret: item.$3,
                  enabled: !_busy,
                  validator: (v) =>
                      v!.isEmpty ? mx(context, '此项必填', 'Required') : null,
                  onSubmitted: item.$2 == _newPassword ? (_) => _save() : null,
                ),
              ),
            DesktopSettingRow(
              label: '',
              child: ManagementButton(
                label: mx(context, '确认', 'Confirm'),
                primary: true,
                onPressed: _busy ? null : _save,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Text(
        mx(context, '两步验证（MFA2）', 'Two-step verification (MFA2)'),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 18),
      if (_loading)
        const LinearProgressIndicator(minHeight: 2)
      else if (_setup == null && !_disabling)
        Row(
          children: [
            if (_mfa) ...[
              Text(
                mx(context, '已启用', 'Enabled'),
                style: TextStyle(color: context.colors.success),
              ),
              const SizedBox(width: 16),
            ],
            ManagementButton(
              label: _mfa
                  ? mx(context, '禁用', 'Disable')
                  : mx(context, '启用', 'Enable'),
              primary: !_mfa,
              onPressed: _busy
                  ? null
                  : () async {
                      if (_mfa) {
                        setState(() => _disabling = true);
                      } else {
                        await _action(() async {
                          final setup = await ref
                              .read(settingsRepositoryProvider)
                              .getMfa2QrInfo();
                          if (mounted) setState(() => _setup = setup);
                        });
                      }
                    },
            ),
          ],
        )
      else ...[
        if (_setup != null) ...[
          Text(
            mx(
              context,
              '1. 使用身份验证器扫描二维码，或输入密钥：',
              '1. Scan the QR code with your authenticator, or enter this secret:',
            ),
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _setup!.secret,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              IconButton(
                tooltip: mx(context, '复制密钥', 'Copy secret'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _setup!.secret)),
                icon: const Icon(Icons.copy, size: 16),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Image.memory(
              base64Decode(_setup!.qrImage.split(',').last),
              width: 180,
              height: 180,
              errorBuilder: (_, error, stack) => Text(
                mx(
                  context,
                  '二维码无法显示，请手动输入上方密钥。',
                  'Cannot display the QR code. Enter the secret above manually.',
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        DesktopSettingRow(
          label: mx(context, '验证码', 'Verification code'),
          child: DesktopSettingInput(
            controller: _code,
            enabled: !_busy,
            hint: mx(context, '输入 6 位数字', 'Enter six digits'),
            onSubmitted: (_) => _mfaSubmit(),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            ManagementButton(
              label: mx(context, '取消', 'Cancel'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _setup = null;
                      _disabling = false;
                      _code.clear();
                    }),
            ),
            ManagementButton(
              label: _disabling
                  ? mx(context, '禁用', 'Disable')
                  : mx(context, '保存', 'Save'),
              primary: true,
              onPressed: _busy ? null : _mfaSubmit,
            ),
          ],
        ),
      ],
    ],
  );
}
