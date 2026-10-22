import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_select.dart';
import '../ai_agent/agent_models.dart';
import 'desktop_settings_repository.dart';
import 'desktop_settings_widgets.dart';

class DesktopNotificationSettings extends ConsumerStatefulWidget {
  const DesktopNotificationSettings({super.key});
  @override
  ConsumerState<DesktopNotificationSettings> createState() =>
      _DesktopNotificationSettingsState();
}

class _DesktopNotificationSettingsState
    extends ConsumerState<DesktopNotificationSettings> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _events = [];
  String _type = 'email';
  bool _busy = false, _loaded = false;
  String? _error;
  final _switching = <String>{};
  static const _fieldNames = {
    'email': ['service', 'host', 'user', 'pass', 'to'],
    'sct': ['sendKey'],
    'tg': ['token', 'chatId'],
    'webhook': ['url', 'headers', 'template'],
  };
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(desktopSettingsRepositoryProvider);
      final data = await Future.wait<Object>([
        repo.notificationConfig(),
        repo.notificationEvents(),
      ]);
      if (!mounted) return;
      setState(() {
        _config = data[0] as Map<String, dynamic>;
        _events = data[1] as List<Map<String, dynamic>>;
        _type = '${_config['type'] ?? 'email'}';
        for (final channel in _fieldNames.entries) {
          _config[channel.key] = Map<String, dynamic>.from(
            stringMap(_config[channel.key]),
          );
          for (final name in channel.value) {
            (_fields['${channel.key}.$name'] ??= TextEditingController()).text =
                '${(_config[channel.key] as Map)[name] ?? ''}';
          }
        }
        final email = _config['email'] as Map<String, dynamic>;
        email.putIfAbsent('useCustom', () => false);
        email.putIfAbsent('port', () => 465);
        email.putIfAbsent('secure', () => true);
        final webhook = _config['webhook'] as Map<String, dynamic>;
        webhook.putIfAbsent('method', () => 'POST');
        webhook.putIfAbsent('contentType', () => 'application/json');
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> get _channel => _config[_type] as Map<String, dynamic>;
  Widget _input(
    String name,
    String label, {
    bool required = false,
    bool secret = false,
    String? hint,
    int lines = 1,
    String? Function(String)? validate,
  }) => DesktopSettingRow(
    label: label,
    child: DesktopSettingInput(
      controller: _fields['$_type.$name']!,
      enabled: !_busy,
      secret: secret,
      hint: hint,
      lines: lines,
      validator: (v) => required && v!.trim().isEmpty
          ? mx(context, '此项必填', 'Required')
          : validate?.call(v ?? ''),
    ),
  );
  Widget _select(
    String name,
    String label,
    Map<String, String> options, {
    String? fallback,
    ValueChanged<String>? onChanged,
  }) => DesktopSettingRow(
    label: label,
    child: DesktopSelect(
      options: options,
      values: ['${_channel[name] ?? fallback ?? options.keys.first}'],
      enabled: !_busy,
      onSelected: (v) => setState(() {
        _channel[name] = v;
        onChanged?.call(v);
      }),
    ),
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final entry in _fields.entries) {
        final parts = entry.key.split('.');
        (_config[parts[0]] as Map)[parts[1]] = entry.value.text;
      }
      _config['type'] = _type;
      if (_type == 'webhook') {
        for (final name in ['headers', 'template']) {
          final text = '${_channel[name] ?? ''}'.trim();
          if (text.isNotEmpty) {
            final json = jsonDecode(text);
            if (json is! Map) {
              throw FormatException(
                mx(context, '$name 必须是 JSON 对象', '$name must be a JSON object'),
              );
            }
          }
        }
      }
      await ref
          .read(desktopSettingsRepositoryProvider)
          .saveNotifications(_config);
      if (mounted) {
        managementNotice(
          context,
          mx(
            context,
            '测试通过，保存成功；请确认已收到测试通知。',
            'Test passed and configuration saved. Confirm that you received the test notification.',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> event, bool value) async {
    final type = '${event['type']}';
    setState(() => _switching.add(type));
    try {
      await ref
          .read(desktopSettingsRepositoryProvider)
          .toggleNotification(type, value);
      if (mounted) setState(() => event['sw'] = value);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _switching.remove(type));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        ManagementError(message: _error!, onRetry: !_loaded ? _load : null),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (_loaded) ...[
        Form(
          key: _form,
          child: Column(
            children: [
              DesktopSettingRow(
                label: mx(context, '通知方式', 'Channel'),
                child: DesktopSelect(
                  options: {
                    'email': mx(context, '邮箱', 'Email'),
                    'sct': 'Server酱',
                    'tg': 'Telegram',
                    'webhook': 'Webhook',
                  },
                  values: [_type],
                  enabled: !_busy,
                  onSelected: (v) => setState(() => _type = v),
                ),
              ),
              if (_type == 'sct') ...[
                _input('sendKey', 'SendKey', required: true, hint: 'SCT******'),
                DesktopSettingRow(
                  label: '',
                  child: ManagementLink(
                    label: mx(
                      context,
                      'Server酱官网（免费版每日最多 5 条）',
                      'ServerChan website (free plan: 5/day)',
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse('https://sct.ftqq.com/r/9338'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              ],
              if (_type == 'email') ...[
                DesktopSettingRow(
                  label: mx(context, '配置模式', 'Configuration'),
                  child: DesktopSelect(
                    options: {
                      'service': mx(context, '服务商', 'Provider'),
                      'custom': mx(context, '自定义 SMTP', 'Custom SMTP'),
                    },
                    values: [
                      _channel['useCustom'] == true ? 'custom' : 'service',
                    ],
                    enabled: !_busy,
                    onSelected: (v) => setState(() {
                      _channel['useCustom'] = v == 'custom';
                      _channel['port'] ??= 465;
                      _channel['secure'] ??= true;
                    }),
                  ),
                ),
                if (_channel['useCustom'] != true)
                  _input(
                    'service',
                    mx(context, '服务商', 'Provider'),
                    required: true,
                    hint: 'QQ, 126, 163, Gmail…',
                  )
                else ...[
                  _input(
                    'host',
                    mx(context, 'SMTP 服务器', 'SMTP server'),
                    required: true,
                    hint: 'smtp.gmail.com',
                  ),
                  _select(
                    'port',
                    mx(context, '端口', 'Port'),
                    const {
                      '465': '465 (SSL)',
                      '587': '587 (STARTTLS)',
                      '25': '25',
                    },
                    fallback: '465',
                    onChanged: (v) {
                      _channel['port'] = int.parse(v);
                      _channel['secure'] = v == '465';
                    },
                  ),
                  DesktopSettingRow(
                    label: mx(context, '加密连接', 'Encryption'),
                    child: DesktopSelect(
                      options: const {'ssl': 'SSL/TLS', 'starttls': 'STARTTLS'},
                      values: [
                        _channel['secure'] != false ? 'ssl' : 'starttls',
                      ],
                      enabled: !_busy,
                      onSelected: (v) =>
                          setState(() => _channel['secure'] = v == 'ssl'),
                    ),
                  ),
                ],
                _input(
                  'user',
                  mx(context, '邮箱地址', 'Email address'),
                  required: true,
                  validate: (v) =>
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)
                      ? null
                      : mx(context, '请输入有效邮箱', 'Enter a valid email address'),
                ),
                _input(
                  'pass',
                  mx(context, 'SMTP 密码', 'SMTP password'),
                  required: true,
                  secret: true,
                ),
                _input(
                  'to',
                  mx(context, '收件人', 'Recipient'),
                  hint: mx(
                    context,
                    '留空则发送给自己',
                    'Leave blank to send to yourself',
                  ),
                ),
              ],
              if (_type == 'tg') ...[
                _input('token', 'Token', required: true, secret: true),
                _input(
                  'chatId',
                  'ChatId',
                  required: true,
                  validate: (v) => RegExp(r'^-?\d+$').hasMatch(v)
                      ? null
                      : mx(context, 'ChatId 必须为数字', 'ChatId must be numeric'),
                ),
                DesktopSettingRow(
                  label: '',
                  child: ManagementLink(
                    label: mx(
                      context,
                      '查看 Token/ChatId 获取教程',
                      'Token / ChatId guide',
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://easynode.chaoszhu.com/zh/guide/get-tg-token',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              ],
              if (_type == 'webhook') ...[
                _input(
                  'url',
                  'URL',
                  required: true,
                  validate: (v) {
                    final uri = Uri.tryParse(v);
                    return uri == null ||
                            !['http', 'https'].contains(uri.scheme) ||
                            uri.host.isEmpty
                        ? mx(
                            context,
                            '请输入有效的 HTTP(S) URL',
                            'Enter a valid HTTP(S) URL',
                          )
                        : null;
                  },
                ),
                _select('method', mx(context, '请求方法', 'Method'), const {
                  'POST': 'POST',
                  'GET': 'GET',
                  'PUT': 'PUT',
                }),
                _select('contentType', 'Content-Type', const {
                  'application/json': 'application/json',
                  'application/x-www-form-urlencoded':
                      'application/x-www-form-urlencoded',
                  'multipart/form-data': 'multipart/form-data',
                  'text/plain': 'text/plain',
                }),
                _input(
                  'headers',
                  'Header',
                  lines: 2,
                  hint: '{"Authorization":"Bearer …"}',
                ),
                _input(
                  'template',
                  mx(context, '自定义模板', 'Custom template'),
                  lines: 6,
                  hint: '{"title":"{{title}}", "content":"{{content}}"}',
                ),
                DesktopSettingRow(
                  label: '',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManagementLink(
                        label: mx(context, '格式化模板', 'Format template'),
                        onPressed: () {
                          try {
                            final c = _fields['webhook.template']!;
                            c.text = const JsonEncoder.withIndent(
                              '  ',
                            ).convert(jsonDecode(c.text));
                          } catch (e) {
                            setState(
                              () => _error = mx(
                                context,
                                '模板不是有效的 JSON',
                                'Template is not valid JSON',
                              ),
                            );
                          }
                        },
                      ),
                      Text(
                        mx(
                          context,
                          '变量：{{title}}、{{content}}、{{timestamp}}、{{datetime}}；留空使用默认格式。',
                          'Variables: {{title}}, {{content}}, {{timestamp}}, {{datetime}}. Leave blank for defaults.',
                        ),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              DesktopSettingRow(
                label: '',
                child: ManagementButton(
                  label: mx(context, '测试并保存', 'Test and save'),
                  primary: true,
                  onPressed: _busy ? null : _save,
                ),
              ),
            ],
          ),
        ),
        Text(
          mx(
            context,
            '请确保通知方式能够正常收到测试通知。',
            'Confirm that the selected channel receives the test notification.',
          ),
          style: TextStyle(color: context.colors.success, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 340,
          child: ManagementTable(
            columns: [
              ManagementColumn(mx(context, '通知类型', 'Event'), width: 250),
              ManagementColumn(mx(context, '开关', 'Enabled'), width: 100),
            ],
            rows: [
              for (final event in _events)
                [
                  Text('${event['desc'] ?? event['type']}'),
                  ManagementSwitch(
                    value: event['sw'] == true,
                    label: '${event['desc'] ?? event['type']}',
                    onChanged: _switching.contains('${event['type']}')
                        ? null
                        : (v) => _toggle(event, v),
                  ),
                ],
            ],
          ),
        ),
      ],
    ],
  );
}
