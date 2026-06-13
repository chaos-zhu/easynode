import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/utils/jwt_expiry.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_localizations.dart';
import '../../state/package_info_provider.dart';
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
        setState(() => _submitting = false);
        final accepted = await _confirmHttpRisk();
        if (!mounted || accepted != true) return;
        setState(() => _httpRiskAccepted = true);
        await _submit();
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

  Future<bool?> _confirmHttpRisk() {
    final l = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('login.httpRiskTitle')),
        content: Text(l.tr('login.httpRiskBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tr('common.continue')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.colors.canvas,
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
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
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
      style: TextStyle(
        color: context.colors.text,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: context.colors.muted),
        filled: true,
        fillColor: context.colors.chip,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: TextStyle(
          color: context.colors.softMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: context.colors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: context.colors.muted, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.accent, width: 1.2),
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
          Icon(
            Icons.shield_outlined,
            color: context.colors.muted,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.tr('login.savePassword'),
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            key: const Key('switch-save-password'),
            value: value,
            activeThumbColor: context.colors.card,
            activeTrackColor: context.colors.accent,
            inactiveThumbColor: context.colors.card,
            inactiveTrackColor: context.colors.border,
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
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          key: const Key('btn-login'),
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.accent,
            foregroundColor: context.colors.fontOnPrimary,
            disabledBackgroundColor: context.colors.border,
            disabledForegroundColor: context.colors.softMuted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: submitting
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.fontOnPrimary,
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

class _LoginHero extends ConsumerWidget {
  const _LoginHero({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final info = ref.watch(packageInfoProvider).valueOrNull;
    final versionLabel = info == null ? '' : 'v${info.version}';
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
            color: context.colors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              versionLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.colors.softMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (versionLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/chaos-zhu/easynode'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: context.colors.softMuted,
                ),
              ),
            ],
          ],
        ),
      ],
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
        color: context.colors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.dangerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: context.colors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.colors.danger,
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
            color: context.colors.muted,
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
                backgroundColor: context.colors.card,
                selectedColor: context.colors.banner,
                side: BorderSide(
                  color: entry.key == value ? context.colors.accent : context.colors.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelStyle: TextStyle(
                  color: entry.key == value ? context.colors.text : context.colors.muted,
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
