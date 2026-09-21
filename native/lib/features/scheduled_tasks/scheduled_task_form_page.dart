import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/host_list_notifier.dart';
import '../../state/scheduled_task_notifier.dart';
import '../../state/script_list_notifier.dart';
import '../scripts/script_model.dart';
import '../servers/server_model.dart';
import 'scheduled_task_models.dart';

class ScheduledTaskFormPage extends ConsumerStatefulWidget {
  const ScheduledTaskFormPage({super.key, this.task});

  final ScheduledTask? task;

  @override
  ConsumerState<ScheduledTaskFormPage> createState() =>
      _ScheduledTaskFormPageState();
}

class _ScheduledTaskFormPageState extends ConsumerState<ScheduledTaskFormPage> {
  static const _maxScriptBytes = 256 * 1024;
  static const _timezones = [
    'Asia/Shanghai',
    'UTC',
    'Asia/Hong_Kong',
    'Asia/Tokyo',
    'Europe/London',
    'America/New_York',
  ];
  static const _cronSuggestions = <(String, String)>[
    ('scheduledTasks.cron.everyMinute', '* * * * *'),
    ('scheduledTasks.cron.every30Minutes', '*/30 * * * *'),
    ('scheduledTasks.cron.hourly', '0 * * * *'),
    ('scheduledTasks.cron.dailyNoon', '0 12 * * *'),
    ('scheduledTasks.cron.dailyMidnight', '0 0 * * *'),
    ('scheduledTasks.cron.monday', '0 0 * * 1'),
    ('scheduledTasks.cron.monthly', '0 0 1 * *'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cronController = TextEditingController();
  final _commandController = TextEditingController();
  late ScheduledTaskFormData _form;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _form = widget.task == null
        ? ScheduledTaskFormData.create()
        : ScheduledTaskFormData.fromTask(widget.task!);
    _nameController.text = _form.name;
    _cronController.text = _form.cron;
    _commandController.text = _form.script.command;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cronController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final l = AppLocalizations.of(context);
    if (_form.hostIds.isEmpty) {
      _showError(l.tr('scheduledTasks.validation.hosts'));
      return;
    }
    final script = _form.script.isLibrary
        ? ScheduledTaskScript(type: 'library', scriptId: _form.script.scriptId)
        : ScheduledTaskScript(
            type: 'inline',
            command: _commandController.text,
            useBase64: _form.script.useBase64,
          );
    if (script.isLibrary && script.scriptId.isEmpty) {
      _showError(l.tr('scheduledTasks.validation.libraryScript'));
      return;
    }
    setState(() => _saving = true);
    try {
      _form
        ..name = _nameController.text.trim()
        ..cron = _cronController.text.trim()
        ..script = script;
      await ref.read(scheduledTaskListProvider.notifier).save(_form);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectHosts(
    List<ServerModel> hosts,
    Set<String> selectableIds,
  ) async {
    final selected = {..._form.hostIds};
    final options = hosts
        .where(
          (host) =>
              selectableIds.contains(host.id) || selected.contains(host.id),
        )
        .map(
          (host) => _TaskHostOption(
            id: host.id,
            name: host.displayName,
            connectionLabel: host.connectionLabel,
            selectable: selectableIds.contains(host.id),
          ),
        )
        .toList();
    final knownIds = hosts.map((host) => host.id).toSet();
    options.addAll(
      selected
          .where((id) => !knownIds.contains(id))
          .map(
            (id) => _TaskHostOption(
              id: id,
              name: id,
              connectionLabel: '',
              selectable: false,
            ),
          ),
    );
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final l = AppLocalizations.of(context);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.tr('scheduledTasks.selectHosts'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, selected),
                          child: Text(l.tr('common.confirm')),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final isSelected = selected.contains(option.id);
                        final unavailable = l.tr(
                          'scheduledTasks.hostUnavailable',
                        );
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(option.name),
                          subtitle: Text(
                            option.selectable
                                ? option.connectionLabel
                                : option.connectionLabel.isEmpty
                                ? unavailable
                                : '$unavailable - ${option.connectionLabel}',
                          ),
                          onChanged: option.selectable || isSelected
                              ? (checked) => setModalState(() {
                                  if (checked == true) {
                                    selected.add(option.id);
                                  } else {
                                    selected.remove(option.id);
                                  }
                                })
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null) setState(() => _form.hostIds = result.toList());
  }

  Future<ScriptModel?> _pickScript(List<ScriptModel> scripts, String title) {
    return showModalBottomSheet<ScriptModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: scripts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final script = scripts[index];
                    return ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text(script.name),
                      subtitle: script.description.isEmpty
                          ? null
                          : Text(
                              script.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.pop(context, script),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importScript(List<ScriptModel> scripts) async {
    final l = AppLocalizations.of(context);
    final selected = await _pickScript(
      scripts,
      l.tr('scheduledTasks.importScript'),
    );
    if (selected == null) return;
    setState(() {
      _commandController.text = selected.command;
      _form.script = ScheduledTaskScript(
        type: 'inline',
        command: selected.command,
        useBase64: selected.useBase64,
      );
    });
  }

  Future<void> _referenceScript(List<ScriptModel> scripts) async {
    final l = AppLocalizations.of(context);
    final selected = await _pickScript(
      scripts,
      l.tr('scheduledTasks.referenceScript'),
    );
    if (selected == null) return;
    setState(() {
      _form.script = ScheduledTaskScript(
        type: 'library',
        scriptId: selected.id,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final allHosts =
        ref.watch(hostListProvider).valueOrNull ?? const <ServerModel>[];
    final hosts = allHosts
        .where((host) => host.canConnect && !host.isWindows)
        .toList(growable: false);
    final selectableHostIds = hosts.map((host) => host.id).toSet();
    final allHostsById = {for (final host in allHosts) host.id: host};
    final scripts =
        ref.watch(scriptListProvider).valueOrNull ?? const <ScriptModel>[];
    final scriptById = {for (final script in scripts) script.id: script};
    final timezones = _timezones.contains(_form.timezone)
        ? _timezones
        : [_form.timezone, ..._timezones];
    final selectedHostLabels = _form.hostIds
        .map((id) => allHostsById[id]?.displayName ?? id)
        .toList(growable: false);
    final commandBytes = utf8.encode(_commandController.text).length;
    final editing = _form.isEdit;

    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        backgroundColor: context.colors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          editing
              ? l.tr('scheduledTasks.editTask')
              : l.tr('scheduledTasks.addTask'),
        ),
      ),
      bottomNavigationBar: _BottomSaveBar(
        saving: _saving,
        label: l.tr('common.save'),
        onPressed: _saving ? null : _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _CardSection(
              title: l.tr('scheduledTasks.section.basic'),
              children: [
                _TextField(
                  controller: _nameController,
                  label: l.tr('scheduledTasks.field.name'),
                  maxLength: 100,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? l.tr('scheduledTasks.validation.name')
                      : null,
                ),
                _PickerField(
                  label: l.tr('scheduledTasks.field.hosts'),
                  value: selectedHostLabels.join(', '),
                  placeholder: l.tr('scheduledTasks.selectHosts'),
                  leadingIcon: Icons.dns_outlined,
                  meta: selectedHostLabels.isEmpty
                      ? null
                      : l
                            .tr('scheduledTasks.hostCount')
                            .replaceFirst(
                              '{0}',
                              '${selectedHostLabels.length}',
                            ),
                  onTap: () => _selectHosts(allHosts, selectableHostIds),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CardSection(
              title: l.tr('scheduledTasks.section.schedule'),
              children: [
                _LabeledBlock(
                  label: l.tr('scheduledTasks.field.cron'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _cronController,
                        style: TextStyle(
                          color: context.colors.text,
                          fontSize: 15,
                          fontFamily: 'monospace',
                        ),
                        decoration: _fieldDecoration(context),
                        validator: (value) {
                          if ((value ?? '')
                                  .trim()
                                  .split(RegExp(r'\s+'))
                                  .length !=
                              5) {
                            return l.tr('scheduledTasks.validation.cron');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final suggestion in _cronSuggestions)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: context.colors.chip,
                              side: BorderSide(color: context.colors.border),
                              label: Text(l.tr(suggestion.$1)),
                              onPressed: () => setState(
                                () => _cronController.text = suggestion.$2,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DropdownField<String>(
                        label: l.tr('scheduledTasks.field.timezone'),
                        value: _form.timezone,
                        items: [
                          for (final timezone in timezones)
                            DropdownMenuItem(
                              value: timezone,
                              child: Text(
                                timezone,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _form.timezone = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 116,
                      child: _InitialTextField(
                        initialValue: _form.timeoutSeconds.toString(),
                        label: l.tr('scheduledTasks.field.timeout'),
                        keyboardType: TextInputType.number,
                        mono: true,
                        validator: (value) {
                          final number = int.tryParse(value ?? '');
                          if (number == null || number < 1 || number > 1800) {
                            return l.tr('scheduledTasks.validation.timeout');
                          }
                          _form.timeoutSeconds = number;
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CardSection(
              title: l.tr('scheduledTasks.section.command'),
              children: [
                _ScriptTypeSegment(
                  value: _form.script.type,
                  inlineLabel: l.tr('scheduledTasks.inlineScript'),
                  libraryLabel: l.tr('scheduledTasks.referenceScript'),
                  onChanged: (type) => setState(() {
                    _form.script = type == 'library'
                        ? const ScheduledTaskScript(type: 'library')
                        : ScheduledTaskScript(
                            type: 'inline',
                            command: _commandController.text,
                            useBase64: _form.script.useBase64,
                          );
                  }),
                ),
                if (_form.script.isLibrary)
                  _PickerField(
                    label: l.tr('scheduledTasks.referenceScript'),
                    value: scriptById[_form.script.scriptId]?.name ?? '',
                    placeholder: l.tr('scheduledTasks.selectScript'),
                    leadingIcon: Icons.article_outlined,
                    onTap: () => _referenceScript(scripts),
                  )
                else ...[
                  _LabeledBlock(
                    label: l.tr('scheduledTasks.field.command'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: scripts.isEmpty
                                  ? null
                                  : () => _importScript(scripts),
                              icon: const Icon(
                                Icons.file_download_outlined,
                                size: 18,
                              ),
                              label: Text(l.tr('scheduledTasks.importScript')),
                            ),
                            Text(
                              '${(commandBytes / 1024).toStringAsFixed(1)} / 256 KiB',
                              style: TextStyle(
                                color: commandBytes > _maxScriptBytes
                                    ? context.colors.danger
                                    : context.colors.softMuted,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _commandController,
                          minLines: 10,
                          maxLines: 18,
                          style: TextStyle(
                            color: context.colors.text,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: _fieldDecoration(
                            context,
                            hintText: l.tr('scheduledTasks.commandHint'),
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return l.tr('scheduledTasks.validation.command');
                            }
                            if (utf8.encode(value!).length > _maxScriptBytes) {
                              return l.tr(
                                'scheduledTasks.validation.commandSize',
                              );
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  _SwitchRow(
                    label: l.tr('scheduledTasks.base64Script'),
                    value: _form.script.useBase64,
                    onChanged: (value) => setState(() {
                      _form.script = ScheduledTaskScript(
                        type: 'inline',
                        command: _commandController.text,
                        useBase64: value,
                      );
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _CardSection(
              title: l.tr('scheduledTasks.section.runtime'),
              children: [
                _DropdownField<String>(
                  label: l.tr('scheduledTasks.field.notification'),
                  value: _form.notificationPolicy,
                  items: [
                    DropdownMenuItem(
                      value: 'failure',
                      child: Text(l.tr('scheduledTasks.notification.failure')),
                    ),
                    DropdownMenuItem(
                      value: 'always',
                      child: Text(l.tr('scheduledTasks.notification.always')),
                    ),
                    DropdownMenuItem(
                      value: 'never',
                      child: Text(l.tr('scheduledTasks.notification.never')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _form.notificationPolicy = value);
                    }
                  },
                ),
                _SwitchRow(
                  label: l.tr('scheduledTasks.enabled'),
                  value: _form.enabled,
                  onChanged: (value) => setState(() => _form.enabled = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskHostOption {
  const _TaskHostOption({
    required this.id,
    required this.name,
    required this.connectionLabel,
    required this.selectable,
  });

  final String id;
  final String name;
  final String connectionLabel;
  final bool selectable;
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.leadingIcon,
    this.meta,
  });

  final String label;
  final String value;
  final String placeholder;
  final VoidCallback onTap;
  final IconData? leadingIcon;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return _LabeledBlock(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: InputDecorator(
          decoration: _fieldDecoration(context),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 18, color: context.colors.primary),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  value.isEmpty ? placeholder : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: value.isEmpty
                        ? context.colors.softMuted
                        : context.colors.text,
                    fontSize: 15,
                  ),
                ),
              ),
              if (meta != null) ...[
                const SizedBox(width: 8),
                _MetaPill(label: meta!),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down,
                color: context.colors.softMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
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
                    color: context.colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
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

class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.colors.softMuted,
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
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return _LabeledBlock(
      label: label,
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        validator: validator,
        style: TextStyle(color: context.colors.text, fontSize: 15),
        decoration: _fieldDecoration(
          context,
          counterText: maxLength == null ? null : '',
        ),
      ),
    );
  }
}

class _InitialTextField extends StatelessWidget {
  const _InitialTextField({
    required this.initialValue,
    required this.label,
    this.validator,
    this.keyboardType,
    this.mono = false,
  });

  final String initialValue;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return _LabeledBlock(
      label: label,
      child: TextFormField(
        initialValue: initialValue,
        validator: validator,
        keyboardType: keyboardType,
        style: TextStyle(
          color: context.colors.text,
          fontSize: 15,
          fontFamily: mono ? 'monospace' : null,
        ),
        decoration: _fieldDecoration(context),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _LabeledBlock(
      label: label,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: _fieldDecoration(context),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _ScriptTypeSegment extends StatelessWidget {
  const _ScriptTypeSegment({
    required this.value,
    required this.inlineLabel,
    required this.libraryLabel,
    required this.onChanged,
  });

  final String value;
  final String inlineLabel;
  final String libraryLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.chip,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              selected: value == 'inline',
              icon: Icons.code,
              label: inlineLabel,
              onTap: () => onChanged('inline'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentButton(
              selected: value == 'library',
              icon: Icons.link,
              label: libraryLabel,
              onTap: () => onChanged('library'),
            ),
          ),
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
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.colors.fontOnPrimary
        : context.colors.muted;
    return Material(
      color: selected ? context.colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
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
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: context.colors.fontOnPrimary,
          activeTrackColor: context.colors.primary,
          onChanged: onChanged,
        ),
      ],
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
        color: context.colors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: context.colors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
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

InputDecoration _fieldDecoration(
  BuildContext context, {
  String? hintText,
  String? counterText,
}) {
  return InputDecoration(
    filled: true,
    fillColor: context.colors.chip,
    hintText: hintText,
    counterText: counterText,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.colors.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.colors.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.colors.danger, width: 1.6),
    ),
  );
}
