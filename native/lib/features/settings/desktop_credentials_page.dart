import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/desktop_text_files.dart';
import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../state/api_providers.dart';
import '../../state/credential_list_notifier.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../servers/server_credential_model.dart';

class DesktopCredentialsPage extends ConsumerStatefulWidget {
  const DesktopCredentialsPage({super.key});
  @override
  ConsumerState<DesktopCredentialsPage> createState() =>
      _DesktopCredentialsPageState();
}

class _DesktopCredentialsPageState
    extends ConsumerState<DesktopCredentialsPage> {
  bool _busy = false;
  String? _error;

  Future<void> _edit([ServerCredentialModel? credential]) async {
    final saved = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DesktopCredentialDialog(credential: credential),
    );
    if (saved == true) {
      ref.invalidate(credentialListProvider);
      ref.invalidate(desktopServerCatalogProvider);
    }
  }

  Future<void> _delete(ServerCredentialModel credential) async {
    if (!await managementConfirm(
          context,
          mx(
            context,
            '确认删除凭据：${credential.displayName}？',
            'Delete credential ${credential.displayName}?',
          ),
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(settingsRepositoryProvider)
          .deleteCredential(credential.id);
      ref.invalidate(credentialListProvider);
      ref.invalidate(desktopServerCatalogProvider);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(credentialListProvider);
    final items = state.valueOrNull ?? [];
    return ManagementPage(
      error: _error ?? (state.hasError ? managementError(state.error!) : null),
      busy: _busy || state.isLoading,
      toolbar: Row(
        children: [
          Expanded(
            child: Text(
              mx(
                context,
                '共 ${items.length} 个凭据',
                '${items.length} credentials',
              ),
              style: TextStyle(fontSize: 13, color: context.colors.muted),
            ),
          ),
          if (state.hasError)
            ManagementLink(
              label: mx(context, '重试', 'Retry'),
              onPressed: () => ref.invalidate(credentialListProvider),
            ),
          ManagementButton(
            key: const Key('credential-add'),
            label: mx(context, '添加凭据', 'Add credential'),
            icon: Icons.add,
            primary: true,
            onPressed: _busy ? null : () => _edit(),
          ),
        ],
      ),
      child: ManagementTable(
        empty: mx(context, '暂无凭据', 'No credentials'),
        columns: [
          ManagementColumn(mx(context, '名称', 'Name'), width: 280),
          ManagementColumn(mx(context, '类型', 'Type'), width: 160),
          ManagementColumn.actions(mx(context, '操作', 'Actions'), width: 140),
        ],
        rows: [
          for (final c in items)
            [
              Text(c.displayName),
              ManagementTag(
                c.isPrivateKey
                    ? mx(context, '密钥', 'Private key')
                    : mx(context, '密码', 'Password'),
                color: c.isPrivateKey
                    ? context.colors.accent
                    : context.colors.muted,
              ),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  ManagementLink(
                    key: ValueKey('credential-edit-${c.id}'),
                    label: mx(context, '编辑', 'Edit'),
                    onPressed: _busy ? null : () => _edit(c),
                  ),
                  if (c.id != 'default')
                    ManagementLink(
                      label: mx(context, '删除', 'Delete'),
                      danger: true,
                      onPressed: _busy ? null : () => _delete(c),
                    ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class DesktopCredentialDialog extends ConsumerStatefulWidget {
  const DesktopCredentialDialog({super.key, this.credential});
  final ServerCredentialModel? credential;
  @override
  ConsumerState<DesktopCredentialDialog> createState() =>
      _DesktopCredentialDialogState();
}

class _DesktopCredentialDialogState
    extends ConsumerState<DesktopCredentialDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.credential?.name ?? '');
  final _password = TextEditingController(),
      _key = TextEditingController(),
      _passphrase = TextEditingController();
  late String _type = widget.credential?.authType ?? 'privateKey';
  bool _saving = false, _reading = false, _visible = false;
  String? _error;
  bool get _edit => widget.credential != null;
  bool get _requiresSecret => !_edit || widget.credential!.authType != _type;
  @override
  void dispose() {
    for (final c in [_name, _password, _key, _passphrase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _upload() async {
    setState(() => _reading = true);
    try {
      final texts = await pickDesktopTextFiles(privateKey: true);
      if (!mounted || texts == null) return;
      setState(() {
        _key.text = texts.single;
        _error = null;
      });
      if (_key.text.contains('ENCRYPTED')) await _decrypt();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = mx(
            context,
            '无法读取私钥，请选择 UTF-8 文本文件，并检查文件访问权限。',
            'Cannot read the private key. Choose a UTF-8 file and check file access permissions.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _decrypt() async {
    final decrypted = await showAppDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DecryptKeyDialog(privateKey: _key.text),
    );
    if (mounted && decrypted != null) setState(() => _key.text = decrypted);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_type == 'privateKey' && _key.text.contains('ENCRYPTED')) {
      await _decrypt();
      if (!mounted || _key.text.contains('ENCRYPTED')) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(settingsRepositoryProvider);
      if (_edit) {
        await repo.updateCredential(
          id: widget.credential!.id,
          name: _name.text.trim(),
          authType: _type,
          password: _type == 'password' ? _password.text : '',
          privateKey: _type == 'privateKey' ? _key.text.trim() : '',
          openSSHKeyPassword: _type == 'privateKey' ? _passphrase.text : '',
        );
      } else {
        await repo.createCredential(
          name: _name.text.trim(),
          authType: _type,
          password: _type == 'password' ? _password.text : '',
          privateKey: _type == 'privateKey' ? _key.text.trim() : '',
          openSSHKeyPassword: _type == 'privateKey' ? _passphrase.text : '',
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    width: 560,
    topAligned: true,
    busy: _saving || _reading,
    title: _edit
        ? mx(context, '编辑凭据', 'Edit credential')
        : mx(context, '添加凭据', 'Add credential'),
    body: Form(
      key: _form,
      child: AbsorbPointer(
        absorbing: _saving || _reading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ManagementError(message: _error!),
            ManagementPair(
              left: ManagementField(
                label: mx(context, '凭据名称', 'Credential name'),
                child: TextFormField(
                  key: const Key('credential-name'),
                  controller: _name,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: desktopInputDecoration(
                    context,
                    hint: mx(
                      context,
                      '用于识别凭据',
                      'A name to identify this credential',
                    ),
                  ),
                  validator: (v) => v!.trim().isEmpty
                      ? mx(context, '请输入凭据名称', 'Enter a credential name')
                      : null,
                ),
              ),
              right: ManagementField(
                label: mx(context, '认证方式', 'Authentication'),
                child: ManagementChoices(
                  options: {
                    'privateKey': mx(context, '密钥', 'Private key'),
                    'password': mx(context, '密码', 'Password'),
                  },
                  value: _type,
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
            ),
            if (_type == 'privateKey')
              ManagementField(
                label: mx(context, '密钥', 'Private key'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ManagementButton(
                        label: mx(
                          context,
                          '选择本地私钥',
                          'Choose local private key',
                        ),
                        onPressed: _upload,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('credential-private-key'),
                      controller: _key,
                      minLines: 5,
                      maxLines: 8,
                      autocorrect: false,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      decoration: desktopInputDecoration(
                        context,
                        hint: _edit
                            ? mx(
                                context,
                                '留空将保留已保存的密钥',
                                'Leave blank to keep the saved key',
                              )
                            : '-----BEGIN RSA PRIVATE KEY-----',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => _requiresSecret && v!.trim().isEmpty
                          ? mx(context, '请输入私钥', 'Enter a private key')
                          : null,
                    ),
                    if (_key.text.contains('ENCRYPTED'))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ManagementLink(
                          label: mx(context, '解密密钥', 'Decrypt private key'),
                          onPressed: _decrypt,
                        ),
                      ),
                  ],
                ),
              ),
            if (_type == 'privateKey' &&
                _key.text.contains('OPENSSH PRIVATE KEY'))
              ManagementField(
                label: mx(context, '私钥密码', 'Key passphrase'),
                child: TextFormField(
                  controller: _passphrase,
                  obscureText: !_visible,
                  style: const TextStyle(fontSize: 13),
                  decoration:
                      desktopInputDecoration(
                        context,
                        hint: mx(
                          context,
                          '没有密码请留空',
                          'Leave blank if there is no passphrase',
                        ),
                      ).copyWith(
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _visible = !_visible),
                          icon: Icon(
                            _visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 17,
                          ),
                        ),
                      ),
                ),
              ),
            if (_type == 'password')
              ManagementField(
                label: mx(context, '密码', 'Password'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('credential-password'),
                      controller: _password,
                      obscureText: !_visible,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration:
                          desktopInputDecoration(
                            context,
                            hint: _edit
                                ? mx(
                                    context,
                                    '留空将保留已保存的密码',
                                    'Leave blank to keep the saved password',
                                  )
                                : mx(context, '输入密码', 'Enter password'),
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _visible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 17,
                              ),
                              onPressed: () =>
                                  setState(() => _visible = !_visible),
                            ),
                          ),
                      validator: (v) => _requiresSecret && v!.isEmpty
                          ? mx(context, '请输入密码', 'Enter password')
                          : null,
                    ),
                    if (_password.text.contains(' '))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          mx(context, '密码中包含空格字符', 'Password contains spaces'),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.warning,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      ManagementButton(
        label: mx(context, '取消', 'Cancel'),
        onPressed: _saving || _reading ? null : () => Navigator.pop(context),
      ),
      ManagementButton(
        label: _saving
            ? mx(context, '保存中…', 'Saving…')
            : _edit
            ? mx(context, '保存修改', 'Save changes')
            : mx(context, '创建凭据', 'Create credential'),
        primary: true,
        onPressed: _saving || _reading ? null : _save,
      ),
    ],
  );
}

class _DecryptKeyDialog extends ConsumerStatefulWidget {
  const _DecryptKeyDialog({required this.privateKey});
  final String privateKey;
  @override
  ConsumerState<_DecryptKeyDialog> createState() => _DecryptKeyDialogState();
}

class _DecryptKeyDialogState extends ConsumerState<_DecryptKeyDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiClientProvider).postJson(
        '/decrypt-private-key',
        {'privateKey': widget.privateKey, 'password': _password.text},
      );
      if (result['data'] is! String || (result['data'] as String).isEmpty) {
        throw StateError('Invalid private key response');
      }
      if (mounted) Navigator.pop(context, result['data']);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    width: 400,
    busy: _busy,
    title: mx(context, '输入密钥密码', 'Private key passphrase'),
    body: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ManagementError(message: _error!),
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          decoration: desktopInputDecoration(context),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      ManagementButton(
        label: mx(context, '取消', 'Cancel'),
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      ManagementButton(
        label: mx(context, '解密密钥', 'Decrypt key'),
        primary: true,
        onPressed: _busy ? null : _submit,
      ),
    ],
  );
}
