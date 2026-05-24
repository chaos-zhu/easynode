import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/palette.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/proxy_list_notifier.dart';
import '../servers/server_proxy_model.dart';

class ProxyEditPage extends ConsumerStatefulWidget {
  const ProxyEditPage({super.key, this.proxy});

  final ServerProxyModel? proxy;

  @override
  ConsumerState<ProxyEditPage> createState() => _ProxyEditPageState();
}

class _ProxyEditPageState extends ConsumerState<ProxyEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _type = 'socks5';
  bool _saving = false;
  bool _deleting = false;
  bool _showPassword = false;

  bool get _isEdit => widget.proxy != null;

  @override
  void initState() {
    super.initState();
    final p = widget.proxy;
    if (p != null) {
      _type = p.type.isEmpty ? 'socks5' : p.type;
      _nameCtrl.text = p.name;
      _hostCtrl.text = p.host;
      _portCtrl.text = p.port == 0 ? '' : '${p.port}';
      _userCtrl.text = p.username;
      _passCtrl.text = p.password;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final port = int.tryParse(_portCtrl.text.trim()) ?? 0;
    final next = ServerProxyModel(
      id: widget.proxy?.id ?? '',
      name: _nameCtrl.text.trim(),
      type: _type,
      host: _hostCtrl.text.trim(),
      port: port,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      if (_isEdit) {
        await repo.updateProxy(next);
      } else {
        await repo.createProxy(next);
      }
      if (!mounted) return;
      _showSnack(l.tr('proxy.saved'));
      await ref.read(proxyListProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.saveFailed', [err.message]));
    } catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.saveFailed', [err.toString()]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final p = widget.proxy;
    if (p == null) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tr('proxy.deleteConfirmTitle')),
        content: Text(l.trf('proxy.deleteConfirmBody', [p.displayName])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.danger,
              foregroundColor: AppPalette.fontOnPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(settingsRepositoryProvider).deleteProxy(p.id);
      if (!mounted) return;
      _showSnack(l.tr('proxy.deleted'));
      await ref.read(proxyListProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiFailure catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.deleteFailed', [err.message]));
    } catch (err) {
      if (!mounted) return;
      _showSnack(l.trf('proxy.deleteFailed', [err.toString()]));
    } finally {
      if (mounted) setState(() => _deleting = false);
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
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: AppBar(
        backgroundColor: AppPalette.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(_isEdit ? l.tr('proxy.edit') : l.tr('proxy.add')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _AppBarSaveButton(
              loading: _saving,
              label: l.tr('common.save'),
              onTap: _saving ? null : _save,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _FieldLabel(label: l.tr('proxy.field.type')),
                    const SizedBox(height: 8),
                    _TypeSelector(
                      value: _type,
                      onChanged: (next) => setState(() => _type = next),
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel(label: l.tr('proxy.field.name')),
                    const SizedBox(height: 8),
                    _FormField(
                      controller: _nameCtrl,
                      hintText: l.tr('proxy.field.nameHint'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l.tr('proxy.validation.name')
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(label: l.tr('proxy.field.host')),
                              const SizedBox(height: 8),
                              _FormField(
                                controller: _hostCtrl,
                                hintText: l.tr('proxy.field.hostHint'),
                                monospace: true,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? l.tr('proxy.validation.host')
                                        : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 110,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(label: l.tr('proxy.field.port')),
                              const SizedBox(height: 8),
                              _FormField(
                                controller: _portCtrl,
                                hintText: l.tr('proxy.field.portHint'),
                                monospace: true,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (v) {
                                  final n = int.tryParse(
                                    (v ?? '').trim(),
                                  );
                                  if (n == null || n < 1 || n > 65535) {
                                    return l.tr('proxy.validation.port');
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel(
                      label: l.tr('proxy.field.username'),
                      trailing: l.tr('common.optional'),
                    ),
                    const SizedBox(height: 8),
                    _FormField(
                      controller: _userCtrl,
                      hintText: l.tr('proxy.field.username'),
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel(
                      label: l.tr('proxy.field.password'),
                      trailing: l.tr('common.optional'),
                    ),
                    const SizedBox(height: 8),
                    _FormField(
                      controller: _passCtrl,
                      hintText: l.tr('proxy.field.password'),
                      obscure: !_showPassword,
                      suffix: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: AppPalette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _BottomBar(
              isEdit: _isEdit,
              saving: _saving,
              deleting: _deleting,
              saveLabel: l.tr('common.save'),
              deleteLabel: l.tr('common.delete'),
              onSave: _saving || _deleting ? null : _save,
              onDelete: _saving || _deleting ? null : _delete,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBarSaveButton extends StatelessWidget {
  const _AppBarSaveButton({
    required this.loading,
    required this.label,
    required this.onTap,
  });

  final bool loading;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppPalette.fontOnPrimary,
                  ),
                )
              else
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppPalette.fontOnPrimary,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.fontOnPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppPalette.muted,
          ),
        ),
        if (trailing != null && trailing!.isNotEmpty)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppPalette.muted,
            ),
          ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.hintText,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.monospace = false,
    this.obscure = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool monospace;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscure,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppPalette.text,
        fontFamily: monospace ? 'monospace' : null,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: AppPalette.softMuted,
        ),
        isDense: true,
        filled: true,
        fillColor: AppPalette.card,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.danger),
        ),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged});

  final String value;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TypeOption(
          label: 'SOCKS5',
          description: 'SOCKS5 协议代理',
          icon: Icons.shuffle_rounded,
          selected: value == 'socks5',
          onTap: () => onChanged('socks5'),
        ),
        const SizedBox(height: 10),
        _TypeOption(
          label: 'HTTP',
          description: 'HTTP / HTTPS 代理',
          icon: Icons.public_rounded,
          selected: value == 'http',
          onTap: () => onChanged('http'),
        ),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppPalette.accentSoft : AppPalette.card;
    final border = selected ? AppPalette.primary : AppPalette.border;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: selected ? 2 : 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? AppPalette.primary : AppPalette.chip,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 16,
                color: selected
                    ? AppPalette.fontOnPrimary
                    : AppPalette.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: selected ? AppPalette.primary : AppPalette.softMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isEdit,
    required this.saving,
    required this.deleting,
    required this.saveLabel,
    required this.deleteLabel,
    required this.onSave,
    required this.onDelete,
  });

  final bool isEdit;
  final bool saving;
  final bool deleting;
  final String saveLabel;
  final String deleteLabel;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppPalette.canvas,
        border: Border(
          top: BorderSide(color: AppPalette.strongBorder, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: AppPalette.danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                icon: deleting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.danger,
                        ),
                      )
                    : const Icon(Icons.delete_outline, size: 16),
                label: Text(
                  deleteLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (isEdit) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: AppPalette.fontOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                disabledBackgroundColor: AppPalette.chip,
                disabledForegroundColor: AppPalette.softMuted,
              ),
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppPalette.fontOnPrimary,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                saveLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
