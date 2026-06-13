import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/credential_list_notifier.dart';
import '../servers/server_credential_model.dart';

class CredentialEditPage extends ConsumerStatefulWidget {
  const CredentialEditPage({super.key, this.credential});

  final ServerCredentialModel? credential;

  @override
  ConsumerState<CredentialEditPage> createState() => _CredentialEditPageState();
}

class _CredentialEditPageState extends ConsumerState<CredentialEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _privateKeyCtrl;
  late final TextEditingController _passphraseCtrl;

  String _authType = 'privateKey';
  bool _showPassword = false;
  bool _showPassphrase = false;
  bool _saving = false;

  bool get _isEdit => widget.credential != null;

  @override
  void initState() {
    super.initState();
    final c = widget.credential;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _passwordCtrl = TextEditingController();
    _privateKeyCtrl = TextEditingController();
    _passphraseCtrl = TextEditingController();
    if (c != null) _authType = c.authType.isEmpty ? 'privateKey' : c.authType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _privateKeyCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final privateKey = _privateKeyCtrl.text.trim();
    final passphrase = _passphraseCtrl.text;

    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      if (_isEdit) {
        await repo.updateCredential(
          id: widget.credential!.id,
          name: name,
          authType: _authType,
          password: password,
          privateKey: privateKey,
          openSSHKeyPassword: passphrase,
        );
      } else {
        await repo.createCredential(
          name: name,
          authType: _authType,
          password: password,
          privateKey: privateKey,
          openSSHKeyPassword: passphrase,
        );
      }
      if (!mounted) return;
      _showSnack(l.tr('credentials.saved'));
      await ref.read(credentialListProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('credentials.saveFailed', [err.message]));
    } catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('credentials.saveFailed', [err.toString()]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isKey = _authType == 'privateKey';
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        backgroundColor: context.colors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(_isEdit ? l.tr('credentials.edit') : l.tr('credentials.add')),
      ),
      bottomNavigationBar: _BottomSaveBar(
        saving: _saving,
        label: l.tr('common.save'),
        onPressed: _saving ? null : _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            _FieldLabel(text: l.tr('credentials.field.name')),
            const SizedBox(height: 8),
            _FormField(
              controller: _nameCtrl,
              hint: l.tr('credentials.field.nameHint'),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) {
                  return l.tr('credentials.validation.name');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _FieldLabel(text: l.tr('credentials.field.authType')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TypeOption(
                    label: l.tr('servers.auth.password'),
                    sublabel: l.tr('credentials.field.password'),
                    icon: Icons.lock_outline,
                    selected: !isKey,
                    onTap: () => setState(() => _authType = 'password'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeOption(
                    label: l.tr('servers.auth.privateKey'),
                    sublabel: l.tr('credentials.field.privateKey'),
                    icon: Icons.vpn_key_outlined,
                    selected: isKey,
                    onTap: () => setState(() => _authType = 'privateKey'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!isKey) ...[
              _FieldLabel(
                text: l.tr('credentials.field.password'),
                trailing: _isEdit ? '(${l.tr('credentials.editHint')})' : null,
              ),
              const SizedBox(height: 8),
              _FormField(
                controller: _passwordCtrl,
                hint: l.tr('credentials.field.passwordHint'),
                obscure: !_showPassword,
                suffix: _EyeButton(
                  open: _showPassword,
                  onTap: () => setState(() => _showPassword = !_showPassword),
                ),
                validator: (v) {
                  if (!_isEdit && (v ?? '').isEmpty) {
                    return l.tr('credentials.validation.password');
                  }
                  return null;
                },
              ),
            ],
            if (isKey) ...[
              _FieldLabel(
                text: l.tr('credentials.field.privateKey'),
                trailing: _isEdit ? '(${l.tr('credentials.editHint')})' : null,
              ),
              const SizedBox(height: 8),
              _FormField(
                controller: _privateKeyCtrl,
                hint: l.tr('credentials.field.privateKeyHint'),
                maxLines: 8,
                monospace: true,
                validator: (v) {
                  if (!_isEdit && (v ?? '').trim().isEmpty) {
                    return l.tr('credentials.validation.privateKey');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _FieldLabel(
                text: l.tr('credentials.field.passphrase'),
                trailing: l.tr('common.optional'),
              ),
              const SizedBox(height: 8),
              _FormField(
                controller: _passphraseCtrl,
                hint: l.tr('credentials.field.passphraseHint'),
                obscure: !_showPassphrase,
                suffix: _EyeButton(
                  open: _showPassphrase,
                  onTap: () => setState(() => _showPassphrase = !_showPassphrase),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomSaveBar extends StatelessWidget {
  const _BottomSaveBar({
    required this.saving,
    required this.label,
    required this.onPressed,
  });

  final bool saving;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: context.colors.card,
          border: Border(top: BorderSide(color: context.colors.border)),
        ),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.fontOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onPressed,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: context.colors.muted,
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: context.colors.softMuted,
            ),
          ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    this.hint,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.maxLines = 1,
    this.monospace = false,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final int maxLines;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      maxLines: obscure ? 1 : maxLines,
      style: TextStyle(
        fontSize: monospace ? 12 : 14,
        fontFamily: monospace ? 'monospace' : null,
        color: context.colors.text,
        height: monospace ? 1.5 : null,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: monospace ? context.colors.chip : context.colors.card,
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 13,
          color: context.colors.softMuted,
        ),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.accent),
        ),
      ),
    );
  }
}

class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        open ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 18,
        color: context.colors.muted,
      ),
      onPressed: onTap,
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? context.colors.accentSoft : context.colors.card;
    final border = selected ? context.colors.primary : context.colors.border;
    final borderWidth = selected ? 2.0 : 1.0;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: borderWidth),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? context.colors.primary : context.colors.muted,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: selected ? context.colors.primary : context.colors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.colors.softMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
