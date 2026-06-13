import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/auth_notifier.dart';
import 'settings_repository.dart';

class AccountSecurityPage extends ConsumerStatefulWidget {
  const AccountSecurityPage({super.key});

  @override
  ConsumerState<AccountSecurityPage> createState() =>
      _AccountSecurityPageState();
}

class _AccountSecurityPageState extends ConsumerState<AccountSecurityPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldNameCtrl = TextEditingController();
  final _oldPwdCtrl = TextEditingController();
  final _newNameCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _newPwdConfirmCtrl = TextEditingController();

  bool _showOldPwd = false;
  bool _showNewPwd = false;
  bool _showNewPwdConfirm = false;
  bool _saving = false;

  bool _mfaEnabled = false;
  bool _mfaLoading = true;
  Mfa2Setup? _setup;
  bool _enableLoading = false;
  bool _disableLoading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadMfa);
  }

  @override
  void dispose() {
    _oldNameCtrl.dispose();
    _oldPwdCtrl.dispose();
    _newNameCtrl.dispose();
    _newPwdCtrl.dispose();
    _newPwdConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMfa() async {
    try {
      final enabled =
          await ref.read(settingsRepositoryProvider).getMfa2Status();
      if (!mounted) return;
      setState(() {
        _mfaEnabled = enabled;
        _mfaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _mfaLoading = false);
    }
  }

  Future<void> _saveAccount() async {
    final l = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final oldName = _oldNameCtrl.text.trim();
    final newName = _newNameCtrl.text.trim();
    final oldPwd = _oldPwdCtrl.text;
    final newPwd = _newPwdCtrl.text;

    if (oldName == newName && oldPwd == newPwd) {
      _showSnack(l.tr('account.usernameSame'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('account.confirmTitle')),
        content: Text(l.tr('account.confirmBody')),
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

    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).updateAccount(
            oldLoginName: oldName,
            oldPwd: oldPwd,
            newLoginName: newName,
            newPwd: newPwd,
          );
      if (!mounted) return;
      _showSnack(l.tr('account.changed'));
      await ref.read(authProvider.notifier).signOut();
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(err.message);
    } catch (err) {
      if (!mounted) return;
      _showSnack(err.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startEnableMfa() async {
    setState(() => _enableLoading = true);
    try {
      final setup =
          await ref.read(settingsRepositoryProvider).getMfa2QrInfo();
      if (!mounted) return;
      setState(() => _setup = setup);
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(err.message);
    } finally {
      if (mounted) setState(() => _enableLoading = false);
    }
  }

  Future<void> _submitEnableMfa(String token) async {
    final l = AppLocalizations.of(context);
    if (token.length != 6 || int.tryParse(token) == null) {
      _showSnack(l.tr('account.mfa.codeInvalid'));
      return;
    }
    setState(() => _enableLoading = true);
    try {
      await ref.read(settingsRepositoryProvider).enableMfa2(token);
      if (!mounted) return;
      _showSnack(l.tr('account.mfa.enabled'));
      setState(() {
        _setup = null;
        _mfaEnabled = true;
      });
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(err.message);
    } finally {
      if (mounted) setState(() => _enableLoading = false);
    }
  }

  Future<void> _disableMfa() async {
    final l = AppLocalizations.of(context);
    final token = await _promptForCode(
      title: l.tr('account.mfa.disable'),
      label: l.tr('account.mfa.codeLabel'),
      confirmText: l.tr('account.mfa.disableConfirm'),
    );
    if (token == null || !mounted) return;
    if (token.length != 6 || int.tryParse(token) == null) {
      _showSnack(l.tr('account.mfa.codeInvalid'));
      return;
    }
    setState(() => _disableLoading = true);
    try {
      await ref.read(settingsRepositoryProvider).disableMfa2(token);
      if (!mounted) return;
      _showSnack(l.tr('account.mfa.disabled'));
      setState(() {
        _mfaEnabled = false;
        _setup = null;
      });
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(err.message);
    } finally {
      if (mounted) setState(() => _disableLoading = false);
    }
  }

  Future<String?> _promptForCode({
    required String title,
    required String label,
    required String confirmText,
  }) async {
    final controller = TextEditingController();
    final l = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              hintText: '6 digits',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  void _copySecret() {
    final setup = _setup;
    if (setup == null) return;
    final l = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: setup.secret));
    _showSnack(l.tr('common.saved'));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        backgroundColor: context.colors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l.tr('settings.account.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionHeader(label: l.tr('account.section.credentials')),
          const SizedBox(height: 10),
          _CredentialsCard(
            formKey: _formKey,
            oldNameCtrl: _oldNameCtrl,
            oldPwdCtrl: _oldPwdCtrl,
            newNameCtrl: _newNameCtrl,
            newPwdCtrl: _newPwdCtrl,
            newPwdConfirmCtrl: _newPwdConfirmCtrl,
            showOldPwd: _showOldPwd,
            showNewPwd: _showNewPwd,
            showNewPwdConfirm: _showNewPwdConfirm,
            saving: _saving,
            onToggleOldPwd: () =>
                setState(() => _showOldPwd = !_showOldPwd),
            onToggleNewPwd: () =>
                setState(() => _showNewPwd = !_showNewPwd),
            onToggleNewPwdConfirm: () => setState(
                () => _showNewPwdConfirm = !_showNewPwdConfirm),
            onSubmit: _saveAccount,
          ),
          const SizedBox(height: 22),
          _SectionHeader(label: l.tr('account.section.mfa')),
          const SizedBox(height: 10),
          _MfaCard(
            loading: _mfaLoading,
            enabled: _mfaEnabled,
            setup: _setup,
            enableLoading: _enableLoading,
            disableLoading: _disableLoading,
            onStartEnable: _enableLoading ? null : _startEnableMfa,
            onSubmitEnable: _submitEnableMfa,
            onCancelEnable: () => setState(() => _setup = null),
            onDisable: _disableLoading ? null : _disableMfa,
            onCopySecret: _copySecret,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: context.colors.muted,
        ),
      ),
    );
  }
}

class _CredentialsCard extends StatelessWidget {
  const _CredentialsCard({
    required this.formKey,
    required this.oldNameCtrl,
    required this.oldPwdCtrl,
    required this.newNameCtrl,
    required this.newPwdCtrl,
    required this.newPwdConfirmCtrl,
    required this.showOldPwd,
    required this.showNewPwd,
    required this.showNewPwdConfirm,
    required this.saving,
    required this.onToggleOldPwd,
    required this.onToggleNewPwd,
    required this.onToggleNewPwdConfirm,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController oldNameCtrl;
  final TextEditingController oldPwdCtrl;
  final TextEditingController newNameCtrl;
  final TextEditingController newPwdCtrl;
  final TextEditingController newPwdConfirmCtrl;
  final bool showOldPwd;
  final bool showNewPwd;
  final bool showNewPwdConfirm;
  final bool saving;
  final VoidCallback onToggleOldPwd;
  final VoidCallback onToggleNewPwd;
  final VoidCallback onToggleNewPwdConfirm;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FieldGroup(
              label: l.tr('account.oldLoginName'),
              child: _TextInput(
                controller: oldNameCtrl,
                hintText: l.tr('account.oldLoginName'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l.tr('account.usernameRequired')
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _FieldGroup(
              label: l.tr('account.oldPwd'),
              child: _TextInput(
                controller: oldPwdCtrl,
                hintText: l.tr('account.oldPwd'),
                obscure: !showOldPwd,
                suffix: _EyeButton(
                  visible: showOldPwd,
                  onTap: onToggleOldPwd,
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? l.tr('account.pwdRequired')
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _FieldGroup(
              label: l.tr('account.newLoginName'),
              child: _TextInput(
                controller: newNameCtrl,
                hintText: l.tr('account.newLoginName'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l.tr('account.usernameRequired')
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _FieldGroup(
              label: l.tr('account.newPwd'),
              child: _TextInput(
                controller: newPwdCtrl,
                hintText: l.tr('account.newPwd'),
                obscure: !showNewPwd,
                suffix: _EyeButton(
                  visible: showNewPwd,
                  onTap: onToggleNewPwd,
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? l.tr('account.pwdRequired')
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            _FieldGroup(
              label: l.tr('account.newPwdConfirm'),
              child: _TextInput(
                controller: newPwdConfirmCtrl,
                hintText: l.tr('account.newPwdConfirm'),
                obscure: !showNewPwdConfirm,
                suffix: _EyeButton(
                  visible: showNewPwdConfirm,
                  onTap: onToggleNewPwdConfirm,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return l.tr('account.pwdRequired');
                  }
                  if (v != newPwdCtrl.text) {
                    return l.tr('account.pwdMismatch');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saving ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.fontOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  disabledBackgroundColor: context.colors.chip,
                  disabledForegroundColor: context.colors.softMuted,
                ),
                icon: saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.fontOnPrimary,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(
                  l.tr('account.submit'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.tr('account.confirmBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: context.colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.muted,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.hintText,
    this.validator,
    this.obscure = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final String? Function(String?)? validator;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: TextStyle(
        fontSize: 14,
        color: context.colors.text,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 13,
          color: context.colors.softMuted,
        ),
        isDense: true,
        filled: true,
        fillColor: context.colors.canvas,
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.danger),
        ),
      ),
    );
  }
}

class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 18,
        color: context.colors.muted,
      ),
    );
  }
}

class _MfaCard extends StatefulWidget {
  const _MfaCard({
    required this.loading,
    required this.enabled,
    required this.setup,
    required this.enableLoading,
    required this.disableLoading,
    required this.onStartEnable,
    required this.onSubmitEnable,
    required this.onCancelEnable,
    required this.onDisable,
    required this.onCopySecret,
  });

  final bool loading;
  final bool enabled;
  final Mfa2Setup? setup;
  final bool enableLoading;
  final bool disableLoading;
  final VoidCallback? onStartEnable;
  final Future<void> Function(String token) onSubmitEnable;
  final VoidCallback onCancelEnable;
  final VoidCallback? onDisable;
  final VoidCallback onCopySecret;

  @override
  State<_MfaCard> createState() => _MfaCardState();
}

class _MfaCardState extends State<_MfaCard> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: widget.loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.enabled
                            ? l.tr('account.mfa.statusOn')
                            : l.tr('account.mfa.statusOff'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.colors.text,
                        ),
                      ),
                    ),
                    _MfaStatusChip(enabled: widget.enabled),
                  ],
                ),
                const SizedBox(height: 10),
                if (widget.enabled) ...[
                  Text(
                    l.tr('account.mfa.scanHint'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onDisable,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.danger,
                        side: BorderSide(color: context.colors.danger),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: widget.disableLoading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.colors.danger,
                              ),
                            )
                          : const Icon(Icons.lock_open_outlined, size: 16),
                      label: Text(l.tr('account.mfa.disable')),
                    ),
                  ),
                ] else if (widget.setup != null) ...[
                  Text(
                    l.tr('account.mfa.scanHint'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(child: _QrPreview(setup: widget.setup!)),
                  const SizedBox(height: 12),
                  _SecretRow(
                    secret: widget.setup!.secret,
                    onCopy: widget.onCopySecret,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.tr('account.mfa.codeLabel'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'monospace',
                      letterSpacing: 6,
                      color: context.colors.text,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '------',
                      hintStyle: TextStyle(
                        fontSize: 18,
                        letterSpacing: 6,
                        color: context.colors.softMuted,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: context.colors.canvas,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.enableLoading
                              ? null
                              : widget.onCancelEnable,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.muted,
                            side: BorderSide(color: context.colors.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(l.tr('common.cancel')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: widget.enableLoading
                              ? null
                              : () => widget.onSubmitEnable(
                                    _codeCtrl.text.trim(),
                                  ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.primary,
                            foregroundColor: context.colors.fontOnPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: widget.enableLoading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.colors.fontOnPrimary,
                                  ),
                                )
                              : Text(l.tr('account.mfa.enableConfirm')),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    l.tr('account.mfa.scanHint'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onStartEnable,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        foregroundColor: context.colors.fontOnPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: widget.enableLoading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.colors.fontOnPrimary,
                              ),
                            )
                          : const Icon(Icons.shield_outlined, size: 16),
                      label: Text(l.tr('account.mfa.enable')),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _MfaStatusChip extends StatelessWidget {
  const _MfaStatusChip({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bg = enabled
        ? context.colors.success.withValues(alpha: 0.16)
        : context.colors.chip;
    final fg = enabled ? context.colors.success : context.colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        enabled
            ? l.tr('account.mfa.statusOn')
            : l.tr('account.mfa.statusOff'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _QrPreview extends StatelessWidget {
  const _QrPreview({required this.setup});

  final Mfa2Setup setup;

  @override
  Widget build(BuildContext context) {
    final bytes = setup.qrImageBytes;
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: context.colors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.strongBorder),
      ),
      alignment: Alignment.center,
      child: bytes != null
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Image.memory(bytes, fit: BoxFit.contain),
            )
          : Icon(
              Icons.qr_code_2_rounded,
              size: 96,
              color: context.colors.softMuted,
            ),
    );
  }
}

class _SecretRow extends StatelessWidget {
  const _SecretRow({required this.secret, required this.onCopy});

  final String secret;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              secret,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: context.colors.text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: l.tr('account.mfa.copySecret'),
            onPressed: onCopy,
            icon: Icon(
              Icons.copy_outlined,
              size: 18,
              color: context.colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
