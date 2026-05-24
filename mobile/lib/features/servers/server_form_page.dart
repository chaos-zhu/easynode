import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/palette.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/credential_list_notifier.dart';
import '../../state/group_list_notifier.dart';
import '../../state/host_list_notifier.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/proxy_list_notifier.dart';
import '../../state/server_data_refresh.dart';
import 'server_credential_model.dart';
import 'server_form_data.dart';
import 'server_group_model.dart';
import 'server_model.dart';
import 'server_proxy_model.dart';

class ServerFormPage extends ConsumerStatefulWidget {
  const ServerFormPage({super.key, this.server});

  final ServerModel? server;

  @override
  ConsumerState<ServerFormPage> createState() => _ServerFormPageState();
}

class _ServerFormPageState extends ConsumerState<ServerFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _indexCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _privateKeyCtrl = TextEditingController();
  final _consoleUrlCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _commandCtrl = TextEditingController();

  late ServerFormData _form;
  bool _saving = false;
  bool _advancedOpen = true;

  @override
  void initState() {
    super.initState();
    final hosts = ref.read(hostListProvider).valueOrNull ?? const <ServerModel>[];
    final maxIndex = hosts.fold<int>(
      0,
      (max, host) => host.index > max ? host.index : max,
    );
    _form = widget.server == null
        ? ServerFormData.add(nextIndex: maxIndex + 1)
        : ServerFormData.edit(widget.server!);
    _syncControllers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _indexCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _privateKeyCtrl.dispose();
    _consoleUrlCtrl.dispose();
    _tagsCtrl.dispose();
    _commandCtrl.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _nameCtrl.text = _form.name;
    _indexCtrl.text = _form.index.toString();
    _hostCtrl.text = _form.host;
    _portCtrl.text = _form.port.toString();
    _usernameCtrl.text = _form.username;
    _passwordCtrl.text = _form.password;
    _privateKeyCtrl.text = _form.privateKey;
    _consoleUrlCtrl.text = _form.consoleUrl;
    _tagsCtrl.text = _form.tag.join(',');
    _commandCtrl.text = _form.command;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final groups = ref.watch(groupListProvider).valueOrNull ?? const <ServerGroupModel>[];
    final hosts = ref.watch(hostListProvider).valueOrNull ?? const <ServerModel>[];
    final credentials = ref.watch(credentialListProvider).valueOrNull ??
        const <ServerCredentialModel>[];
    final proxies =
        ref.watch(proxyListProvider).valueOrNull ?? const <ServerProxyModel>[];
    final isPlusActive = ref.watch(isPlusActiveProvider);
    final jumpHostOptions = hosts
        .where((host) => host.isConfig && host.id != _form.id)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: _FormColors.surface,
      appBar: AppBar(
        backgroundColor: _FormColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(_form.isEdit ? l.tr('servers.editServer') : l.tr('servers.addServer')),
      ),
      bottomNavigationBar: _BottomSaveBar(
        saving: _saving,
        label: _form.isEdit ? l.tr('common.save') : l.tr('servers.addServer'),
        onPressed: _saving ? null : _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ConnectionTypeSegment(
              value: _form.connectType,
              onChanged: _changeConnectType,
            ),
            const SizedBox(height: 14),
            _CardSection(
              title: l.tr('servers.section.instance'),
              children: [
                _GroupSelector(
                  label: l.tr('servers.field.group'),
                  value: _normalizeGroupValue(groups),
                  groups: groups,
                  onChanged: (value) => _form.group = value ?? 'default',
                  validator: (value) =>
                      value == null || value.isEmpty ? l.tr('servers.validation.group') : null,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TextField(
                        controller: _nameCtrl,
                        label: l.tr('servers.field.name'),
                        validator: (value) => _required(value, l.tr('servers.validation.name')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: _TextField(
                        controller: _indexCtrl,
                        label: l.tr('servers.field.index'),
                        keyboardType: TextInputType.number,
                        validator: (value) => _requiredInt(
                          value,
                          l.tr('servers.validation.index'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CardSection(
              title: l.tr('servers.section.connection'),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TextField(
                        controller: _hostCtrl,
                        label: l.tr('servers.field.host'),
                        mono: true,
                        validator: (value) => _required(value, l.tr('servers.validation.host')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: _TextField(
                        controller: _portCtrl,
                        label: l.tr('servers.field.port'),
                        mono: true,
                        keyboardType: TextInputType.number,
                        validator: (value) => _requiredInt(
                          value,
                          l.tr('servers.validation.port'),
                        ),
                      ),
                    ),
                  ],
                ),
                _TextField(
                  controller: _usernameCtrl,
                  label: l.tr('servers.field.username'),
                  mono: true,
                ),
                if (_form.isSsh) ...[
                  _AuthTypeSegment(
                    value: _form.authType,
                    onChanged: (value) => setState(() => _form.authType = value),
                  ),
                  FormField<String>(
                    key: ValueKey('auth-${_form.authType}'),
                    initialValue: _form.credential,
                    validator: _form.authType == 'credential'
                        ? (value) => value == null || value.isEmpty
                            ? l.tr('servers.validation.credential')
                            : null
                        : null,
                    builder: (field) => AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _AuthField(
                        key: ValueKey(_form.authType),
                        form: _form,
                        passwordCtrl: _passwordCtrl,
                        privateKeyCtrl: _privateKeyCtrl,
                        credentials: credentials,
                        errorText: field.errorText,
                        onCredentialChanged: (value) => setState(() {
                          _form.credential = value ?? '';
                          field.didChange(_form.credential);
                        }),
                      ),
                    ),
                  ),
                ] else
                  _TextField(
                    controller: _passwordCtrl,
                    label: l.tr('servers.field.password'),
                    obscureText: true,
                    helperText: _form.isEdit ? l.tr('servers.secretEditHint') : null,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _CardSection(
              title: l.tr('servers.advanced'),
              trailing: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _advancedOpen = !_advancedOpen),
                icon: Icon(
                  _advancedOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: _FormColors.textMuted,
                ),
              ),
              children: _advancedOpen
                  ? [
                      if (_form.isSsh) ...[
                        FormField<String>(
                          key: ValueKey('proxy-${_form.proxyType}'),
                          initialValue: _form.proxyType == 'jumpHosts'
                              ? _form.jumpHosts.join(',')
                              : _form.proxyServer,
                          validator: _form.proxyType.isEmpty
                              ? null
                              : (value) => value == null || value.isEmpty
                                  ? l.tr(_form.proxyType == 'jumpHosts'
                                      ? 'servers.validation.jumpHosts'
                                      : 'servers.validation.proxyServer')
                                  : null,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ProxyTypeSegment(
                                value: _form.proxyType,
                                isPlusActive: isPlusActive,
                                onChanged: _changeProxyType,
                                onPlusRequired: _showProxyPlusRequiredSnack,
                              ),
                              if (!isPlusActive)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    l.tr('servers.proxyPlusTip'),
                                    style: const TextStyle(
                                      color: _FormColors.label,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: _ProxyField(
                                  key: ValueKey(_form.proxyType),
                                  proxyType: _form.proxyType,
                                  proxies: proxies,
                                  proxyValue: _normalizeProxyValue(proxies),
                                  jumpHostOptions: jumpHostOptions,
                                  jumpHostIds: _form.jumpHosts,
                                  errorText: field.errorText,
                                  onProxyChanged: (value) => setState(() {
                                    _form.proxyServer = value ?? '';
                                    field.didChange(_form.proxyServer);
                                  }),
                                  onJumpHostsChanged: (ids) => setState(() {
                                    _form.jumpHosts = ids;
                                    field.didChange(_form.jumpHosts.join(','));
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_form.isSsh)
                        _TextField(
                          controller: _commandCtrl,
                          label: l.tr('servers.field.command'),
                          minLines: 3,
                          maxLines: 4,
                        ),
                      _DateField(
                        label: l.tr('servers.field.expired'),
                        value: _form.expired,
                        onChanged: (value) => setState(() {
                          _form.expired = value;
                          if (value == null) _form.expiredNotify = false;
                        }),
                      ),
                      _SwitchRow(
                        label: l.tr('servers.field.expiredNotify'),
                        value: _form.expiredNotify,
                        enabled: _form.expired != null,
                        onChanged: (value) => setState(() {
                          _form.expiredNotify = value;
                        }),
                      ),
                      _TextField(
                        controller: _tagsCtrl,
                        label: l.tr('servers.field.tags'),
                        helperText: l.tr('servers.tagsHint'),
                      ),
                      _TextField(
                        controller: _consoleUrlCtrl,
                        label: l.tr('servers.field.consoleUrl'),
                        mono: true,
                      ),
                    ]
                  : const [],
            ),
          ],
        ),
      ),
    );
  }

  void _changeConnectType(String next) {
    setState(() {
      _form.connectType = next;
      if (!_form.isEdit) {
        if (next == 'rdp') {
          _form.port = 3389;
          _form.username = 'Administrator';
          _form.authType = 'password';
        } else {
          _form.port = 22;
          _form.username = 'root';
          _form.authType = 'password';
        }
        _portCtrl.text = _form.port.toString();
        _usernameCtrl.text = _form.username;
      }
    });
  }

  void _changeProxyType(String next) {
    setState(() {
      _form.proxyType = next;
      if (next != 'jumpHosts') _form.jumpHosts = const [];
      if (next != 'proxyServer') _form.proxyServer = '';
    });
  }

  void _showProxyPlusRequiredSnack() {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.tr('servers.proxyPlusTip'))),
    );
  }

  String? _normalizeGroupValue(List<ServerGroupModel> groups) {
    if (groups.any((group) => group.id == _form.group)) return _form.group;
    if (groups.isNotEmpty) {
      _form.group = groups.first.id;
      return _form.group;
    }
    return null;
  }

  String? _normalizeProxyValue(List<ServerProxyModel> proxies) {
    if (proxies.any((proxy) => proxy.id == _form.proxyServer)) {
      return _form.proxyServer;
    }
    if (_form.proxyServer.isNotEmpty) _form.proxyServer = '';
    return null;
  }

  String? _required(String? value, String message) {
    return value == null || value.trim().isEmpty ? message : null;
  }

  String? _requiredInt(String? value, String message) {
    if (value == null || value.trim().isEmpty) return message;
    return int.tryParse(value.trim()) == null ? message : null;
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    _form
      ..name = _nameCtrl.text
      ..host = _hostCtrl.text
      ..port = int.parse(_portCtrl.text.trim())
      ..username = _usernameCtrl.text
      ..index = int.parse(_indexCtrl.text.trim())
      ..password = _passwordCtrl.text
      ..privateKey = _privateKeyCtrl.text
      ..consoleUrl = _consoleUrlCtrl.text
      ..tag = _tagsCtrl.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false)
      ..command = _commandCtrl.text;
    try {
      final repo = ref.read(serverRepositoryProvider);
      final message = _form.isEdit ? await repo.updateHost(_form) : await repo.createHost(_form);
      await refreshServerSharedData(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message == 'success' ? l.tr('common.saved') : message)),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _FormColors {
  static const surface = AppPalette.canvas;
  static const card = AppPalette.card;
  static const field = AppPalette.chip;
  static const primary = AppPalette.primary;
  static const border = AppPalette.border;
  static const text = AppPalette.text;
  static const textMuted = AppPalette.muted;
  static const label = AppPalette.softMuted;
}

class _CardSection extends StatelessWidget {
  const _CardSection({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _FormColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _FormColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _FormColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _FormColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (children.isNotEmpty) const SizedBox(height: 14),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionTypeSegment extends StatelessWidget {
  const _ConnectionTypeSegment({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SegmentShell(
      children: [
        _SegmentButton(
          selected: value == 'ssh',
          icon: Icons.terminal,
          label: 'SSH',
          onTap: () => onChanged('ssh'),
        ),
        _SegmentButton(
          selected: value == 'rdp',
          icon: Icons.monitor_outlined,
          label: 'RDP',
          onTap: () => onChanged('rdp'),
        ),
      ],
    );
  }
}

class _AuthTypeSegment extends StatelessWidget {
  const _AuthTypeSegment({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _LabeledBlock(
      label: l.tr('servers.field.authType'),
      child: _SegmentShell(
        compact: true,
        children: [
          _SegmentButton(
            selected: value == 'password',
            icon: Icons.lock_outline,
            label: l.tr('servers.auth.password'),
            onTap: () => onChanged('password'),
          ),
          _SegmentButton(
            selected: value == 'privateKey',
            icon: Icons.key_outlined,
            label: l.tr('servers.auth.privateKey'),
            onTap: () => onChanged('privateKey'),
          ),
          _SegmentButton(
            selected: value == 'credential',
            icon: Icons.shield_outlined,
            label: l.tr('servers.auth.credential'),
            onTap: () => onChanged('credential'),
          ),
        ],
      ),
    );
  }
}

class _ProxyTypeSegment extends StatelessWidget {
  const _ProxyTypeSegment({
    required this.value,
    required this.onChanged,
    required this.isPlusActive,
    required this.onPlusRequired,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool isPlusActive;
  final VoidCallback onPlusRequired;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _LabeledBlock(
      label: l.tr('servers.field.proxyType'),
      child: _SegmentShell(
        compact: true,
        children: [
          _SegmentButton(
            selected: value.isEmpty,
            icon: Icons.block,
            label: l.tr('servers.proxy.noneShort'),
            onTap: () => onChanged(''),
          ),
          _SegmentButton(
            selected: value == 'proxyServer',
            icon: Icons.public,
            label: l.tr('servers.proxy.socksShort'),
            disabled: !isPlusActive,
            onTap: () =>
                isPlusActive ? onChanged('proxyServer') : onPlusRequired(),
          ),
          _SegmentButton(
            selected: value == 'jumpHosts',
            icon: Icons.hub_outlined,
            label: l.tr('servers.proxy.jumpHostsShort'),
            disabled: !isPlusActive,
            onTap: () =>
                isPlusActive ? onChanged('jumpHosts') : onPlusRequired(),
          ),
        ],
      ),
    );
  }
}

class _SegmentShell extends StatelessWidget {
  const _SegmentShell({
    required this.children,
    this.compact = false,
  });

  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 44 : 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _FormColors.card,
        borderRadius: BorderRadius.circular(compact ? 10 : 16),
        border: Border.all(color: _FormColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabled = false,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? _FormColors.card
        : (disabled ? _FormColors.label : _FormColors.textMuted);
    return Material(
      color: selected ? _FormColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Opacity(
          opacity: disabled && !selected ? 0.55 : 1,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.check : icon,
                    size: 16,
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _FormColors.label,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.minLines,
    this.maxLines = 1,
    this.helperText,
    this.mono = false,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? minLines;
  final int? maxLines;
  final String? helperText;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return _LabeledBlock(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        minLines: obscureText ? 1 : minLines,
        maxLines: obscureText ? 1 : maxLines,
        validator: validator,
        style: TextStyle(
          color: _FormColors.text,
          fontSize: 15,
          fontFamily: mono ? 'monospace' : null,
        ),
        decoration: _fieldDecoration(helperText: helperText),
      ),
    );
  }
}

InputDecoration _fieldDecoration({String? helperText}) {
  return InputDecoration(
    filled: true,
    fillColor: _FormColors.field,
    helperText: helperText,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _FormColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _FormColors.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
    ),
  );
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    super.key,
    required this.form,
    required this.passwordCtrl,
    required this.privateKeyCtrl,
    required this.credentials,
    required this.errorText,
    required this.onCredentialChanged,
  });

  final ServerFormData form;
  final TextEditingController passwordCtrl;
  final TextEditingController privateKeyCtrl;
  final List<ServerCredentialModel> credentials;
  final String? errorText;
  final ValueChanged<String?> onCredentialChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (form.authType == 'password') {
      return _TextField(
        controller: passwordCtrl,
        label: l.tr('servers.field.password'),
        obscureText: true,
        helperText: form.isEdit ? l.tr('servers.secretEditHint') : null,
      );
    }
    if (form.authType == 'privateKey') {
      return _TextField(
        controller: privateKeyCtrl,
        label: l.tr('servers.field.privateKey'),
        minLines: 5,
        maxLines: 8,
        helperText: form.isEdit ? l.tr('servers.secretEditHint') : null,
      );
    }
    final value = credentials.any((item) => item.id == form.credential)
        ? form.credential
        : null;
    ServerCredentialModel? selected;
    for (final item in credentials) {
      if (item.id == value) {
        selected = item;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PickerField(
          label: l.tr('servers.field.credential'),
          value: selected?.displayName ?? '',
          leadingIcon: Icons.shield_outlined,
          meta: selected == null
              ? null
              : selected.authType == 'privateKey'
                  ? l.tr('servers.auth.privateKey')
                  : l.tr('servers.auth.password'),
          placeholder: l.tr('servers.credentials.empty'),
          enabled: credentials.isNotEmpty,
          errorText: errorText,
          onTap: () async {
            final result = await _showChoiceSheet<String>(
              context: context,
              title: l.tr('servers.field.credential'),
              value: selected?.id,
              options: [
                for (final item in credentials)
                  _ChoiceSheetOption(
                    value: item.id,
                    icon: Icons.shield_outlined,
                    label: item.displayName,
                    meta: item.authType == 'privateKey'
                        ? l.tr('servers.auth.privateKey')
                        : l.tr('servers.auth.password'),
                  ),
              ],
            );
            if (result != null) onCredentialChanged(result);
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 13, color: _FormColors.label),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                credentials.isEmpty
                    ? l.tr('servers.credentials.empty')
                    : l.tr('servers.credentials.hint'),
                style: const TextStyle(color: _FormColors.label, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

}

class _ProxySelector extends StatelessWidget {
  const _ProxySelector({
    required this.proxies,
    required this.value,
    required this.errorText,
    required this.onChanged,
  });

  final List<ServerProxyModel> proxies;
  final String? value;
  final String? errorText;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ServerProxyModel? selected;
    for (final item in proxies) {
      if (item.id == value) {
        selected = item;
        break;
      }
    }
    return _PickerField(
      label: l.tr('servers.field.proxyServer'),
      value: selected?.displayName ?? '',
      leadingIcon: Icons.public,
      meta: selected?.typeLabel,
      placeholder: l.tr('servers.proxy.empty'),
      enabled: proxies.isNotEmpty,
      errorText: errorText,
      onTap: () async {
        final result = await _showChoiceSheet<String>(
          context: context,
          title: l.tr('servers.field.proxyServer'),
          value: selected?.id,
          options: [
            for (final item in proxies)
              _ChoiceSheetOption(
                value: item.id,
                icon: Icons.public,
                label: item.displayName,
                meta: item.typeLabel,
              ),
          ],
        );
        if (result != null) onChanged(result);
      },
    );
  }
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({
    required this.label,
    required this.value,
    required this.groups,
    required this.onChanged,
    this.validator,
  });

  final String label;
  final String? value;
  final List<ServerGroupModel> groups;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: validator,
      builder: (field) {
        ServerGroupModel? selected;
        for (final group in groups) {
          if (group.id == field.value) {
            selected = group;
            break;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PickerField(
              label: label,
              value: selected?.displayName ?? '',
              leadingIcon: Icons.folder_outlined,
              placeholder: label,
              enabled: groups.isNotEmpty,
              errorText: field.errorText,
              onTap: () async {
                final result = await _showChoiceSheet<String>(
                  context: context,
                  title: label,
                  value: field.value,
                  options: [
                    for (final group in groups)
                      _ChoiceSheetOption(
                        value: group.id,
                        icon: Icons.folder_outlined,
                        label: group.displayName,
                      ),
                  ],
                );
                if (result != null) {
                  field.didChange(result);
                  onChanged(result);
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProxyField extends StatelessWidget {
  const _ProxyField({
    super.key,
    required this.proxyType,
    required this.proxies,
    required this.proxyValue,
    required this.jumpHostOptions,
    required this.jumpHostIds,
    required this.errorText,
    required this.onProxyChanged,
    required this.onJumpHostsChanged,
  });

  final String proxyType;
  final List<ServerProxyModel> proxies;
  final String? proxyValue;
  final List<ServerModel> jumpHostOptions;
  final List<String> jumpHostIds;
  final String? errorText;
  final ValueChanged<String?> onProxyChanged;
  final ValueChanged<List<String>> onJumpHostsChanged;

  @override
  Widget build(BuildContext context) {
    if (proxyType == 'proxyServer') {
      return _ProxySelector(
        proxies: proxies,
        value: proxyValue,
        errorText: errorText,
        onChanged: onProxyChanged,
      );
    }
    if (proxyType == 'jumpHosts') {
      return _JumpHostSelector(
        options: jumpHostOptions,
        selectedIds: jumpHostIds,
        errorText: errorText,
        onChanged: onJumpHostsChanged,
      );
    }
    return const SizedBox.shrink();
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.icon,
    this.enabled = true,
    this.emptyText,
    this.selectedItemBuilder,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;
  final IconData? icon;
  final bool enabled;
  final String? emptyText;
  final DropdownButtonBuilder? selectedItemBuilder;

  @override
  Widget build(BuildContext context) {
    return _LabeledBlock(
      label: label,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        items: items,
        onChanged: enabled ? onChanged : null,
        validator: validator,
        hint: emptyText == null
            ? null
            : Text(
                emptyText!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _FormColors.label),
              ),
        selectedItemBuilder: selectedItemBuilder,
        icon: Icon(icon ?? Icons.keyboard_arrow_down, color: _FormColors.label),
        style: const TextStyle(color: _FormColors.text, fontSize: 15),
        decoration: _fieldDecoration(),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.leadingIcon,
    this.meta,
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final String value;
  final String placeholder;
  final VoidCallback onTap;
  final IconData? leadingIcon;
  final String? meta;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _LabeledBlock(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: _fieldDecoration().copyWith(errorText: errorText),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(
                  leadingIcon,
                  size: 18,
                  color: enabled ? _FormColors.primary : _FormColors.label,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  value.isEmpty ? placeholder : value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: value.isEmpty ? _FormColors.label : _FormColors.text,
                    fontSize: 15,
                  ),
                ),
              ),
              if (meta != null && meta!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _MetaPill(label: meta!),
              ],
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down,
                color: _FormColors.label,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _FormColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _FormColors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _FormColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChoiceSheetOption<T> {
  const _ChoiceSheetOption({
    required this.value,
    required this.icon,
    required this.label,
    this.meta = '',
  });

  final T value;
  final IconData icon;
  final String label;
  final String meta;
}

Future<T?> _showChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required T? value,
  required List<_ChoiceSheetOption<T>> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    backgroundColor: _FormColors.card,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _FormColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final selected = option.value == value;
                    return Material(
                      color: selected ? _FormColors.field : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).pop(option.value),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? _FormColors.primary
                                  : _FormColors.border,
                              width: selected ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : option.icon,
                                size: 20,
                                color: _FormColors.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  option.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _FormColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (option.meta.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _MetaPill(label: option.meta),
                              ],
                            ],
                          ),
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
    },
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final display = value == null
        ? ''
        : '${value!.year.toString().padLeft(4, '0')}/'
            '${value!.month.toString().padLeft(2, '0')}/'
            '${value!.day.toString().padLeft(2, '0')}';
    return _LabeledBlock(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final now = DateTime.now();
          final result = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 20),
          );
          if (result != null) onChanged(result);
        },
        child: InputDecorator(
          decoration: _fieldDecoration(),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  display,
                  style: const TextStyle(
                    color: _FormColors.text,
                    fontSize: 15,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (value != null)
                InkWell(
                  onTap: () => onChanged(null),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: _FormColors.label),
                  ),
                ),
              const Icon(Icons.calendar_today_outlined, size: 18, color: _FormColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? _FormColors.textMuted : _FormColors.label,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Switch(
          value: enabled && value,
          activeThumbColor: _FormColors.card,
          activeTrackColor: _FormColors.primary,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _JumpHostSelector extends StatelessWidget {
  const _JumpHostSelector({
    required this.options,
    required this.selectedIds,
    required this.errorText,
    required this.onChanged,
  });

  final List<ServerModel> options;
  final List<String> selectedIds;
  final String? errorText;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final selectedHosts = <ServerModel>[];
    for (final id in selectedIds) {
      for (final host in options) {
        if (host.id == id) {
          selectedHosts.add(host);
          break;
        }
      }
    }
    return _LabeledBlock(
      label: options.isEmpty
          ? '${l.tr('servers.field.jumpHosts')} (${selectedHosts.length}/${options.length})'
          : '${l.tr('servers.field.jumpHosts')} (${selectedHosts.length}/${options.length})（${l.tr('servers.jumpHosts.orderHint')}）',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: options.isEmpty ? null : () => _showPicker(context),
        child: InputDecorator(
          decoration: _fieldDecoration(
            helperText: options.isEmpty
                ? l.tr('servers.jumpHosts.empty')
                : null,
          ).copyWith(errorText: errorText),
          child: selectedHosts.isEmpty
              ? Text(
                  l.tr('servers.jumpHosts.placeholder'),
                  style: const TextStyle(color: _FormColors.label, fontSize: 14),
                )
              : Column(
                  children: [
                    for (var i = 0; i < selectedHosts.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: _FormColors.primary,
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: _FormColors.card,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedHosts[i].displayName,
                                style: const TextStyle(color: _FormColors.text),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                final next = [...selectedIds]
                                  ..remove(selectedHosts[i].id);
                                onChanged(next);
                              },
                              child: const Icon(Icons.close, size: 18, color: _FormColors.label),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final next = [...selectedIds];
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      backgroundColor: _FormColors.card,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final l = AppLocalizations.of(context);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.tr('servers.field.jumpHosts'),
                          style: const TextStyle(
                            color: _FormColors.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(next),
                        child: Text(l.tr('common.save')),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: _FormColors.border),
                    itemBuilder: (context, index) {
                      final host = options[index];
                      final selected = next.contains(host.id);
                      final order = next.indexOf(host.id) + 1;
                      return CheckboxListTile(
                        value: selected,
                        activeColor: _FormColors.primary,
                        onChanged: (value) => setSheetState(() {
                          if (value == true) {
                            next.add(host.id);
                          } else {
                            next.remove(host.id);
                          }
                        }),
                        title: Text(host.displayName),
                        subtitle: Text(host.connectionLabel),
                        secondary: selected
                            ? CircleAvatar(
                                radius: 12,
                                backgroundColor: _FormColors.primary,
                                child: Text(
                                  '$order',
                                  style: const TextStyle(color: _FormColors.card),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (result != null) onChanged(result);
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
        decoration: const BoxDecoration(
          color: _FormColors.card,
          border: Border(top: BorderSide(color: _FormColors.border)),
        ),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _FormColors.primary,
              foregroundColor: _FormColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onPressed,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _FormColors.card,
                    ),
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
