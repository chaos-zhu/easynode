import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/app_color_theme.dart';
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

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
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
        title: Text(_isEdit ? l.tr('proxy.edit') : l.tr('proxy.add')),
      ),
      bottomNavigationBar: _BottomBar(
        saving: _saving,
        label: l.tr('common.save'),
        onPressed: _saving ? null : _save,
      ),
      body: Form(
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
                          color: context.colors.muted,
                        ),
                      ),
                    ),
                  ],
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
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: context.colors.muted,
          ),
        ),
        if (trailing != null && trailing!.isNotEmpty)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: context.colors.muted,
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
        color: context.colors.text,
        fontFamily: monospace ? 'monospace' : null,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 13,
          color: context.colors.softMuted,
        ),
        isDense: true,
        filled: true,
        fillColor: context.colors.card,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
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
    final bg = selected ? context.colors.accentSoft : context.colors.card;
    final border = selected ? context.colors.primary : context.colors.border;
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
                color: selected ? context.colors.primary : context.colors.chip,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 16,
                color: selected
                    ? context.colors.fontOnPrimary
                    : context.colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.colors.muted,
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
              color: selected ? context.colors.primary : context.colors.softMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
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
