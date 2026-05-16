import 'package:flutter/material.dart';

import '../../core/utils/jwt_expiry.dart';
import '../../core/utils/validators.dart';
import 'auth_session.dart';
import 'login_controller.dart';

/// Mobile login page.
///
/// Intentionally minimal: just enough form fields to log into an existing
/// EasyNode server. The layout is deliberately distinct from the AGPL
/// reference project — single vertical column, no decorative widgets.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.controller,
    required this.initialServerAddress,
    required this.initialUsername,
    required this.initialSavePassword,
    required this.onLoginSuccess,
    this.initialPassword = '',
  });

  final LoginController controller;
  final String initialServerAddress;
  final String initialUsername;
  final String initialPassword;
  final bool initialSavePassword;
  final ValueChanged<AuthSession> onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _serverCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _pwdCtrl;
  final TextEditingController _mfaCtrl = TextEditingController();

  LoginExpiry _expiry = LoginExpiry.temporary;
  bool _savePassword = false;
  bool _httpRiskAccepted = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: widget.initialServerAddress);
    _userCtrl = TextEditingController(text: widget.initialUsername);
    _pwdCtrl = TextEditingController(text: widget.initialPassword);
    _savePassword = widget.initialSavePassword;
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _mfaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.controller.login(
        serverAddress: _serverCtrl.text,
        username: _userCtrl.text,
        password: _pwdCtrl.text,
        mfa2Token: _mfaCtrl.text,
        httpRiskAccepted: _httpRiskAccepted,
        savePassword: _savePassword,
        expiry: _expiry,
      );

      if (!mounted) return;

      if (result.requiresHttpRiskConfirmation) {
        final accepted = await _showHttpRiskDialog();
        if (!mounted) return;
        if (accepted == true) {
          setState(() => _httpRiskAccepted = true);
          // Re-submit immediately with the risk now accepted.
          await _submit();
          return;
        }
        setState(() => _errorMessage = '请确认 HTTP 风险后再登录');
        return;
      }

      if (!result.success || result.session == null) {
        setState(() => _errorMessage = result.message.isEmpty ? '登录失败' : result.message);
        return;
      }

      widget.onLoginSuccess(result.session!);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<bool?> _showHttpRiskDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HTTP 风险提示'),
        content: const Text(
          '当前服务端地址使用 HTTP 协议。登录后产生的 token 与 session cookie 会以明文方式传输，'
          '存在被第三方截获并接管会话的风险。建议改用 HTTPS。\n\n确认继续以 HTTP 方式登录？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('我已知风险，继续'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EasyNode 登录')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('field-server'),
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务端地址',
                hintText: 'http://192.168.1.10:8082',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('field-username'),
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('field-password'),
              controller: _pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('field-mfa'),
              controller: _mfaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'MFA2 验证码（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _ExpiryPicker(
              value: _expiry,
              onChanged: (value) => setState(() => _expiry = value),
            ),
            SwitchListTile(
              key: const Key('switch-save-password'),
              contentPadding: EdgeInsets.zero,
              title: const Text('保存密码到安全存储'),
              value: _savePassword,
              onChanged: (value) => setState(() => _savePassword = value),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                key: const Key('login-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('btn-login'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryPicker extends StatelessWidget {
  const _ExpiryPicker({required this.value, required this.onChanged});
  final LoginExpiry value;
  final ValueChanged<LoginExpiry> onChanged;

  static const _options = <LoginExpiry, String>{
    LoginExpiry.temporary: '临时（1 小时）',
    LoginExpiry.currentDay: '当天',
    LoginExpiry.threeDays: '三天',
    LoginExpiry.sevenDays: '七天',
  };

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '登录有效期',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LoginExpiry>(
          isExpanded: true,
          value: value,
          items: [
            for (final entry in _options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Standalone helper so consumers (and tests) can call the same HTTP detection
/// the page uses without poking at private widget state.
bool loginPageShouldWarnHttp(String address) => isHttpAddress(address);
