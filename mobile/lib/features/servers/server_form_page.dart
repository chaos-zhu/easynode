import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/group_list_notifier.dart';
import '../../state/host_list_notifier.dart';
import 'server_form_data.dart';
import 'server_group_model.dart';
import 'server_model.dart';

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
    _tagsCtrl.text = _form.tag.join(', ');
    _commandCtrl.text = _form.command;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final groups = ref.watch(groupListProvider).valueOrNull ?? const <ServerGroupModel>[];
    final hosts = ref.watch(hostListProvider).valueOrNull ?? const <ServerModel>[];
    final jumpHostOptions = hosts
        .where((host) => host.isConfig && host.id != _form.id)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(_form.isEdit ? l.tr('servers.editServer') : l.tr('servers.addServer')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(l.tr('common.save')),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            _Section(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'ssh',
                      icon: Icon(Icons.terminal),
                      label: Text('SSH'),
                    ),
                    ButtonSegment(
                      value: 'rdp',
                      icon: Icon(Icons.desktop_windows_outlined),
                      label: Text('RDP'),
                    ),
                  ],
                  selected: {_form.connectType},
                  onSelectionChanged: (values) {
                    final next = values.first;
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
                          _form.authType = 'privateKey';
                        }
                        _portCtrl.text = _form.port.toString();
                        _usernameCtrl.text = _form.username;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _normalizeGroupValue(groups),
                  decoration: InputDecoration(labelText: l.tr('servers.field.group')),
                  items: groups
                      .map(
                        (group) => DropdownMenuItem(
                          value: group.id,
                          child: Text(group.displayName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => _form.group = value ?? 'default',
                  validator: (value) =>
                      value == null || value.isEmpty ? l.tr('servers.validation.group') : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _TextField(
                        controller: _nameCtrl,
                        label: l.tr('servers.field.name'),
                        validator: (value) => _required(value, l.tr('servers.validation.name')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _TextField(
                        controller: _hostCtrl,
                        label: l.tr('servers.field.host'),
                        validator: (value) => _required(value, l.tr('servers.validation.host')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _TextField(
                        controller: _portCtrl,
                        label: l.tr('servers.field.port'),
                        keyboardType: TextInputType.number,
                        validator: (value) => _requiredInt(
                          value,
                          l.tr('servers.validation.port'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TextField(
                  controller: _usernameCtrl,
                  label: l.tr('servers.field.username'),
                ),
                const SizedBox(height: 12),
                if (_form.isSsh) ...[
                  DropdownButtonFormField<String>(
                    value: _form.authType,
                    decoration: InputDecoration(labelText: l.tr('servers.field.authType')),
                    items: [
                      DropdownMenuItem(
                        value: 'privateKey',
                        child: Text(l.tr('servers.auth.privateKey')),
                      ),
                      DropdownMenuItem(
                        value: 'password',
                        child: Text(l.tr('servers.auth.password')),
                      ),
                      DropdownMenuItem(
                        value: 'credential',
                        child: Text(l.tr('servers.auth.credential')),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _form.authType = value ?? 'privateKey';
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_form.isRdp || _form.authType == 'password')
                  _TextField(
                    controller: _passwordCtrl,
                    label: l.tr('servers.field.password'),
                    obscureText: true,
                    helperText: _form.isEdit ? l.tr('servers.secretEditHint') : null,
                  )
                else if (_form.authType == 'privateKey')
                  _TextField(
                    controller: _privateKeyCtrl,
                    label: l.tr('servers.field.privateKey'),
                    minLines: 5,
                    maxLines: 8,
                    helperText: _form.isEdit ? l.tr('servers.secretEditHint') : null,
                  )
                else
                  Text(l.tr('servers.credentialUnsupported')),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(l.tr('servers.advanced')),
                  children: [
                    if (_form.isSsh) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l.tr('servers.field.proxyType'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: Text(l.tr('servers.proxy.none')),
                              selected: _form.proxyType == '',
                              onSelected: (_) => setState(() {
                                _form.proxyType = '';
                                _form.jumpHosts = const [];
                              }),
                            ),
                            ChoiceChip(
                              label: Text(l.tr('servers.proxy.proxyServer')),
                              selected: _form.proxyType == 'proxyServer',
                              onSelected: (_) => setState(() {
                                _form.proxyType = 'proxyServer';
                                _form.jumpHosts = const [];
                              }),
                            ),
                            ChoiceChip(
                              label: Text(l.tr('servers.proxy.jumpHosts')),
                              selected: _form.proxyType == 'jumpHosts',
                              onSelected: (_) => setState(() {
                                _form.proxyType = 'jumpHosts';
                              }),
                            ),
                          ],
                        ),
                      ),
                      if (_form.proxyType == 'jumpHosts') ...[
                        const SizedBox(height: 12),
                        _JumpHostSelector(
                          options: jumpHostOptions,
                          selectedIds: _form.jumpHosts,
                          onChanged: (ids) => setState(() {
                            _form.jumpHosts = ids;
                          }),
                        ),
                      ],
                      if (_form.proxyType == 'proxyServer') ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l.tr('servers.proxyServerUnsupported'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    _TextField(
                      controller: _consoleUrlCtrl,
                      label: l.tr('servers.field.consoleUrl'),
                    ),
                    const SizedBox(height: 12),
                    _TextField(
                      controller: _tagsCtrl,
                      label: l.tr('servers.field.tags'),
                      helperText: l.tr('servers.tagsHint'),
                    ),
                    const SizedBox(height: 12),
                    _TextField(
                      controller: _commandCtrl,
                      label: l.tr('servers.field.command'),
                      minLines: 3,
                      maxLines: 5,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_form.isEdit ? l.tr('common.save') : l.tr('servers.addServer')),
            ),
          ],
        ),
      ),
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
      await ref.read(hostListProvider.notifier).refresh();
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

class _Section extends StatelessWidget {
  const _Section({
    required this.children,
    this.title,
    this.padding = const EdgeInsets.all(12),
  });

  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
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
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? minLines;
  final int? maxLines;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      minLines: obscureText ? 1 : minLines,
      maxLines: obscureText ? 1 : maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _JumpHostSelector extends StatelessWidget {
  const _JumpHostSelector({
    required this.options,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<ServerModel> options;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final selectedHosts = <ServerModel>[];
    for (final id in selectedIds) {
      for (final host in options) {
        if (host.id == id) {
          selectedHosts.add(host);
          break;
        }
      }
    }
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: options.isEmpty ? null : () => _showPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l.tr('servers.field.jumpHosts'),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          helperText: options.isEmpty
              ? l.tr('servers.jumpHosts.empty')
              : l.tr('servers.jumpHosts.orderHint'),
        ),
        child: selectedHosts.isEmpty
            ? Text(
                l.tr('servers.jumpHosts.placeholder'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < selectedHosts.length; i++)
                    InputChip(
                      label: Text('${i + 1}. ${selectedHosts[i].displayName}'),
                      onDeleted: () {
                        final next = [...selectedIds]..remove(selectedHosts[i].id);
                        onChanged(next);
                      },
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final next = [...selectedIds];
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final l = AppLocalizations.of(context);
          final colors = Theme.of(context).colorScheme;
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: colors.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final host = options[index];
                      final selected = next.contains(host.id);
                      final order = next.indexOf(host.id) + 1;
                      return CheckboxListTile(
                        value: selected,
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
                                child: Text('$order'),
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
