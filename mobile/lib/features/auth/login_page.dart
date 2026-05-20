import 'package:flutter/material.dart';

import '../../core/utils/jwt_expiry.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
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

  LoginExpiry _expiry = LoginExpiry.currentDay;
  bool _savePassword = false;
  bool _httpRiskAccepted = false;
  bool _showHttpRiskBanner = false;
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

  /// Resolve a [LoginResult] into the user-facing error string. Prefers the
  /// localized message keyed by [LoginResult.messageKey]; otherwise falls back
  /// to whatever the controller / backend handed us.
  String _resolveErrorMessage(LoginResult result, AppLocalizations l) {
    final key = result.messageKey;
    if (key != null && key.isNotEmpty) return l.tr(key);
    if (result.message.isNotEmpty) return result.message;
    return l.tr('login.errLoginGeneric');
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final l = AppLocalizations.of(context);
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
        setState(() => _errorMessage = _resolveErrorMessage(result, l));
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
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final spacing = const SizedBox(height: 14);
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                _LoginHero(
                  title: l.tr('app.title'),
                  subtitle: l.tr('app.subtitle'),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  color: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('field-server'),
                          controller: _serverCtrl,
                          focusNode: _serverFocus,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _userFocus.requestFocus(),
                          decoration: InputDecoration(
                            labelText: l.tr('login.serverAddress'),
                            hintText: l.tr('login.serverAddressHint'),
                            prefixIcon: const Icon(Icons.dns_outlined),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        spacing,
                        TextField(
                          key: const Key('field-username'),
                          controller: _userCtrl,
                          focusNode: _userFocus,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                          decoration: InputDecoration(
                            labelText: l.tr('login.username'),
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        spacing,
                        TextField(
                          key: const Key('field-password'),
                          controller: _pwdCtrl,
                          focusNode: _passwordFocus,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: l.tr('login.password'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        spacing,
                        TextField(
                          key: const Key('field-mfa'),
                          controller: _mfaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l.tr('login.mfa'),
                            prefixIcon: const Icon(Icons.pin_outlined),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _ExpiryPicker(
                          value: _expiry,
                          onChanged: (value) => setState(() => _expiry = value),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          key: const Key('switch-save-password'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.tr('login.savePassword')),
                          secondary: const Icon(Icons.enhanced_encryption),
                          value: _savePassword,
                          onChanged: (value) =>
                              setState(() => _savePassword = value),
                        ),
                        if (_showHttpRiskBanner) ...[
                          spacing,
                          _HttpRiskBanner(onConfirm: _acceptHttpRiskAndSubmit),
                        ],
                        if (_errorMessage != null) ...[
                          spacing,
                          _ErrorBox(message: _errorMessage!),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            key: const Key('btn-login'),
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: Text(l.tr('login.submit')),
                          ),
                        ),
                      ],
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

class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Image.asset(
            'assets/logo_v2_01.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HttpRiskBanner extends StatelessWidget {
  const _HttpRiskBanner({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                  l.tr('login.httpRiskTitle'),
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.tr('login.httpRiskBody'),
                  style: TextStyle(color: colors.onErrorContainer),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onConfirm,
                    child: Text(l.tr('common.continue')),
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

  static const _optionKeys = <LoginExpiry, String>{
    LoginExpiry.currentDay: 'login.expiry.currentDay',
    LoginExpiry.threeDays: 'login.expiry.threeDays',
    LoginExpiry.sevenDays: 'login.expiry.sevenDays',
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.tr('login.sessionDuration'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _optionKeys.entries)
              ChoiceChip(
                label: Text(l.tr(entry.value)),
                selected: entry.key == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(entry.key),
              ),
          ],
        ),
      ],
    );
  }
}

bool loginPageShouldWarnHttp(String address) => isHttpAddress(address);
