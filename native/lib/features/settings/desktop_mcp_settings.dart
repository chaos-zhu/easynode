import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_select.dart';
import '../../state/agent_providers.dart';
import '../ai_agent/agent_mcp_models.dart';
import 'desktop_settings_widgets.dart';

/// Builds the Web MCP payload, omitting an unchanged, masked saved secret.
Map<String, dynamic> desktopMcpPayload({
  required String name,
  required String key,
  required String url,
  required bool enabled,
  required int connectTimeout,
  required int callTimeout,
  required bool authorization,
  required String secret,
  AgentMcpServer? existing,
}) {
  final headerName =
      existing?.headers.keys
          .where((k) => k.toLowerCase() == 'authorization')
          .firstOrNull ??
      'Authorization';
  return {
    'name': name.trim(),
    'key': key.trim(),
    'url': url.trim(),
    'enabled': enabled,
    'connectTimeoutSeconds': connectTimeout,
    'callTimeoutSeconds': callTimeout,
    if (!authorization)
      'headers': <String, String>{}
    else if (secret.trim().isNotEmpty)
      'headers': {headerName: secret.trim()}
    else if (existing == null)
      'headers': <String, String>{},
  };
}

class DesktopMcpSettings extends ConsumerStatefulWidget {
  const DesktopMcpSettings({super.key});
  @override
  ConsumerState<DesktopMcpSettings> createState() => _DesktopMcpSettingsState();
}

class _DesktopMcpSettingsState extends ConsumerState<DesktopMcpSettings> {
  final _busy = <String>{};
  String? _error;
  Future<void> _action(String id, Future<void> Function() fn) async {
    setState(() {
      _busy.add(id);
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _remove(AgentMcpServer s) async {
    if (!await managementConfirm(
          context,
          mx(
            context,
            '删除 MCP Server「${s.name}」及其工具？',
            'Delete MCP server “${s.name}” and its tools?',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _action(
      s.id,
      () => ref.read(agentMcpServersProvider.notifier).remove(s.id),
    );
  }

  Future<void> _edit([AgentMcpServer? server]) => showAppDialog<void>(
    context: context,
    builder: (_) => DesktopMcpEditor(server: server),
  );
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentMcpServersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              mx(context, '外部 MCP', 'External MCP'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            ManagementButton(
              label: mx(context, '添加 MCP Server', 'Add MCP server'),
              primary: true,
              onPressed: () => _edit(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          mx(
            context,
            '接入远程 Streamable HTTP MCP Server。保存后自动发现并启用工具，调用外部工具时始终需要确认。',
            'Connect remote Streamable HTTP MCP servers. Saving discovers and enables tools. External tool calls always require confirmation.',
          ),
          style: TextStyle(
            color: context.colors.muted,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 18),
        if (_error != null || state.hasError)
          ManagementError(
            message: _error ?? managementError(state.error!),
            onRetry: () => ref.read(agentMcpServersProvider.notifier).refresh(),
          ),
        if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
        SizedBox(
          height: 400,
          child: ManagementTable(
            columns: [
              const ManagementColumn('Server', width: 170),
              const ManagementColumn('Endpoint', width: 230),
              ManagementColumn(
                mx(context, '已启用工具', 'Enabled tools'),
                width: 100,
              ),
              ManagementColumn(mx(context, '启用', 'Enabled'), width: 75),
              ManagementColumn.actions(
                mx(context, '操作', 'Actions'),
                width: 250,
              ),
            ],
            rows: [
              for (final s in state.valueOrNull ?? <AgentMcpServer>[])
                [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name),
                      Text(
                        s.key,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: s.url,
                        child: Text(
                          s.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (s.lastError.isNotEmpty)
                        Tooltip(
                          message: s.lastError,
                          child: Text(
                            s.lastError,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.danger,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text('${s.enabledToolCount} / ${s.tools.length}'),
                  ManagementSwitch(
                    value: s.enabled,
                    label: s.name,
                    onChanged: _busy.contains(s.id)
                        ? null
                        : (v) => _action(s.id, () async {
                            await ref
                                .read(agentMcpServersProvider.notifier)
                                .save(s.id, {'enabled': v});
                          }),
                  ),
                  Wrap(
                    children: [
                      ManagementLink(
                        label: mx(context, '刷新', 'Refresh'),
                        onPressed: _busy.contains(s.id)
                            ? null
                            : () => _action(s.id, () async {
                                final result = await ref
                                    .read(agentMcpServersProvider.notifier)
                                    .discover(s.id);
                                if (result.lastError.isNotEmpty) {
                                  throw StateError(result.lastError);
                                }
                              }),
                      ),
                      if (s.tools.isNotEmpty)
                        ManagementLink(
                          label: mx(context, '管理', 'Tools'),
                          onPressed: () => showAppDialog<void>(
                            context: context,
                            builder: (_) => DesktopMcpToolsDialog(server: s),
                          ),
                        ),
                      ManagementLink(
                        label: mx(context, '编辑', 'Edit'),
                        onPressed: _busy.contains(s.id) ? null : () => _edit(s),
                      ),
                      ManagementLink(
                        label: mx(context, '删除', 'Delete'),
                        danger: true,
                        onPressed: _busy.contains(s.id)
                            ? null
                            : () => _remove(s),
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

class DesktopMcpEditor extends ConsumerStatefulWidget {
  const DesktopMcpEditor({super.key, this.server});
  final AgentMcpServer? server;
  @override
  ConsumerState<DesktopMcpEditor> createState() => _DesktopMcpEditorState();
}

class _DesktopMcpEditorState extends ConsumerState<DesktopMcpEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _key = TextEditingController(),
      _url = TextEditingController(),
      _secret = TextEditingController(),
      _connect = TextEditingController(),
      _call = TextEditingController();
  bool _enabled = true, _authorization = true, _busy = false;
  String? _error, _result;
  @override
  void initState() {
    super.initState();
    final s = widget.server;
    _name.text = s?.name ?? '';
    _key.text = s?.key ?? '';
    _url.text = s?.url ?? '';
    _enabled = s?.enabled ?? true;
    _authorization = s == null || s.hasAuthorization;
    _connect.text = '${s?.connectTimeoutSeconds ?? 10}';
    _call.text = '${s?.callTimeoutSeconds ?? 60}';
  }

  @override
  void dispose() {
    for (final c in [_name, _key, _url, _secret, _connect, _call]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? mx(context, '不能为空', 'Required') : null;
  String? _timeout(String? v) {
    final n = int.tryParse(v ?? '');
    return n == null || n < 1 || n > 60
        ? mx(context, '请输入 1–60 的整数', 'Enter an integer from 1 to 60')
        : null;
  }

  Future<void> _submit({bool test = false}) async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final payload = desktopMcpPayload(
        name: _name.text,
        key: _key.text,
        url: _url.text,
        enabled: _enabled,
        connectTimeout: int.parse(_connect.text),
        callTimeout: int.parse(_call.text),
        authorization: _authorization,
        secret: _secret.text,
        existing: widget.server,
      );
      final notifier = ref.read(agentMcpServersProvider.notifier);
      if (test) {
        final count = await notifier.testConnection({
          ...payload,
          if (widget.server != null) 'id': widget.server!.id,
        });
        if (mounted) {
          setState(
            () => _result = mx(
              context,
              '连接成功，发现 $count 个工具',
              'Connected. Found $count tools.',
            ),
          );
        }
      } else {
        final s = widget.server == null
            ? await notifier.create(payload)
            : await notifier.save(widget.server!.id, payload);
        if (!mounted) return;
        managementNotice(
          context,
          s.lastError.isEmpty
              ? mx(
                  context,
                  '保存成功，发现 ${s.tools.length} 个工具',
                  'Saved. Found ${s.tools.length} tools.',
                )
              : mx(
                  context,
                  '配置已保存并停用，发现工具失败：${s.lastError}',
                  'Saved and disabled. Tool discovery failed: ${s.lastError}',
                ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    width: 640,
    topAligned: true,
    busy: _busy,
    title: widget.server == null
        ? mx(context, '添加 MCP Server', 'Add MCP server')
        : mx(context, '编辑 MCP Server', 'Edit MCP server'),
    body: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ManagementError(message: _error!),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _result!,
                style: TextStyle(color: context.colors.success),
              ),
            ),
          DesktopSettingRow(
            label: mx(context, '名称', 'Name'),
            child: DesktopSettingInput(controller: _name, validator: _required),
          ),
          DesktopSettingRow(
            label: mx(context, '标识', 'Key'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopSettingInput(
                  controller: _key,
                  enabled: widget.server == null,
                  hint: 'github',
                  validator: (v) => RegExp(r'^[a-z0-9_-]+$').hasMatch(v ?? '')
                      ? null
                      : mx(
                          context,
                          '仅支持小写字母、数字、下划线和连字符',
                          'Use lowercase letters, digits, underscores or hyphens',
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  mx(
                    context,
                    '用于生成稳定工具名称，创建后不可修改。',
                    'Used for stable tool names; cannot be changed after creation.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.muted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          DesktopSettingRow(
            label: 'URL',
            child: DesktopSettingInput(
              controller: _url,
              hint: 'https://example.com/mcp',
              validator: (v) {
                final u = Uri.tryParse(v ?? '');
                return u != null &&
                        ['http', 'https'].contains(u.scheme) &&
                        u.host.isNotEmpty
                    ? null
                    : mx(
                        context,
                        '请输入 HTTP/HTTPS URL',
                        'Enter an HTTP/HTTPS URL',
                      );
              },
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '连接超时', 'Connect timeout'),
            child: DesktopSettingInput(
              controller: _connect,
              hint: mx(context, '秒，1–60', 'Seconds, 1–60'),
              validator: _timeout,
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '调用超时', 'Call timeout'),
            child: DesktopSettingInput(
              controller: _call,
              hint: mx(context, '秒，1–60', 'Seconds, 1–60'),
              validator: _timeout,
            ),
          ),
          DesktopSettingRow(
            label: mx(context, '认证方式', 'Authentication'),
            child: DesktopSelect(
              options: {
                'none': mx(context, '无需认证', 'No authentication'),
                'authorization': mx(
                  context,
                  '密钥 (Authorization)',
                  'Key (Authorization)',
                ),
              },
              values: [_authorization ? 'authorization' : 'none'],
              onSelected: (v) =>
                  setState(() => _authorization = v == 'authorization'),
            ),
          ),
          if (_authorization)
            DesktopSettingRow(
              label: mx(context, '密钥', 'Secret'),
              child: DesktopSettingInput(
                controller: _secret,
                secret: true,
                hint: widget.server == null
                    ? 'Bearer <token>'
                    : mx(
                        context,
                        '留空保持原密钥',
                        'Leave blank to keep the saved secret',
                      ),
              ),
            ),
          DesktopSettingRow(
            label: mx(context, '启用', 'Enabled'),
            child: ManagementSwitch(
              value: _enabled,
              label: mx(context, '启用', 'Enabled'),
              onChanged: _busy ? null : (v) => setState(() => _enabled = v),
            ),
          ),
        ],
      ),
    ),
    actions: [
      ManagementButton(
        label: mx(context, '测试连接', 'Test connection'),
        onPressed: _busy ? null : () => _submit(test: true),
      ),
      ManagementButton(
        label: mx(context, '取消', 'Cancel'),
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      ManagementButton(
        label: _busy
            ? mx(context, '处理中…', 'Working…')
            : mx(context, '保存', 'Save'),
        primary: true,
        onPressed: _busy ? null : _submit,
      ),
    ],
  );
}

class DesktopMcpToolsDialog extends ConsumerStatefulWidget {
  const DesktopMcpToolsDialog({super.key, required this.server});
  final AgentMcpServer server;
  @override
  ConsumerState<DesktopMcpToolsDialog> createState() =>
      _DesktopMcpToolsDialogState();
}

class _DesktopMcpToolsDialogState extends ConsumerState<DesktopMcpToolsDialog> {
  late final List<AgentMcpTool> _tools = [...widget.server.tools];
  final _expanded = <int>{};
  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(agentMcpServersProvider.notifier).save(widget.server.id, {
        'tools': [for (final t in _tools) t.toUpdateJson()],
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopManagementDialog(
    width: 760,
    title: mx(
      context,
      '${widget.server.name} 工具管理',
      '${widget.server.name} tools',
    ),
    busy: _busy,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          mx(
            context,
            '关闭不希望 AI 使用的工具。所有外部工具在调用前都会请求确认。',
            'Disable tools that AI should not use. External tools always require confirmation.',
          ),
          style: TextStyle(
            fontSize: 13,
            color: context.colors.muted,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null) ManagementError(message: _error!),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .45,
          child: ManagementTable(
            columns: [
              const ManagementColumn('', width: 42),
              ManagementColumn(mx(context, '工具', 'Tool'), width: 200),
              ManagementColumn(mx(context, '说明', 'Description'), width: 275),
              ManagementColumn(mx(context, '启用', 'Enabled'), width: 80),
            ],
            rows: [
              for (final (i, t) in _tools.indexed)
                [
                  IconButton(
                    onPressed: () => setState(() {
                      if (!_expanded.add(i)) _expanded.remove(i);
                    }),
                    icon: Icon(
                      _expanded.contains(i)
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 16,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.displayName.isEmpty ? t.remoteName : t.displayName,
                      ),
                      Text(
                        t.remoteName,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.muted,
                        ),
                      ),
                    ],
                  ),
                  Text(t.description.isEmpty ? '—' : t.description),
                  ManagementSwitch(
                    value: t.enabled,
                    label: t.remoteName,
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _tools[i] = t.copyWith(enabled: v),
                          ),
                  ),
                ],
            ],
            expanded: {
              for (final i in _expanded)
                i: Container(
                  padding: const EdgeInsets.all(16),
                  color: context.colors.chip,
                  child: SelectableText(
                    'Schema\n${const JsonEncoder.withIndent('  ').convert(_tools[i].inputSchema)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
            },
          ),
        ),
      ],
    ),
    actions: [
      ManagementButton(
        label: mx(context, '取消', 'Cancel'),
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      ManagementButton(
        label: mx(context, '保存工具设置', 'Save tool settings'),
        primary: true,
        onPressed: _busy ? null : _save,
      ),
    ],
  );
}
