import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_select.dart';
import '../../state/agent_providers.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../../state/storage_providers.dart';
import '../ai_agent/agent_models.dart';
import '../ai_agent/agent_ui_tokens.dart';
import 'desktop_mcp_settings.dart';
import 'desktop_settings_widgets.dart';

/// Desktop edits the server configuration without mounting mobile host/SSH state.
class DesktopAiSettings extends ConsumerStatefulWidget {
  const DesktopAiSettings({super.key});
  @override
  ConsumerState<DesktopAiSettings> createState() => _DesktopAiSettingsState();
}

class _DesktopAiSettingsState extends ConsumerState<DesktopAiSettings> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController(),
      _key = TextEditingController(),
      _context = TextEditingController(),
      _steps = TextEditingController();
  AgentProviderConfig? _config;
  String _type = 'openai-compatible';
  List<String> _models = [], _options = [];
  final _policies = <String, AgentHostPolicy>{};
  final _savingHosts = <String>{};
  int _section = 0;
  bool _loading = true,
      _saving = false,
      _discovering = false,
      _preferenceBusy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_url, _key, _context, _steps]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await ref.read(agentRepositoryProvider).getConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _type = config.providerType;
        _url.text = config.apiUrl;
        _key.text = config.apiKey;
        _models = [...config.models];
        _context.text = '${config.contextLimit}';
        _steps.text = '${config.maxSteps}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    if (_models.isEmpty) {
      setState(
        () => _error = mx(context, '请至少填写一个模型', 'Add at least one model'),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = _config!.copyWith(
        providerType: _type,
        apiUrl: _url.text,
        apiKey: _key.text,
        models: List.of(_models),
        contextLimit: int.parse(_context.text),
        maxSteps: int.parse(_steps.text),
      );
      await ref.read(agentRepositoryProvider).saveProvider(config);
      final saved = await ref.read(agentRepositoryProvider).getConfig();
      ref.invalidate(agentSettingsProvider);
      if (mounted) {
        setState(() => _config = saved);
        managementNotice(
          context,
          mx(context, 'Provider 设置已保存', 'Provider settings saved'),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preference(bool enabled) async {
    setState(() => _preferenceBusy = true);
    try {
      final value = await ref
          .read(agentRepositoryProvider)
          .setNativeAgentEnabled(enabled);
      await ref.read(appStorageProvider).setNativeAgentEnabledCache(value);
      ref.invalidate(agentSettingsProvider);
      if (mounted) {
        setState(() => _config = _config!.copyWith(nativeAgentEnabled: value));
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _preferenceBusy = false);
    }
  }

  Future<void> _discover() async {
    if (_url.text.trim().isEmpty || _key.text.trim().isEmpty) {
      setState(
        () => _error = mx(
          context,
          '请先填写 Base URL 和 API Key',
          'Enter Base URL and API Key first',
        ),
      );
      return;
    }
    setState(() {
      _discovering = true;
      _error = null;
    });
    try {
      final models = await ref
          .read(agentRepositoryProvider)
          .discoverModels(apiUrl: _url.text, apiKey: _key.text);
      if (mounted) {
        setState(() => _options = models);
        managementNotice(
          context,
          mx(
            context,
            '已加载 ${models.length} 个模型，请从下拉列表选择',
            '${models.length} models loaded. Select models below.',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  void _addModel(String value) {
    final id = value.trim();
    if (id.isEmpty) return;
    setState(() {
      if (!_models.contains(id)) _models.add(id);
    });
  }

  Future<void> _savePolicy(AgentHostPolicy policy) async {
    setState(() {
      _savingHosts.add(policy.hostId);
      _error = null;
    });
    try {
      await ref.read(agentRepositoryProvider).updateHostPolicy(policy);
      ref.invalidate(desktopServerCatalogProvider);
      ref.invalidate(agentSettingsProvider);
      if (mounted) {
        managementNotice(
          context,
          mx(
            context,
            '已保存 ${policy.name} 的 AI 策略',
            'AI policy saved for ${policy.name}',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _savingHosts.remove(policy.hostId));
    }
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? mx(context, '不能为空', 'Required') : null;
  String? _range(String? v, int min, int max) {
    final n = int.tryParse(v ?? '');
    return n != null && n >= min && n <= max
        ? null
        : mx(
            context,
            '请输入 $min–$max 的整数',
            'Enter an integer from $min to $max',
          );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ManagementTabs<int>(
        options: {
          0: mx(context, '模型服务', 'Model provider'),
          1: mx(context, '外部 MCP', 'External MCP'),
          2: mx(context, '主机策略', 'Host policies'),
        },
        icons: const {
          0: Icons.memory_outlined,
          1: Icons.link,
          2: Icons.lock_outline,
        },
        value: _section,
        height: 48,
        horizontalPadding: 22,
        inset: 24,
        onChanged: (index) => setState(() {
          _section = index;
          _error = null;
        }),
      ),
      const SizedBox(height: 18),
      if (_error != null)
        ManagementError(
          message: _error!,
          onRetry: _config == null ? _load : null,
        ),
      if (_loading)
        const LinearProgressIndicator(minHeight: 2)
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: _section == 1
              ? const DesktopMcpSettings()
              : _section == 2
              ? _hosts()
              : _config != null
              ? _provider()
              : const SizedBox.shrink(),
        ),
    ],
  );

  Widget _providerRow(String label, Widget child) => DesktopSettingRow(
    label: label,
    labelAlign: TextAlign.right,
    labelTopPadding: 8,
    maxWidth: 620,
    child: child,
  );

  Widget _tip(String text) => Text(
    text,
    style: TextStyle(color: context.colors.muted, fontSize: 12, height: 1.6),
  );

  Widget _numberRow(
    String label,
    TextEditingController controller,
    int min,
    int max,
    String tip, {
    int step = 1,
  }) => _providerRow(
    label,
    LayoutBuilder(
      builder: (context, size) {
        final number = SizedBox(
          width: 150,
          child: DesktopSettingNumber(
            controller: controller,
            min: min,
            max: max,
            step: step,
            validator: (v) => _range(v, min, max),
          ),
        );
        return size.maxWidth >= 360
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  number,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _tip(tip),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [number, const SizedBox(height: 6), _tip(tip)],
              );
      },
    ),
  );

  Widget _provider() => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 20),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.colors.border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mx(context, 'AI 助手入口', 'AI assistant entry'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _tip(
                          mx(
                            context,
                            '控制登录后各页面是否显示 AI 助手入口，不影响终端助手。',
                            'Show the assistant entry after login. Terminal assistants are unaffected.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ManagementSwitch(
                        value: _config!.nativeAgentEnabled,
                        label: mx(context, 'AI 助手入口', 'AI assistant entry'),
                        onChanged: _preferenceBusy ? null : _preference,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _config!.nativeAgentEnabled
                            ? mx(context, '已显示', 'Visible')
                            : mx(context, '已隐藏', 'Hidden'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _config!.nativeAgentEnabled
                              ? context.colors.accent
                              : context.colors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              mx(context, 'Provider 设置', 'Provider settings'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _tip(
              mx(
                context,
                '配置 AI 助手使用的模型服务，保存后 AI 助手和终端助手共用此配置。',
                'Configure the model provider shared by the global and terminal assistants.',
              ),
            ),
            const SizedBox(height: 20),
            _providerRow(
              'Provider',
              LayoutBuilder(
                builder: (context, size) => Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: size.maxWidth.clamp(0, 260),
                      child: DesktopSelect(
                        controlHeight: 36,
                        options: {
                          'openai-compatible': mx(
                            context,
                            'OpenAI 兼容',
                            'OpenAI compatible',
                          ),
                          'anthropic': 'Anthropic',
                          'google': 'Google Gemini',
                        },
                        values: [_type],
                        onSelected: (v) => setState(() => _type = v),
                      ),
                    ),
                    ManagementLink(
                      label: mx(context, '没有 API Key？', 'Need an API Key?'),
                      onPressed: () => launchUrl(
                        Uri.parse('https://en.221022.xyz/buy-ai-token'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _providerRow(
              'Base URL',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManagementSuggestionInput(
                    controller: _url,
                    controlHeight: 36,
                    options: {
                      if (_type == 'anthropic')
                        'https://api.anthropic.com/v1':
                            'https://api.anthropic.com/v1'
                      else if (_type == 'google')
                        'https://generativelanguage.googleapis.com/v1beta':
                            'https://generativelanguage.googleapis.com/v1beta'
                      else
                        'https://api.openai.com/v1':
                            'https://api.openai.com/v1',
                    },
                    hint: _type == 'anthropic'
                        ? 'https://api.anthropic.com/v1'
                        : _type == 'google'
                        ? 'https://generativelanguage.googleapis.com/v1beta'
                        : 'https://api.openai.com/v1',
                    validator: (v) {
                      final u = Uri.tryParse(v?.trim() ?? '');
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
                  const SizedBox(height: 6),
                  _tip(
                    _type == 'anthropic'
                        ? mx(
                            context,
                            '填写 API 前缀，不要附加 /messages。',
                            'Use the API prefix without /messages.',
                          )
                        : _type == 'google'
                        ? mx(
                            context,
                            '填写 API 前缀，不要附加 /models/...:generateContent。',
                            'Use the API prefix without /models/...:generateContent.',
                          )
                        : mx(
                            context,
                            '填写 OpenAI 兼容 API 前缀，通常以 /v1 结尾。',
                            'Use an OpenAI-compatible API prefix, usually ending in /v1.',
                          ),
                  ),
                ],
              ),
            ),
            _providerRow(
              'API Key',
              DesktopSettingInput(
                controller: _key,
                secret: true,
                controlHeight: 36,
                validator: _required,
              ),
            ),
            _providerRow(
              mx(context, '模型列表', 'Models'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, size) {
                      final select = DesktopSelect(
                        controlHeight: 36,
                        allowCreate: true,
                        maxVisibleTags: 1,
                        showSelectionOrder: false,
                        clearable: true,
                        options: {
                          for (final m in {..._options, ..._models}) m: m,
                        },
                        values: _models,
                        onSelected: _addModel,
                        onRemoved: (v) => setState(() => _models.remove(v)),
                        placeholder: mx(
                          context,
                          '搜索或输入模型 ID',
                          'Search or enter a model ID',
                        ),
                      );
                      if (_type != 'openai-compatible') return select;
                      final fetch = ManagementButton(
                        label: _discovering
                            ? mx(context, '获取中…', 'Loading…')
                            : mx(context, '获取模型', 'Fetch models'),
                        primary: true,
                        onPressed: _discovering ? null : _discover,
                      );
                      return size.maxWidth >= 350
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: select),
                                const SizedBox(width: 10),
                                fetch,
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                select,
                                const SizedBox(height: 8),
                                fetch,
                              ],
                            );
                    },
                  ),
                  if (_type != 'openai-compatible') ...[
                    const SizedBox(height: 6),
                    _tip(
                      mx(
                        context,
                        '当前 Provider 请手动填写可用模型 ID。',
                        'Enter available model IDs for this provider.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _numberRow(
              mx(context, '上下文窗口', 'Context window'),
              _context,
              1024,
              1 << 30,
              mx(
                context,
                '默认 65,536，按模型实际上下文窗口调整。',
                'Default: 65,536. Adjust to the model’s context window.',
              ),
              step: 1024,
            ),
            _numberRow(
              mx(context, '最大迭代次数', 'Maximum steps'),
              _steps,
              1,
              50,
              mx(
                context,
                '单次对话最多允许模型调用工具并继续推理的次数；默认 25，最多 50。',
                'Maximum tool and reasoning iterations per conversation. Default: 25, maximum: 50.',
              ),
            ),
            _providerRow(
              '',
              Align(
                alignment: Alignment.centerLeft,
                child: ManagementButton(
                  label: _saving
                      ? mx(context, '保存中…', 'Saving…')
                      : mx(context, '保存 Provider 设置', 'Save provider settings'),
                  primary: true,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _hosts() {
    final catalog = ref.watch(desktopServerCatalogProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          mx(context, '主机 AI 策略', 'Host AI policies'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          mx(
            context,
            '限制每台主机允许的操作范围和最高权限模式，会话不能突破这里的设置。',
            'Limit operations and permission modes for each host. Sessions cannot exceed these limits.',
          ),
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: context.colors.muted,
          ),
        ),
        const SizedBox(height: 18),
        if (catalog.hasError)
          ManagementError(
            message: managementError(catalog.error!),
            onRetry: () => ref.invalidate(desktopServerCatalogProvider),
          ),
        if (catalog.isLoading) const LinearProgressIndicator(minHeight: 2),
        SizedBox(
          height: 430,
          child: ManagementTable(
            columns: [
              ManagementColumn(mx(context, '主机', 'Host'), width: 190),
              ManagementColumn(mx(context, '允许 AI', 'Allow AI'), width: 90),
              ManagementColumn(mx(context, '允许操作', 'Operations'), width: 150),
              ManagementColumn(
                mx(context, '最高权限模式', 'Permission mode'),
                width: 155,
              ),
              ManagementColumn.actions(
                mx(context, '操作', 'Actions'),
                width: 175,
              ),
            ],
            rows: [
              for (final h in catalog.valueOrNull?.hosts ?? [])
                _hostRow(
                  _policies.putIfAbsent(
                    h.id,
                    () => AgentHostPolicy(
                      hostId: h.id,
                      name: h.displayName,
                      address: '${h.host}:${h.port}',
                      enabled: h.aiPolicy.enabled,
                      maxEffect: h.aiPolicy.maxEffect,
                      maxMode: h.aiPolicy.maxMode,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _hostRow(AgentHostPolicy p) => [
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name),
        Text(
          p.address,
          style: TextStyle(fontSize: 12, color: context.colors.muted),
        ),
      ],
    ),
    ManagementSwitch(
      value: p.enabled,
      label: p.name,
      onChanged: _savingHosts.contains(p.hostId)
          ? null
          : (v) => setState(() => _policies[p.hostId] = p.copyWith(enabled: v)),
    ),
    DesktopSelect(
      options: {
        'read': mx(context, '仅只读', 'Read only'),
        'write': mx(context, '允许读写', 'Read and write'),
      },
      values: [p.maxEffect],
      onSelected: (v) =>
          setState(() => _policies[p.hostId] = p.copyWith(maxEffect: v)),
    ),
    DesktopSelect(
      options: {
        'assist': mx(context, '协助', 'Assist'),
        'authorized': mx(context, '授权', 'Authorized'),
        'full_access': mx(context, '完全', 'Full'),
      },
      optionColors: {
        'authorized': AgentUiTokens.authorizedColor,
        'full_access': AgentUiTokens.fullAccessColor,
      },
      values: [p.maxMode],
      onSelected: (v) =>
          setState(() => _policies[p.hostId] = p.copyWith(maxMode: v)),
    ),
    Wrap(
      children: [
        ManagementLink(
          label: mx(context, '保存', 'Save'),
          onPressed: _savingHosts.contains(p.hostId)
              ? null
              : () => _savePolicy(p),
        ),
        ManagementLink(
          label: mx(context, '恢复默认', 'Reset'),
          onPressed: _savingHosts.contains(p.hostId)
              ? null
              : () {
                  final next = p.copyWith(
                    enabled: true,
                    maxEffect: 'write',
                    maxMode: 'full_access',
                  );
                  setState(() => _policies[p.hostId] = next);
                  unawaited(_savePolicy(next));
                },
        ),
      ],
    ),
  ];
}
