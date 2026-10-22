import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_select.dart';
import '../../state/api_providers.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../../state/plus_info_notifier.dart';
import '../../state/proxy_list_notifier.dart';
import '../servers/server_proxy_model.dart';
import 'desktop_settings_widgets.dart';

class DesktopProxySettings extends ConsumerStatefulWidget {
  const DesktopProxySettings({super.key});
  @override
  ConsumerState<DesktopProxySettings> createState() =>
      _DesktopProxySettingsState();
}

class _DesktopProxySettingsState extends ConsumerState<DesktopProxySettings> {
  final _visible = <String>{};
  bool _busy = false;
  String? _error;
  Future<void> _edit({ServerProxyModel? proxy, bool clone = false}) async {
    final saved = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      closeOnPressEscape: false,
      builder: (_) => DesktopProxyDialog(proxy: proxy, clone: clone),
    );
    if (saved == true) ref.invalidate(proxyListProvider);
  }

  Future<void> _delete(ServerProxyModel proxy) async {
    if (!await managementConfirm(
          context,
          mx(context, '确认删除代理「${proxy.name}」？', 'Delete proxy ${proxy.name}?'),
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(settingsRepositoryProvider).deleteProxy(proxy.id);
      ref.invalidate(proxyListProvider);
      ref.invalidate(desktopServerCatalogProvider);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(proxyListProvider);
    final proxies = state.valueOrNull ?? [];
    final plus = ref.watch(isPlusActiveProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: plus
                ? ''
                : mx(context, '代理服务需要 Plus', 'Proxy services require Plus'),
            child: ManagementButton(
              label: mx(context, '添加代理', 'Add proxy'),
              primary: true,
              icon: Icons.add,
              onPressed: plus && !_busy ? () => _edit() : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null || state.hasError)
          ManagementError(
            message: _error ?? managementError(state.error!),
            onRetry: () => ref.invalidate(proxyListProvider),
          ),
        if (state.isLoading || _busy)
          const LinearProgressIndicator(minHeight: 2),
        SizedBox(
          height: 440,
          child: ManagementTable(
            empty: mx(context, '暂无代理数据', 'No proxies'),
            columns: [
              ManagementColumn(mx(context, '类型', 'Type'), width: 100),
              ManagementColumn(mx(context, '名称', 'Name'), width: 130),
              ManagementColumn(mx(context, '主机', 'Host'), width: 150),
              ManagementColumn(mx(context, '端口', 'Port'), width: 70),
              ManagementColumn(mx(context, '用户名', 'Username'), width: 110),
              ManagementColumn(mx(context, '密码', 'Password'), width: 130),
              ManagementColumn(mx(context, '创建时间', 'Created'), width: 170),
              ManagementColumn.actions(
                mx(context, '操作', 'Actions'),
                width: 180,
              ),
            ],
            rows: [
              for (final p in proxies)
                [
                  ManagementTag(
                    p.typeLabel,
                    color: p.type == 'socks5'
                        ? context.colors.success
                        : context.colors.accent,
                  ),
                  Text(p.name),
                  Text(p.host),
                  Text('${p.port}'),
                  Text(p.username.isEmpty ? '—' : p.username),
                  InkWell(
                    onTap: () => setState(() {
                      if (!_visible.add(p.id)) _visible.remove(p.id);
                    }),
                    child: Text(
                      p.password.isEmpty
                          ? '—'
                          : _visible.contains(p.id)
                          ? p.password
                          : '••••••',
                    ),
                  ),
                  Text(
                    managementDate(
                      p.createTime == null
                          ? null
                          : DateTime.fromMillisecondsSinceEpoch(p.createTime!),
                    ),
                  ),
                  Row(
                    children: [
                      ManagementLink(
                        label: mx(context, '编辑', 'Edit'),
                        onPressed: _busy ? null : () => _edit(proxy: p),
                      ),
                      ManagementLink(
                        label: mx(context, '克隆', 'Clone'),
                        onPressed: _busy || !plus
                            ? null
                            : () => _edit(proxy: p, clone: true),
                      ),
                      ManagementLink(
                        label: mx(context, '删除', 'Delete'),
                        danger: true,
                        onPressed: _busy ? null : () => _delete(p),
                      ),
                    ],
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class DesktopProxyDialog extends ConsumerStatefulWidget {
  const DesktopProxyDialog({super.key, this.proxy, this.clone = false});
  final ServerProxyModel? proxy;
  final bool clone;
  @override
  ConsumerState<DesktopProxyDialog> createState() => _DesktopProxyDialogState();
}

class _DesktopProxyDialogState extends ConsumerState<DesktopProxyDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
        text: widget.clone
            ? '${widget.proxy?.name ?? ''} (copy)'
            : widget.proxy?.name,
      ),
      _host = TextEditingController(text: widget.proxy?.host),
      _port = TextEditingController(
        text: widget.proxy == null ? '' : '${widget.proxy!.port}',
      ),
      _user = TextEditingController(text: widget.proxy?.username),
      _password = TextEditingController(text: widget.proxy?.password);
  late String _type = widget.proxy?.type ?? 'socks5';
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final proxy = ServerProxyModel(
        id: widget.clone ? '' : widget.proxy?.id ?? '',
        name: _name.text.trim(),
        type: _type,
        host: _host.text.trim(),
        port: int.parse(_port.text),
        username: _user.text.trim(),
        password: _password.text,
      );
      final repo = ref.read(settingsRepositoryProvider);
      if (proxy.id.isEmpty) {
        await repo.createProxy(proxy);
      } else {
        await repo.updateProxy(proxy);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    width: 500,
    busy: _busy,
    title: widget.clone
        ? mx(context, '克隆代理', 'Clone proxy')
        : widget.proxy == null
        ? mx(context, '添加代理', 'Add proxy')
        : mx(context, '编辑代理', 'Edit proxy'),
    body: Form(
      key: _form,
      child: Column(
        children: [
          if (_error != null) ManagementError(message: _error!),
          DesktopSettingRow(
            label: mx(context, '类型', 'Type'),
            child: DesktopSelect(
              options: const {'socks5': 'SOCKS5', 'http': 'HTTP'},
              values: [_type],
              enabled: !_busy,
              onSelected: (v) => setState(() => _type = v),
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '名称', 'Name'),
            child: DesktopSettingInput(
              controller: _name,
              enabled: !_busy,
              validator: (v) => v!.trim().isEmpty || v.length > 50
                  ? mx(
                      context,
                      '请输入 1–50 字符的名称',
                      'Enter a name (1–50 characters)',
                    )
                  : null,
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '主机', 'Host'),
            child: DesktopSettingInput(
              controller: _host,
              enabled: !_busy,
              validator: (v) => v!.trim().isEmpty
                  ? mx(context, '请输入主机地址', 'Enter a host address')
                  : null,
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '端口', 'Port'),
            child: DesktopSettingInput(
              controller: _port,
              enabled: !_busy,
              validator: (v) {
                final port = int.tryParse(v ?? '');
                return port == null || port < 1 || port > 65535
                    ? mx(context, '端口范围 1–65535', 'Port range: 1–65535')
                    : null;
              },
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '用户名', 'Username'),
            child: DesktopSettingInput(
              controller: _user,
              enabled: !_busy,
              hint: mx(context, '可选', 'Optional'),
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '密码', 'Password'),
            child: DesktopSettingInput(
              controller: _password,
              enabled: !_busy,
              secret: true,
              hint: mx(context, '可选', 'Optional'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      ManagementButton(
        label: mx(context, '取消', 'Cancel'),
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      ManagementButton(
        label: mx(context, '确定', 'Confirm'),
        primary: true,
        onPressed: _busy ? null : _save,
      ),
    ],
  );
}
