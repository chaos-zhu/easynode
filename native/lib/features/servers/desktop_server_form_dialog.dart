import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api/api_result.dart';
import '../../core/platform/desktop_ssh_directory.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_popover.dart';
import '../../core/ui/desktop_select.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/credential_list_notifier.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/proxy_list_notifier.dart';
import 'server_form_data.dart';
import 'server_model.dart';
import 'server_repository.dart';

class DesktopServerFormDialog extends ConsumerStatefulWidget {
  const DesktopServerFormDialog({
    super.key,
    required this.catalog,
    this.server,
  });

  final HostCatalog catalog;
  final ServerModel? server;

  @override
  ConsumerState<DesktopServerFormDialog> createState() =>
      _DesktopServerFormDialogState();
}

class _DesktopServerFormDialogState
    extends ConsumerState<DesktopServerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _tagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  late final ServerFormData _form;
  late final String _initialAuthType;
  bool _saving = false;
  bool _advancedOpen = false;
  bool _tagsFocused = false;
  String? _error;

  AppLocalizations get l => AppLocalizations.of(context);
  TextEditingController _ctrl(String name) => _controllers[name]!;

  @override
  void initState() {
    super.initState();
    _form = widget.server == null
        ? ServerFormData.add()
        : ServerFormData.edit(widget.server!);
    if (_form.isRdp) _form.authType = 'password';
    _initialAuthType = _form.authType;
    for (final entry in {
      'name': _form.name,
      'host': _form.host,
      'port': '${_form.port}',
      'username': _form.username,
      'password': '',
      'privateKey': '',
      'consoleUrl': _form.consoleUrl,
      'command': _form.command,
    }.entries) {
      _controllers[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _tagController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  InputDecoration _decoration({String? hint, String? helper}) =>
      desktopInputDecoration(context, hint: hint, helper: helper);

  Widget _field(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: context.colors.muted,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );

  Widget _pair(Widget left, Widget right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 14),
      Expanded(child: right),
    ],
  );

  Widget _text(
    String name, {
    bool required = false,
    bool autofocus = false,
    int lines = 1,
    String? hint,
    String? helper,
    Widget? leading,
  }) => _field(
    l.tr('servers.field.$name'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leading != null) ...[leading, const SizedBox(height: 5)],
        TextFormField(
          key: ValueKey('desktop-server-form-$name'),
          controller: _ctrl(name),
          autofocus: autofocus,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: name == 'password',
          maxLines: lines,
          style: TextStyle(fontSize: 13, height: lines > 1 ? 1.55 : 1.3),
          keyboardType: name == 'port'
              ? TextInputType.number
              : TextInputType.text,
          decoration: _decoration(
            hint:
                _form.isEdit &&
                    _initialAuthType == _form.authType &&
                    (name == 'password' || name == 'privateKey')
                ? l.tr('servers.secretEditHint')
                : hint,
            helper: helper,
          ),
          validator: (value) {
            if (required && (value == null || value.trim().isEmpty)) {
              return l.tr('servers.validation.$name');
            }
            if (name == 'port') {
              final port = int.tryParse(value?.trim() ?? '');
              if (port == null || port < 1 || port > 65535) {
                return l.tr('desktop.servers.form.portRange');
              }
            }
            if ((name == 'password' || name == 'privateKey') &&
                _form.isEdit &&
                _initialAuthType != _form.authType &&
                (value == null || value.trim().isEmpty)) {
              return l.tr('desktop.servers.form.secretRequired');
            }
            return null;
          },
        ),
      ],
    ),
  );

  Widget _select({
    required String name,
    required String value,
    required Map<String, String> options,
    Map<String, String> descriptions = const {},
    required ValueChanged<String> onChanged,
    bool enabled = true,
  }) => _field(
    l.tr('servers.field.$name'),
    FormField<String>(
      key: ValueKey('desktop-server-select-$name'),
      initialValue: options.containsKey(value) ? value : null,
      validator: (value) => value == null || !options.containsKey(value)
          ? l.tr('servers.validation.$name')
          : null,
      builder: (field) => DesktopSelect(
        options: options,
        descriptions: descriptions,
        values: options.containsKey(value) ? [value] : const [],
        placeholder: l.tr('desktop.form.selectPlaceholder'),
        enabled: enabled,
        errorText: field.errorText,
        onSelected: (value) {
          field.didChange(value);
          onChanged(value);
        },
      ),
    ),
  );

  Widget _choices(
    String value,
    Map<String, String> labels,
    ValueChanged<String> onChanged, {
    Set<String> disabled = const {},
  }) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: desktopFormControlHeight),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 22,
        runSpacing: 6,
        children: [
          for (final option in labels.entries)
            Tooltip(
              message: disabled.contains(option.key)
                  ? l.tr('plus.serverManagedTip')
                  : '',
              child: Semantics(
                checked: value == option.key,
                inMutuallyExclusiveGroup: true,
                child: TextButton(
                  onPressed: disabled.contains(option.key)
                      ? null
                      : () => onChanged(option.key),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: value == option.key
                        ? context.colors.accent
                        : context.colors.text,
                    disabledForegroundColor: context.colors.softMuted,
                    overlayColor: context.colors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    splashFactory: NoSplash.splashFactory,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value == option.key
                              ? context.colors.accent
                              : context.colors.card,
                          border: Border.all(
                            color: value == option.key
                                ? context.colors.accent
                                : context.colors.strongBorder,
                          ),
                          boxShadow: value == option.key
                              ? [
                                  BoxShadow(
                                    color: context.colors.accentSoft,
                                    spreadRadius: 3,
                                  ),
                                ]
                              : null,
                        ),
                        child: value == option.key
                            ? Center(
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: context.colors.fontOnPrimary,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 7),
                      Text(option.value),
                      if (option.key == 'ssh' || option.key == 'rdp') ...[
                        const SizedBox(width: 4),
                        SvgPicture.asset(
                          option.key == 'ssh'
                              ? 'assets/linux.svg'
                              : 'assets/windows.svg',
                          width: 14,
                          height: 14,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _loadFailure(VoidCallback retry) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            l.tr('desktop.servers.form.optionsFailed'),
            style: TextStyle(color: context.colors.danger, fontSize: 13),
          ),
        ),
        TextButton(onPressed: retry, child: Text(l.tr('common.retry'))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final plus = ref.watch(plusInfoProvider);
    final plusActive = plus.valueOrNull?.isActive ?? false;
    final groups = {
      for (final group in widget.catalog.groups)
        group.id: group.isDefault
            ? l.tr('servers.defaultGroup')
            : group.displayName,
    };
    if (!groups.containsKey('default')) {
      groups['default'] = l.tr('servers.defaultGroup');
    }
    return DesktopManagementDialog(
      topAligned: true,
      title: l.tr(
        _form.isEdit ? 'desktop.servers.edit' : 'desktop.servers.add',
      ),
      busy: _saving,
      body: AbsorbPointer(
        absorbing: _saving,
        child: FocusScope(
          canRequestFocus: !_saving,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (plus.hasError)
                  _loadFailure(() => ref.invalidate(plusInfoProvider)),
                _field(
                  l.tr('desktop.servers.form.connectType'),
                  _choices(
                    _form.connectType,
                    const {'ssh': 'SSH', 'rdp': 'RDP'},
                    _changeConnectType,
                    disabled: plusActive ? const {} : {'rdp'},
                  ),
                ),
                _pair(
                  _text(
                    'name',
                    required: true,
                    autofocus: true,
                    hint: l.tr('desktop.servers.form.nameHint'),
                  ),
                  _select(
                    name: 'group',
                    value: _form.group,
                    options: groups,
                    onChanged: (value) => setState(() => _form.group = value),
                  ),
                ),
                _pair(
                  _text('host', required: true, hint: 'IP'),
                  _text('port', required: true),
                ),
                _pair(
                  _text('username'),
                  _form.isSsh
                      ? _field(
                          l.tr('servers.field.authType'),
                          _choices(
                            _form.authType,
                            {
                              for (final type in [
                                'password',
                                'privateKey',
                                'credential',
                              ])
                                type: l.tr('servers.auth.$type'),
                            },
                            (value) => setState(() => _form.authType = value),
                          ),
                        )
                      : _text('password'),
                ),
                if (_form.isSsh) _authentication(),
                Container(
                  decoration: BoxDecoration(
                    color: context.colors.canvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () =>
                            setState(() => _advancedOpen = !_advancedOpen),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 42),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.tr('servers.advanced'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                _advancedOpen
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Offstage(
                        offstage: !_advancedOpen,
                        child: ExcludeFocus(
                          excluding: !_advancedOpen,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            padding: const EdgeInsets.only(top: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: context.colors.border.withValues(
                                    alpha: .6,
                                  ),
                                ),
                              ),
                            ),
                            child: _advanced(plusActive),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.tr('common.cancel')),
        ),
        FilledButton(
          key: const Key('desktop-server-form-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  l.tr(
                    _form.isEdit
                        ? 'desktop.servers.form.saveChanges'
                        : 'desktop.servers.form.create',
                  ),
                ),
        ),
      ],
    );
  }

  Widget _authentication() {
    if (_form.authType == 'credential') {
      return ref
          .watch(credentialListProvider)
          .when(
            loading: () => const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            ),
            error: (_, _) =>
                _loadFailure(() => ref.invalidate(credentialListProvider)),
            data: (items) => _select(
              name: 'credential',
              value: _form.credential,
              options: {for (final item in items) item.id: item.displayName},
              descriptions: {
                for (final item in items)
                  item.id: l.tr('servers.auth.${item.authType}'),
              },
              onChanged: (value) => setState(() => _form.credential = value),
            ),
          );
    }
    if (_form.authType == 'privateKey') {
      return _text(
        'privateKey',
        lines: 3,
        hint: '-----BEGIN RSA PRIVATE KEY-----',
        helper: _form.isEdit ? null : l.tr('desktop.servers.form.keyHint'),
        leading: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('desktop-server-import-key'),
            onPressed: _importPrivateKey,
            style: desktopButtonStyle(context, primary: true).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
            ),
            icon: const Icon(Icons.upload_file, size: 14),
            label: Text(l.tr('desktop.servers.form.importKey')),
          ),
        ),
      );
    }
    return _text('password');
  }

  Widget _advanced(bool plusActive) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_form.isSsh) ...[
        _field(
          l.tr('servers.field.proxyType'),
          _choices(
            _form.proxyType,
            {
              '': l.tr('servers.proxy.none'),
              'proxyServer': l.tr('servers.proxy.proxyServer'),
              'jumpHosts': l.tr('servers.proxy.jumpHosts'),
            },
            (value) => setState(() {
              _form.proxyType = value;
              _form.jumpHosts = [];
              _form.proxyServer = '';
            }),
            disabled: plusActive ? const {} : {'proxyServer', 'jumpHosts'},
          ),
        ),
        if (_form.proxyType == 'proxyServer')
          ref
              .watch(proxyListProvider)
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                ),
                error: (_, _) =>
                    _loadFailure(() => ref.invalidate(proxyListProvider)),
                data: (items) => _select(
                  name: 'proxyServer',
                  value: _form.proxyServer,
                  options: {
                    for (final item in items) item.id: item.displayName,
                  },
                  descriptions: {
                    for (final item in items) item.id: item.typeLabel,
                  },
                  enabled: plusActive,
                  onChanged: (value) =>
                      setState(() => _form.proxyServer = value),
                ),
              ),
        if (_form.proxyType == 'jumpHosts') _jumpHosts(plusActive),
        _text(
          'command',
          lines: 3,
          hint: l.tr('desktop.servers.form.commandHint'),
        ),
      ],
      _field(
        l.tr('servers.field.expired'),
        Builder(
          builder: (anchorContext) => TextButton(
            key: const Key('desktop-server-expiry'),
            onPressed: () => _pickExpiry(anchorContext),
            style: desktopInputButtonStyle(context),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 15,
                  color: context.colors.softMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _form.expired == null
                        ? l.tr('desktop.servers.form.pickDate')
                        : MaterialLocalizations.of(
                            context,
                          ).formatCompactDate(_form.expired!),
                    style: TextStyle(
                      color: _form.expired == null
                          ? context.colors.softMuted
                          : context.colors.text,
                    ),
                  ),
                ),
                if (_form.expired != null)
                  IconButton(
                    tooltip: l.tr('desktop.servers.form.clearDate'),
                    onPressed: () => setState(() {
                      _form.expired = null;
                      _form.expiredNotify = false;
                    }),
                    icon: const Icon(Icons.close, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 20,
                      height: 20,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      if (_form.expired != null)
        _field(
          l.tr('servers.field.expiredNotify'),
          Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: l.tr('desktop.servers.form.expiryHint'),
              child: Semantics(
                toggled: _form.expiredNotify,
                label: l.tr('servers.field.expiredNotify'),
                child: TextButton(
                  key: const Key('desktop-server-expiry-notify'),
                  onPressed: () => setState(
                    () => _form.expiredNotify = !_form.expiredNotify,
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(40, 28),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    width: 40,
                    height: 20,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _form.expiredNotify
                          ? context.colors.accent
                          : context.colors.strongBorder,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AnimatedAlign(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      alignment: _form.expiredNotify
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      _text('consoleUrl', hint: l.tr('desktop.servers.form.consoleHint')),
      _tags(),
    ],
  );

  Widget _jumpHosts(bool enabled) {
    final options = {
      for (final host in widget.catalog.hosts.where(
        (host) => host.isConfig && !host.isWindows && host.id != _form.id,
      ))
        host.id: host.displayName,
    };
    return _field(
      l.tr('servers.field.jumpHosts'),
      FormField<List<String>>(
        initialValue: _form.jumpHosts,
        validator: (_) =>
            _form.jumpHosts.isEmpty ||
                _form.jumpHosts.any((id) => !options.containsKey(id))
            ? l.tr('servers.validation.jumpHosts')
            : null,
        builder: (field) => DesktopSelect(
          options: options,
          values: _form.jumpHosts,
          enabled: enabled,
          placeholder: l.tr('servers.jumpHosts.placeholder'),
          helperText: l.tr('servers.jumpHosts.orderHint'),
          errorText: field.errorText,
          onSelected: (value) => setState(() {
            _form.jumpHosts = [..._form.jumpHosts, value];
            field.didChange(_form.jumpHosts);
          }),
          onRemoved: (value) => setState(() {
            _form.jumpHosts = [..._form.jumpHosts]..remove(value);
            field.didChange(_form.jumpHosts);
          }),
        ),
      ),
    );
  }

  Widget _tags() => _field(
    l.tr('servers.field.tags'),
    Focus(
      onFocusChange: (focused) => setState(() => _tagsFocused = focused),
      child: InputDecorator(
        isFocused: _tagsFocused,
        isEmpty: _form.tag.isEmpty && _tagController.text.isEmpty,
        decoration: _decoration().copyWith(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final tag in _form.tag)
                    DesktopFormTag(
                      label: tag,
                      color: context.colors.success,
                      onRemove: () => setState(
                        () => _form.tag = [..._form.tag]..remove(tag),
                      ),
                    ),
                  SizedBox(
                    width: 200,
                    child: Focus(
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent ||
                            (event.logicalKey != LogicalKeyboardKey.enter &&
                                event.logicalKey !=
                                    LogicalKeyboardKey.numpadEnter) ||
                            !_tagController.value.composing.isCollapsed) {
                          return KeyEventResult.ignored;
                        }
                        _createTags();
                        return KeyEventResult.handled;
                      },
                      child: TextField(
                        key: const Key('desktop-server-form-tags'),
                        controller: _tagController,
                        focusNode: _tagFocusNode,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                        onEditingComplete: () {},
                        onSubmitted: (_) => _createTags(),
                        decoration: InputDecoration(
                          hintText: l.tr('servers.tagsHint'),
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: context.colors.softMuted,
                          ),
                          isDense: true,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 5,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const Key('desktop-server-add-tag'),
              tooltip: l.tr('common.add'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _createTags,
              icon: const Icon(Icons.add, size: 16),
            ),
          ],
        ),
      ),
    ),
  );

  void _createTags() {
    setState(_commitTags);
    _tagFocusNode.requestFocus();
  }

  void _commitTags() {
    _form.tag = {
      ..._form.tag,
      ..._tagController.text
          .split(RegExp('[,，]'))
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty),
    }.toList();
    _tagController.clear();
  }

  void _changeConnectType(String type) => setState(() {
    _form.connectType = type;
    if (type == 'rdp') _form.authType = 'password';
    if (!_form.isEdit) {
      _ctrl('port').text = type == 'rdp' ? '3389' : '22';
      _ctrl('username').text = type == 'rdp' ? 'Administrator' : 'root';
    }
  });

  Future<void> _importPrivateKey() async {
    final FilePickerResult? result;
    try {
      // Read the selected path ourselves so picker and file errors stay distinct.
      result = await FilePicker.pickFiles(
        initialDirectory: await getDesktopSshDirectory(),
      );
    } on PlatformException catch (error) {
      _keyImportError(
        error.code.startsWith('ENTITLEMENT_')
            ? 'desktop.servers.form.filePermissionFailed'
            : 'desktop.servers.form.filePickerFailed',
      );
      return;
    } catch (_) {
      _keyImportError('desktop.servers.form.filePickerFailed');
      return;
    }
    if (result == null || !mounted) return;
    try {
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final key = utf8.decode(bytes);
      if (!mounted) return;
      setState(() {
        _ctrl('privateKey').text = key;
        _error = null;
      });
    } on FormatException {
      _keyImportError('desktop.servers.form.keyEncodingFailed');
    } catch (_) {
      _keyImportError('desktop.servers.form.keyReadFailed');
    }
  }

  void _keyImportError(String key) {
    if (mounted) setState(() => _error = l.tr(key));
  }

  Future<void> _pickExpiry(BuildContext anchorContext) async {
    final date = await showDesktopPopover<DateTime>(
      context: anchorContext,
      width: 336,
      maxHeight: 370,
      builder: (context) => SingleChildScrollView(
        child: CalendarDatePicker(
          initialDate: _form.expired ?? DateTime.now(),
          firstDate: DateTime(1970),
          lastDate: DateTime(2200),
          onDateChanged: (date) => Navigator.of(context).pop(date),
        ),
      ),
    );
    if (date != null && mounted) setState(() => _form.expired = date);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) {
      setState(() => _advancedOpen = true);
      return;
    }
    // Use configuration lists, without fetching SSH connection secrets.
    if ((_form.authType == 'credential' &&
            ref.read(credentialListProvider).valueOrNull == null) ||
        (_form.isSsh &&
            _form.proxyType == 'proxyServer' &&
            ref.read(proxyListProvider).valueOrNull == null)) {
      setState(() {
        _error = l.tr('desktop.servers.form.optionsFailed');
        _advancedOpen = true;
      });
      return;
    }
    _commitTags();
    _form
      ..name = _ctrl('name').text
      ..host = _ctrl('host').text
      ..port = int.parse(_ctrl('port').text.trim())
      ..username = _ctrl('username').text
      ..password = _form.authType == 'password' ? _ctrl('password').text : ''
      ..privateKey = _form.authType == 'privateKey'
          ? _ctrl('privateKey').text
          : ''
      ..credential = _form.authType == 'credential' ? _form.credential : ''
      ..consoleUrl = _ctrl('consoleUrl').text
      ..command = _ctrl('command').text;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(serverRepositoryProvider);
      if (_form.isEdit) {
        await repository.updateHost(_form);
      } else {
        await repository.createHost(_form);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure
              ? error.message
              : l.tr('desktop.servers.form.saveFailed'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
