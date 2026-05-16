import 'package:flutter/material.dart';

import '../../core/utils/jwt_expiry.dart';
import '../../core/utils/validators.dart';
import 'auth_session.dart';
import 'login_controller.dart';

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
  final FocusNode _serverFocus = FocusNode();
  final FocusNode _userFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  LoginExpiry _expiry = LoginExpiry.temporary;
  bool _savePassword = false;
  bool _httpRiskAccepted = false;
  bool _showHttpRiskBanner = false;
  bool _submitting = false;
  bool _passwordVisible = false;
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
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPassword != widget.initialPassword &&
        _pwdCtrl.text != widget.initialPassword) {
      _pwdCtrl.text = widget.initialPassword;
    }
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _mfaCtrl.dispose();
    _serverFocus.dispose();
    _userFocus.dispose();
    _passwordFocus.dispose();
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
        setState(() => _showHttpRiskBanner = true);
        return;
      }
      if (!result.success || result.session == null) {
        setState(
          () => _errorMessage = result.message.isEmpty
              ? 'Login failed'
              : result.message,
        );
        return;
      }
      widget.onLoginSuccess(result.session!);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _acceptHttpRiskAndSubmit() async {
    setState(() {
      _httpRiskAccepted = true;
      _showHttpRiskBanner = false;
    });
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = const SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('EasyNode')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('EasyNode', style: Theme.of(context).textTheme.headlineMedium),
            Text(
              'Mobile terminal access',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('field-server'),
              controller: _serverCtrl,
              focusNode: _serverFocus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _userFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'https://example.com',
                border: OutlineInputBorder(),
              ),
            ),
            spacing,
            TextField(
              key: const Key('field-username'),
              controller: _userCtrl,
              focusNode: _userFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            spacing,
            TextField(
              key: const Key('field-password'),
              controller: _pwdCtrl,
              focusNode: _passwordFocus,
              obscureText: !_passwordVisible,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _passwordVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
              ),
            ),
            spacing,
            TextField(
              key: const Key('field-mfa'),
              controller: _mfaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'MFA code (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            spacing,
            _ExpiryPicker(
              value: _expiry,
              onChanged: (value) => setState(() => _expiry = value),
            ),
            SwitchListTile(
              key: const Key('switch-save-password'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Save password securely'),
              value: _savePassword,
              onChanged: (value) => setState(() => _savePassword = value),
            ),
            if (_showHttpRiskBanner) ...[
              spacing,
              _HttpRiskBanner(onConfirm: _acceptHttpRiskAndSubmit),
            ],
            if (_errorMessage != null) ...[
              spacing,
              _ErrorBox(message: _errorMessage!),
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
                  : const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HttpRiskBanner extends StatelessWidget {
  const _HttpRiskBanner({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HTTP is not encrypted',
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your token and session cookie can be intercepted. Use HTTPS when possible.',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onConfirm,
                    child: const Text('Continue'),
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

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('login-error'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiryPicker extends StatelessWidget {
  const _ExpiryPicker({required this.value, required this.onChanged});

  final LoginExpiry value;
  final ValueChanged<LoginExpiry> onChanged;

  static const _options = <LoginExpiry, String>{
    LoginExpiry.temporary: 'Temporary, 1 hour',
    LoginExpiry.currentDay: 'Today',
    LoginExpiry.threeDays: '3 days',
    LoginExpiry.sevenDays: '7 days',
  };

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Session duration',
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

bool loginPageShouldWarnHttp(String address) => isHttpAddress(address);
