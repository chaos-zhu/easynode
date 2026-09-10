import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/utils/jwt_expiry.dart';
import '../../core/utils/validators.dart';
import '../../core/security/server_certificate_trust.dart';
import '../../core/storage/app_storage.dart';
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
    this.initialAccounts = const [],
    this.loadSavedPassword,
    this.onDeleteAccount,
  });

  final LoginController controller;
  final String initialServerAddress;
  final String initialUsername;
  final String initialPassword;
  final bool initialSavePassword;
  final List<SavedLoginAccount> initialAccounts;
  final Future<String?> Function(SavedLoginAccount account)? loadSavedPassword;
  final Future<void> Function(SavedLoginAccount account)? onDeleteAccount;
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

  LoginExpiry _expiry = LoginExpiry.threeDays;
  bool _savePassword = false;
  bool _httpRiskAccepted = false;
  bool _submitting = false;
  int _accountSelection = 0;
  late List<SavedLoginAccount> _savedAccounts;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: widget.initialServerAddress);
    _userCtrl = TextEditingController(text: widget.initialUsername);
    _pwdCtrl = TextEditingController(text: widget.initialPassword);
    _savePassword = widget.initialSavePassword;
    _savedAccounts = widget.initialAccounts.toList();
  }

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPassword != widget.initialPassword &&
        _pwdCtrl.text != widget.initialPassword) {
      _pwdCtrl.text = widget.initialPassword;
    }
    if (!identical(oldWidget.initialAccounts, widget.initialAccounts)) {
      _savedAccounts = widget.initialAccounts.toList();
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

  Future<void> _showSavedAccounts() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted) return;
    final accounts = _savedAccounts.toList();
    final selectedAccount = await showModalBottomSheet<SavedLoginAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: accounts.isEmpty ? 0.34 : 0.62,
          child: _LoginHistorySheet(
            accounts: accounts,
            onSelect: (account) => Navigator.of(sheetContext).pop(account),
            onDelete: (account) async {
              final deleted = await _confirmDeleteAccount(account);
              if (!deleted || !sheetContext.mounted) return;
              setSheetState(() {
                accounts.removeWhere(
                  (item) =>
                      item.matches(account.serverAddress, account.username),
                );
              });
            },
          ),
        ),
      ),
    );
    if (!mounted || selectedAccount == null) return;
    await _selectAccount(selectedAccount);
  }

  Future<void> _selectAccount(SavedLoginAccount account) async {
    final selection = ++_accountSelection;
    setState(() {
      _httpRiskAccepted = false;
      _errorMessage = null;
      _serverCtrl.text = account.serverAddress;
      _userCtrl.text = account.username;
      _pwdCtrl.clear();
      _mfaCtrl.clear();
      _savePassword = account.savePassword;
    });
    _serverFocus.unfocus();

    final loader = widget.loadSavedPassword;
    if (!account.savePassword || loader == null) return;
    final password = await loader(account);
    if (!mounted || selection != _accountSelection) return;
    if (_serverCtrl.text == account.serverAddress &&
        _userCtrl.text == account.username) {
      setState(() => _pwdCtrl.text = password ?? '');
    }
  }

  Future<bool> _confirmDeleteAccount(SavedLoginAccount account) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('login.deleteAccount')),
        content: Text(
          l.trf('login.deleteAccountBody', [
            '${account.username} · ${account.serverAddress}',
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    try {
      await widget.onDeleteAccount?.call(account);
      if (!mounted) return false;
      final isCurrent =
          _serverCtrl.text == account.serverAddress &&
          _userCtrl.text == account.username;
      setState(() {
        _savedAccounts.removeWhere(
          (item) => item.matches(account.serverAddress, account.username),
        );
        if (isCurrent) {
          _pwdCtrl.clear();
          _savePassword = false;
        }
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(
        () => _errorMessage = l.trf('login.deleteAccountFailed', [error]),
      );
      return false;
    }
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
      if (result.requiresCertificateConfirmation) {
        setState(() => _submitting = false);
        final certificate = result.certificate!;
        final accepted = await _confirmCertificate(certificate);
        if (!mounted || accepted != true) return;
        try {
          await widget.controller.trustCertificate(certificate);
        } catch (error) {
          if (mounted) setState(() => _errorMessage = error.toString());
          return;
        }
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

  Future<bool?> _confirmCertificate(PresentedServerCertificate certificate) {
    final l = AppLocalizations.of(context);
    final previous = certificate.previousFingerprint;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          l.tr(
            certificate.replacesTrustedCertificate
                ? 'login.certificateChangedTitle'
                : 'login.certificateTitle',
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.tr(
                  certificate.replacesTrustedCertificate
                      ? 'login.certificateChangedBody'
                      : 'login.certificateBody',
                ),
              ),
              const SizedBox(height: 16),
              Text(l.tr('login.certificateServer')),
              const SizedBox(height: 4),
              SelectableText(certificate.origin),
              const SizedBox(height: 12),
              Text(l.tr('login.certificateFingerprint')),
              const SizedBox(height: 4),
              SelectableText(
                certificate.displayFingerprint,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              if (previous != null) ...[
                const SizedBox(height: 12),
                Text(l.tr('login.certificatePreviousFingerprint')),
                const SizedBox(height: 4),
                SelectableText(
                  formatCertificateFingerprint(previous),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tr('login.trustCertificate')),
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
                      _LoginHero(title: l.tr('app.title')),
                      const SizedBox(height: 22),
                      _LoginFormCard(
                        serverCtrl: _serverCtrl,
                        userCtrl: _userCtrl,
                        passwordCtrl: _pwdCtrl,
                        mfaCtrl: _mfaCtrl,
                        serverFocus: _serverFocus,
                        userFocus: _userFocus,
                        passwordFocus: _passwordFocus,
                        onShowSavedAccounts: _showSavedAccounts,
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
            _LoginBottomBar(submitting: _submitting, onSubmit: _submit),
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
    required this.onShowSavedAccounts,
    required this.onSubmit,
  });

  final TextEditingController serverCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController mfaCtrl;
  final FocusNode serverFocus;
  final FocusNode userFocus;
  final FocusNode passwordFocus;
  final VoidCallback onShowSavedAccounts;
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
            suffixIcon: IconButton(
              key: const Key('btn-login-history'),
              tooltip: l.tr('login.savedAccounts'),
              onPressed: onShowSavedAccounts,
              icon: const Icon(Icons.history, size: 20),
            ),
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
    this.suffixIcon,
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
  final Widget? suffixIcon;
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
        suffixIcon: suffixIcon,
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

class _LoginHistorySheet extends StatelessWidget {
  const _LoginHistorySheet({
    required this.accounts,
    required this.onSelect,
    required this.onDelete,
  });

  final List<SavedLoginAccount> accounts;
  final ValueChanged<SavedLoginAccount> onSelect;
  final ValueChanged<SavedLoginAccount> onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('saved-account-menu'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 21,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.tr('login.savedAccounts'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('btn-close-login-history'),
                    tooltip: l.tr('common.close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            if (accounts.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    l.tr('login.noSavedAccounts'),
                    style: TextStyle(
                      color: context.colors.softMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: accounts.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 48,
                    color: context.colors.border.withValues(alpha: 0.65),
                  ),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    return InkWell(
                      key: ValueKey(
                        'saved-account-${account.serverAddress}-${account.username}',
                      ),
                      onTap: () => onSelect(account),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              key: ValueKey(
                                'delete-saved-account-${account.serverAddress}-${account.username}',
                              ),
                              tooltip: l.tr('common.delete'),
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                foregroundColor: context.colors.softMuted,
                                backgroundColor: context.colors.chip.withValues(
                                  alpha: 0.72,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () => onDelete(account),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.colors.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    account.serverAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.colors.softMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
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
          Icon(Icons.shield_outlined, color: context.colors.muted, size: 18),
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
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
          child: Image.asset('assets/logo_v2_01.png', fit: BoxFit.cover),
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
    LoginExpiry.threeDays: 'login.expiry.threeDays',
    LoginExpiry.sevenDays: 'login.expiry.sevenDays',
    LoginExpiry.thirtyDays: 'login.expiry.thirtyDays',
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
                  color: entry.key == value
                      ? context.colors.accent
                      : context.colors.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelStyle: TextStyle(
                  color: entry.key == value
                      ? context.colors.text
                      : context.colors.muted,
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
