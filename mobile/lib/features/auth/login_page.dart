import 'package:flutter/material.dart';

import '../../core/utils/jwt_expiry.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
import 'auth_session.dart';
import 'login_controller.dart';

const _loginCanvas = Color(0xFFF7EFE0);
const _loginSurface = Color(0xFFFBF5E6);
const _loginField = Color(0xFFF4ECD7);
const _loginBorder = Color(0xFFE2D5B3);
const _loginAccent = Color(0xFFE5B33A);
const _loginInk = Color(0xFF2A2418);
const _loginMuted = Color(0xFF9A8B68);
const _loginStrongMuted = Color(0xFF6B5E3F);

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
    return Scaffold(
      backgroundColor: _loginCanvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    children: [
                      _LoginHero(
                        title: l.tr('app.title'),
                        subtitle: l.tr('app.subtitle'),
                      ),
                      const SizedBox(height: 22),
                      _LoginFormCard(
                        serverCtrl: _serverCtrl,
                        userCtrl: _userCtrl,
                        passwordCtrl: _pwdCtrl,
                        mfaCtrl: _mfaCtrl,
                        serverFocus: _serverFocus,
                        userFocus: _userFocus,
                        passwordFocus: _passwordFocus,
                        onSubmit: _submit,
                      ),
                      const SizedBox(height: 24),
                      _ExpiryPicker(
                        value: _expiry,
                        onChanged: (value) => setState(() => _expiry = value),
                      ),
                      const SizedBox(height: 8),
                      _SavePasswordRow(
                        value: _savePassword,
                        onChanged: (value) =>
                            setState(() => _savePassword = value),
                      ),
                      if (_showHttpRiskBanner) ...[
                        const SizedBox(height: 14),
                        _HttpRiskBanner(onConfirm: _acceptHttpRiskAndSubmit),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBox(message: _errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _LoginBottomBar(
              submitting: _submitting,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.serverCtrl,
    required this.userCtrl,
    required this.passwordCtrl,
    required this.mfaCtrl,
    required this.serverFocus,
    required this.userFocus,
    required this.passwordFocus,
    required this.onSubmit,
  });

  final TextEditingController serverCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController mfaCtrl;
  final FocusNode serverFocus;
  final FocusNode userFocus;
  final FocusNode passwordFocus;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: _loginSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _loginBorder),
      ),
      child: Column(
        children: [
          _LoginTextField(
            fieldKey: const Key('field-server'),
            controller: serverCtrl,
            focusNode: serverFocus,
            label: l.tr('login.serverAddress'),
            hint: l.tr('login.serverAddressHint'),
            icon: Icons.dns_outlined,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => userFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          _LoginTextField(
            fieldKey: const Key('field-username'),
            controller: userCtrl,
            focusNode: userFocus,
            label: l.tr('login.username'),
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          _LoginTextField(
            fieldKey: const Key('field-password'),
            controller: passwordCtrl,
            focusNode: passwordFocus,
            label: l.tr('login.password'),
            icon: Icons.lock_outline,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 14),
          _LoginTextField(
            fieldKey: const Key('field-mfa'),
            controller: mfaCtrl,
            label: l.tr('login.mfa'),
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.hint,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.obscureText = false,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      obscureText: obscureText,
      style: const TextStyle(
        color: _loginInk,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: _loginStrongMuted),
        filled: true,
        fillColor: _loginField,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          color: _loginMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: const TextStyle(
          color: _loginStrongMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: _loginStrongMuted, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _loginBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _loginAccent, width: 1.2),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _SavePasswordRow extends StatelessWidget {
  const _SavePasswordRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            color: _loginStrongMuted,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.tr('login.savePassword'),
              style: const TextStyle(
                color: _loginStrongMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            key: const Key('switch-save-password'),
            value: value,
            activeThumbColor: _loginSurface,
            activeTrackColor: _loginAccent,
            inactiveThumbColor: _loginSurface,
            inactiveTrackColor: _loginBorder,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LoginBottomBar extends StatelessWidget {
  const _LoginBottomBar({required this.submitting, required this.onSubmit});

  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: _loginSurface,
        border: Border(top: BorderSide(color: _loginBorder)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          key: const Key('btn-login'),
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: _loginAccent,
            foregroundColor: const Color(0xFF5C4520),
            disabledBackgroundColor: _loginBorder,
            disabledForegroundColor: _loginMuted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF5C4520),
                  ),
                )
              : const Icon(Icons.arrow_forward, size: 18),
          label: Text(
            l.tr('login.submit'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Image.asset(
            'assets/logo_v2_01.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: _loginInk,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: _loginMuted,
            fontWeight: FontWeight.w500,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8BF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6A23C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFF7A4A00), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('login.httpRiskTitle'),
                  style: const TextStyle(
                    color: Color(0xFF7A4A00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.tr('login.httpRiskBody'),
                  style: const TextStyle(
                    color: Color(0xFF7A4A00),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onConfirm,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7A4A00),
                    ),
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
    return Container(
      key: const Key('login-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE7DE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE28B75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFF8B2B1C), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF8B2B1C),
                fontSize: 13,
                height: 1.35,
              ),
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
          style: theme.textTheme.labelLarge?.copyWith(
            color: _loginStrongMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final entry in _optionKeys.entries)
              ChoiceChip(
                selected: entry.key == value,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                backgroundColor: _loginSurface,
                selectedColor: const Color(0xFFF7E4B0),
                side: BorderSide(
                  color: entry.key == value ? _loginAccent : _loginBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelStyle: TextStyle(
                  color: entry.key == value ? _loginInk : _loginStrongMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                label: Text(l.tr(entry.value)),
                onSelected: (_) => onChanged(entry.key),
              ),
          ],
        ),
      ],
    );
  }
}

bool loginPageShouldWarnHttp(String address) => isHttpAddress(address);
