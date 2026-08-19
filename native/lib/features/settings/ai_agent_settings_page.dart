import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../state/agent_providers.dart';
import '../ai_agent/agent_models.dart';
import '../ai_agent/agent_selection_sheet.dart';
import '../ai_agent/agent_ui_tokens.dart';
import 'widgets/settings_section.dart';

part 'ai_agent_settings_widgets.dart';
part 'ai_agent_host_policy_widgets.dart';

class AiAgentSettingsPage extends ConsumerStatefulWidget {
  const AiAgentSettingsPage({super.key});

  @override
  ConsumerState<AiAgentSettingsPage> createState() =>
      _AiAgentSettingsPageState();
}

class _AiAgentSettingsPageState extends ConsumerState<AiAgentSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _models = TextEditingController();
  final _contextLimit = TextEditingController();
  final _maxSteps = TextEditingController();

  String _provider = 'openai-compatible';
  bool _nativeAgentEnabled = true;
  bool _obscureKey = true;
  bool _saving = false;
  bool _initialized = false;
  bool _modelsInvalid = false;
  List<AgentHostPolicy> _hostPolicies = const [];
  final Set<String> _changedHostIds = {};

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _models.dispose();
    _contextLimit.dispose();
    _maxSteps.dispose();
    super.dispose();
  }

  void _applyData(AgentSettingsData data) {
    final config = data.config;
    _provider = config.providerType;
    _nativeAgentEnabled = config.nativeAgentEnabled;
    _url.text = config.apiUrl;
    _key.text = config.apiKey;
    _models.text = config.models.join('\n');
    _contextLimit.text = config.contextLimit.toString();
    _maxSteps.text = config.maxSteps.toString();
    _hostPolicies = List.of(data.hostPolicies);
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(agentSettingsProvider);
    final l = AppLocalizations.of(context);
    final data = settings.valueOrNull;
    if (!_initialized && data != null) _applyData(data);

    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        backgroundColor: context.colors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l.tr('agent.settings')),
      ),
      bottomNavigationBar: data == null
          ? null
          : _SaveBar(
              saving: _saving,
              onPressed: _saving ? null : () => _save(data.config),
            ),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _SettingsError(
          error: error.toString(),
          onRetry: ref.read(agentSettingsProvider.notifier).refresh,
        ),
        data: (_) => Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              SettingsSection(
                title: l.tr('agent.settings.interface'),
                children: [
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                      secondary: Icon(
                        Icons.smart_toy_outlined,
                        color: context.colors.primary,
                      ),
                      title: Text(
                        l.tr('agent.settings.showEntry'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(l.tr('agent.settings.showEntryHint')),
                      ),
                      value: _nativeAgentEnabled,
                      onChanged: _setEnabled,
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: l.tr('agent.settings.provider'),
                children: [
                  _SettingsChoiceRow(
                    key: const Key('agent-provider-row'),
                    icon: Icons.hub_outlined,
                    label: l.tr('agent.settings.providerType'),
                    value: _providerLabel(_provider),
                    onTap: _pickProvider,
                  ),
                  _SettingsField(
                    label: 'Base URL',
                    controller: _url,
                    hintText: _providerUrlHint,
                    keyboardType: TextInputType.url,
                    monospace: true,
                    validator: (value) {
                      final uri = Uri.tryParse(value?.trim() ?? '');
                      return uri != null &&
                              (uri.scheme == 'http' || uri.scheme == 'https')
                          ? null
                          : l.tr('agent.settings.invalidUrl');
                    },
                  ),
                  _SettingsField(
                    label: 'API Key',
                    controller: _key,
                    obscureText: _obscureKey,
                    monospace: true,
                    suffix: IconButton(
                      tooltip: _obscureKey
                          ? l.tr('common.show')
                          : l.tr('common.hide'),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                    ),
                    validator: (value) => value?.trim().isNotEmpty == true
                        ? null
                        : l.tr('agent.settings.required'),
                  ),
                  _ModelSelectionRow(
                    models: _parseModels(_models.text),
                    invalid: _modelsInvalid,
                    onTap: _pickModels,
                  ),
                  _LimitsRow(contextLimit: _contextLimit, maxSteps: _maxSteps),
                ],
              ),
              SettingsSection(
                title: l.tr('agent.settings.hostPolicies'),
                children: _hostPolicies.isEmpty
                    ? [
                        _EmptyHosts(
                          text: l.tr('agent.settings.hostPoliciesEmpty'),
                        ),
                      ]
                    : _hostPolicies
                          .map(
                            (policy) => _HostPolicySummaryRow(
                              key: ValueKey(policy.hostId),
                              policy: policy,
                              onTap: () => _editHostPolicy(policy),
                            ),
                          )
                          .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _providerUrlHint => switch (_provider) {
    'anthropic' => 'https://api.anthropic.com/v1',
    'google' => 'https://generativelanguage.googleapis.com/v1beta',
    _ => 'https://api.openai.com/v1',
  };

  List<String> _parseModels(String? value) => (value ?? '')
      .split(RegExp(r'[,\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Future<void> _pickProvider() async {
    final l = AppLocalizations.of(context);
    final result = await showAgentSingleSelectionSheet<String>(
      context: context,
      title: l.tr('agent.settings.selectProvider'),
      icon: Icons.hub_outlined,
      selected: _provider,
      options: [
        AgentSelectionOption(
          value: 'openai-compatible',
          title: 'OpenAI Compatible',
          subtitle: l.tr('agent.settings.provider.openaiHint'),
          icon: Icons.api_outlined,
        ),
        AgentSelectionOption(
          value: 'anthropic',
          title: 'Anthropic',
          subtitle: l.tr('agent.settings.provider.anthropicHint'),
          icon: Icons.auto_awesome_outlined,
        ),
        AgentSelectionOption(
          value: 'google',
          title: 'Google',
          subtitle: l.tr('agent.settings.provider.googleHint'),
          icon: Icons.cloud_outlined,
        ),
      ],
    );
    if (result != null && mounted) setState(() => _provider = result);
  }

  Future<void> _pickModels() async {
    final l = AppLocalizations.of(context);
    final current = _parseModels(_models.text);
    await showAgentMultiSelectionSheet<String>(
      context: context,
      title: l.tr('agent.settings.selectModels'),
      icon: Icons.memory_outlined,
      searchable: true,
      allowBulkSelection: true,
      searchHint: l.tr('agent.searchModels'),
      customValueHint: l.tr('agent.settings.customModelHint'),
      loadOptions: _provider == 'openai-compatible' ? _discoverModels : null,
      loadOptionsLabel: _provider == 'openai-compatible'
          ? l.tr('agent.settings.discoverModels')
          : null,
      selected: current.toSet(),
      onSelectionChanged: (result) {
        if (!mounted) return;
        setState(() {
          _models.text = result.join('\n');
          _modelsInvalid = result.isEmpty;
        });
      },
      options: current
          .map(
            (model) => AgentSelectionOption(
              value: model,
              title: model,
              icon: Icons.memory_outlined,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<AgentSelectionOption<String>>> _discoverModels() async {
    final l = AppLocalizations.of(context);
    if (_url.text.trim().isEmpty || _key.text.trim().isEmpty) {
      throw StateError(l.tr('agent.settings.discoveryNeedsCredentials'));
    }
    final models = await ref
        .read(agentSettingsProvider.notifier)
        .discoverModels(apiUrl: _url.text, apiKey: _key.text);
    return models
        .map(
          (model) => AgentSelectionOption(
            value: model,
            title: model,
            icon: Icons.memory_outlined,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _editHostPolicy(AgentHostPolicy policy) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HostPolicyEditorSheet(
        policy: policy,
        onChanged: (result) {
          if (!mounted) return;
          setState(() {
            _hostPolicies = _hostPolicies
                .map((item) => item.hostId == result.hostId ? result : item)
                .toList(growable: false);
            _changedHostIds.add(result.hostId);
          });
        },
      ),
    );
  }

  Future<void> _save(AgentProviderConfig original) async {
    final models = _parseModels(_models.text);
    if (_nativeAgentEnabled) {
      setState(() => _modelsInvalid = models.isEmpty);
      if (_formKey.currentState?.validate() != true || models.isEmpty) return;
    }

    final config = _nativeAgentEnabled
        ? original.copyWith(
            providerType: _provider,
            apiUrl: _url.text.trim(),
            apiKey: _key.text.trim(),
            models: models,
            contextLimit: int.parse(_contextLimit.text),
            maxSteps: int.parse(_maxSteps.text),
            nativeAgentEnabled: true,
          )
        : original.copyWith(nativeAgentEnabled: false);

    setState(() => _saving = true);
    try {
      await ref
          .read(agentSettingsProvider.notifier)
          .saveSettings(
            config: config,
            hostPolicies: _hostPolicies,
            changedHostPolicies: _hostPolicies
                .where((policy) => _changedHostIds.contains(policy.hostId))
                .toList(growable: false),
          );
      if (_nativeAgentEnabled) {
        await ref.read(agentControllerProvider.notifier).refreshConnection();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _show(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    final conversation = ref.read(agentControllerProvider).conversation;
    if (!enabled && conversation.running) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            AppLocalizations.of(context).tr('agent.settings.stopBeforeHide'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).tr('agent.stop')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      ref.read(agentControllerProvider.notifier).stop();
    }
    if (mounted) setState(() => _nativeAgentEnabled = enabled);
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
