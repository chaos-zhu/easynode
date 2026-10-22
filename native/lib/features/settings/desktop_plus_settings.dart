import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_form_controls.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../state/plus_discount_notifier.dart';
import '../../state/plus_info_notifier.dart';
import '../ai_agent/agent_models.dart';
import 'desktop_settings_repository.dart';
import 'desktop_settings_widgets.dart';

class DesktopPlusSettings extends ConsumerStatefulWidget {
  const DesktopPlusSettings({super.key});
  @override
  ConsumerState<DesktopPlusSettings> createState() =>
      _DesktopPlusSettingsState();
}

class _DesktopPlusSettingsState extends ConsumerState<DesktopPlusSettings> {
  final _key = TextEditingController();
  bool _initialized = false, _busy = false, _loading = false;
  int _failures = 0, _limit = 0;
  String? _error, _devicesError;
  List<Map<String, dynamic>> _devices = [];
  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _devicesLoad() async {
    setState(() {
      _loading = true;
      _devicesError = null;
    });
    try {
      final data = await ref
          .read(desktopSettingsRepositoryProvider)
          .plusDevices();
      if (mounted) {
        setState(() {
          _devices = mapList(data['devices']);
          _limit = intValue(data['deviceLimit']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _devicesError = managementError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() async {
    if (_busy) return;
    if (_key.text.trim().length < 15) {
      setState(
        () => _error = mx(context, '请输入正确的 Plus Key', 'Enter a valid Plus Key'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(desktopSettingsRepositoryProvider)
          .activatePlus(_key.text.trim());
      _failures = 0;
      if (mounted) {
        managementNotice(
          context,
          mx(context, '激活成功，感谢支持', 'Activated. Thank you for your support'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${managementError(e)}${++_failures > 3 ? mx(context, '。请确认 Key 正确并重启面板服务后重试；有疑问请联系作者 @chaoszhu。', '. Check the key and restart the panel service before retrying. Contact @chaoszhu for help.') : ''}',
        );
      }
    } finally {
      await ref.read(plusInfoProvider.notifier).refresh();
      if (mounted) {
        setState(() => _busy = false);
        if (ref.read(isPlusActiveProvider)) unawaited(_devicesLoad());
      }
    }
  }

  Future<void> _release(Map<String, dynamic> device) async {
    if (!await managementConfirm(
          context,
          mx(
            context,
            '释放该实例的 Plus 授权？该实例将失去 Plus 功能。',
            'Release this instance’s Plus license? Its Plus features will be disabled.',
          ),
        ) ||
        !mounted) {
      return;
    }
    try {
      await ref
          .read(desktopSettingsRepositoryProvider)
          .releasePlusDevice(device['instanceId'].toString());
      await _devicesLoad();
    } catch (e) {
      if (mounted) setState(() => _devicesError = managementError(e));
    }
  }

  Future<void> _contact() => showAppDialog<void>(
    context: context,
    builder: (context) => DesktopManagementDialog(
      width: 440,
      title: mx(context, '增加在线机器授权', 'Increase device allowance'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mx(
              context,
              '如需同时在更多机器上使用，请联系作者增加额度。',
              'Contact the author to use Plus on more instances.',
            ),
          ),
          const SizedBox(height: 14),
          ManagementLink(
            label: 'Telegram: @chaoszhu',
            onPressed: () => launchUrl(
              Uri.parse('https://t.me/chaoszhu'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ManagementLink(
            label: mx(context, 'QQ：307205265（复制）', 'QQ: 307205265 (copy)'),
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: '307205265'));
              if (context.mounted) {
                managementNotice(context, mx(context, '已复制', 'Copied'));
              }
            },
          ),
        ],
      ),
      actions: [
        ManagementButton(
          label: mx(context, '关闭', 'Close'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(plusInfoProvider);
    final discount = ref.watch(plusDiscountProvider).valueOrNull;
    final plus = info.valueOrNull;
    if (!_initialized && plus != null) {
      _initialized = true;
      _key.text = plus.key;
      if (plus.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_devicesLoad());
        });
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (info.hasError)
          ManagementError(
            message: managementError(info.error!),
            onRetry: () => ref.read(plusInfoProvider.notifier).refresh(),
          ),
        if (_error != null) ManagementError(message: _error!),
        DesktopSettingRow(
          label: 'Plus Key',
          labelTopPadding: 8,
          labelWidth: 86,
          wide: true,
          maxWidth: 850,
          child: LayoutBuilder(
            builder: (context, size) {
              final input = DesktopSettingInput(
                controller: _key,
                secret: true,
                controlHeight: 36,
                onSubmitted: (_) => _activate(),
              );
              final buttons = Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _activate,
                    style: desktopButtonStyle(context, primary: true).copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? context.colors.chip
                            : context.colors.success,
                      ),
                      foregroundColor: const WidgetStatePropertyAll(
                        Colors.white,
                      ),
                    ),
                    child: Text(
                      _busy
                          ? mx(context, '激活中…', 'Activating…')
                          : plus?.isActive == true
                          ? mx(context, '已激活', 'Activated')
                          : mx(context, '立即激活', 'Activate'),
                    ),
                  ),
                  ManagementButton(
                    label: mx(context, '获取 Plus Key', 'Get Plus Key'),
                    primary: true,
                    icon: Icons.north_east,
                    onPressed: _buy,
                  ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (size.maxWidth >= 640)
                    Row(
                      children: [
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: input,
                          ),
                        ),
                        const SizedBox(width: 15),
                        buttons,
                      ],
                    )
                  else ...[
                    input,
                    const SizedBox(height: 12),
                    buttons,
                  ],
                  if (plus?.isActive != true && discount?.discount == true)
                    ManagementLink(label: discount!.content, onPressed: _buy),
                ],
              );
            },
          ),
        ),
        if (plus?.isActive == true)
          Text(
            mx(context, 'Plus 专属功能已激活', 'Plus features are activated'),
            style: TextStyle(color: context.colors.success),
          )
        else if (plus?.needRestart == true)
          ManagementError(
            message: mx(
              context,
              '授权已在其它实例被占用，请重启面板服务后重试',
              'The license is in use on another instance. Restart the panel service and retry.',
            ),
          )
        else if (plus?.error.isNotEmpty == true)
          ManagementError(message: plus!.error),
        if (plus?.isActive == true) ...[
          const SizedBox(height: 15),
          _deviceSection(),
        ],
        const SizedBox(height: 15),
        _comparison(context),
      ],
    );
  }

  void _buy() => unawaited(
    launchUrl(
      Uri.parse('https://en.221022.xyz/buy-plus'),
      mode: LaunchMode.externalApplication,
    ),
  );

  String _relative(int timestamp) {
    if (timestamp <= 0) return '—';
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    if (elapsed.isNegative) return '—';
    if (elapsed.inSeconds < 10) return mx(context, '刚刚', 'Just now');
    if (elapsed.inSeconds < 60) {
      return mx(context, '${elapsed.inSeconds}秒前', '${elapsed.inSeconds}s ago');
    }
    if (elapsed.inMinutes < 60) {
      return mx(
        context,
        '${elapsed.inMinutes}分钟前',
        '${elapsed.inMinutes}m ago',
      );
    }
    if (elapsed.inHours < 24) {
      return mx(context, '${elapsed.inHours}小时前', '${elapsed.inHours}h ago');
    }
    return mx(context, '${elapsed.inDays}天前', '${elapsed.inDays}d ago');
  }

  Widget _deviceSection() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: context.colors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    mx(context, '设备授权', 'Device licenses'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ManagementTag(
                    mx(
                      context,
                      '已用 ${_devices.length} / $_limit 台',
                      '${_devices.length} / $_limit used',
                    ),
                    round: true,
                    color: _limit > 0 && _devices.length >= _limit
                        ? context.colors.danger
                        : context.colors.success,
                  ),
                  OutlinedButton(
                    onPressed: _contact,
                    style: desktopButtonStyle(context).copyWith(
                      minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      foregroundColor: WidgetStatePropertyAll(
                        context.colors.accent,
                      ),
                      side: WidgetStatePropertyAll(
                        BorderSide(
                          color: context.colors.accent.withValues(alpha: .4),
                        ),
                      ),
                      backgroundColor: WidgetStatePropertyAll(
                        context.colors.accentSoft,
                      ),
                    ),
                    child: Text(mx(context, '增加授权', 'Increase allowance')),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: _loading ? null : _devicesLoad,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.accent,
                textStyle: const TextStyle(fontSize: 13),
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(mx(context, '刷新', 'Refresh')),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_devicesError != null)
          ManagementError(message: _devicesError!, onRetry: _devicesLoad),
        Stack(
          children: [
            SizedBox(
              height: (44 + 48 * _devices.length.clamp(1, 6)).toDouble(),
              child: ManagementTable(
                bordered: false,
                empty: mx(context, '暂无在线设备', 'No online devices'),
                columns: [
                  const ManagementColumn('#', width: 50),
                  ManagementColumn(mx(context, '实例', 'Instance'), width: 180),
                  ManagementColumn(
                    mx(context, '出口 IP', 'Public IP'),
                    width: 150,
                  ),
                  ManagementColumn(mx(context, '版本', 'Version'), width: 100),
                  ManagementColumn(
                    mx(context, '最后活跃', 'Last active'),
                    width: 120,
                  ),
                  ManagementColumn.actions(
                    mx(context, '操作', 'Actions'),
                    width: 100,
                  ),
                ],
                rows: [for (var i = 0; i < _devices.length; i++) _deviceRow(i)],
              ),
            ),
            if (_loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info, size: 14, color: context.colors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mx(
                  context,
                  '当新实例启动且额度已满时，将自动移除最久未活跃实例的 Plus 授权。如需主动腾出额度，可点击对应实例的「释放」按钮。',
                  'When the allowance is full, a new instance replaces the least recently active license. Use Release to free an allowance manually.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: context.colors.muted,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  List<Widget> _deviceRow(int index) {
    final d = _devices[index];
    final id = '${d['instanceId'] ?? ''}';
    final short = id.length > 4 ? '${id.substring(0, 4)}…' : id;
    final version = '${d['version'] ?? ''}';
    final timestamp = intValue(d['lastSeen']);
    return [
      Text('${index + 1}'),
      Row(
        children: [
          Flexible(
            child: Tooltip(
              message: id,
              child: Text(
                mx(context, '实例 $short', 'Instance $short'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          if (d['isCurrent'] == true) ...[
            const SizedBox(width: 8),
            ManagementTag(
              mx(context, '本机', 'Current'),
              color: context.colors.success,
            ),
          ],
        ],
      ),
      Text('${d['ip'] ?? '—'}'),
      Text(
        version.isEmpty
            ? '—'
            : version.startsWith('v')
            ? version
            : 'v$version',
        style: TextStyle(color: context.colors.muted),
      ),
      Tooltip(
        message: managementDate(
          timestamp > 0 ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: context.colors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _relative(timestamp),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      d['isCurrent'] == true
          ? const Text('—')
          : OutlinedButton(
              onPressed: _loading ? null : () => _release(d),
              style: desktopButtonStyle(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                foregroundColor: WidgetStatePropertyAll(context.colors.danger),
                backgroundColor: WidgetStatePropertyAll(
                  context.colors.danger.withValues(alpha: .08),
                ),
                side: WidgetStatePropertyAll(
                  BorderSide(
                    color: context.colors.danger.withValues(alpha: .4),
                  ),
                ),
              ),
              child: Text(mx(context, '释放', 'Release')),
            ),
    ];
  }

  Future<void> _about() => showAppDialog<void>(
    context: context,
    builder: (context) => DesktopManagementDialog(
      width: 560,
      title: mx(context, 'Plus说明', 'About Plus'),
      body: Text(
        mx(
          context,
          'EasyNode 最初是一个简单的 Web 终端工具，随着用户群的扩大，功能需求也日益增长。为了项目的可持续发展，后续版本推出 PLUS，新增特性优先在 PLUS 中实现；基础功能仍可免费使用。\n\n'
              '暂不支持纯内网用户激活 PLUS。激活码仅用于激活面板 PLUS 功能且仅限本人使用，分享他人可能导致激活码与服务器 IP 被永久封禁。\n\n'
              '在 PLUS 正式发布前赞赏过的用户，可联系作者 @chaoszhu，凭赞赏记录免费获取永久 PLUS 授权码。',
          'EasyNode began as a simple Web terminal. Plus supports continued development and receives new features first. Basic features remain free.\n\n'
              'Plus activation requires internet access. Keys are for personal use only; sharing may result in permanent key and server IP bans.\n\n'
              'Supporters who donated before the Plus launch can contact @chaoszhu with their donation record for a free lifetime license.',
        ),
        style: const TextStyle(fontSize: 14, height: 1.8),
      ),
      actions: [
        ManagementButton(
          label: mx(context, '关闭', 'Close'),
          onPressed: () => Navigator.pop(context),
        ),
        ManagementButton(
          label: mx(context, '获取 Plus Key', 'Get Plus Key'),
          primary: true,
          onPressed: _buy,
        ),
      ],
    ),
  );

  Widget _comparison(BuildContext context) {
    final basic = [
      mx(context, 'AI 助手对话与只读运维', 'AI chat and read-only operations'),
      mx(context, '服务器管理', 'Server management'),
      mx(context, '服务器导入导出', 'Server import and export'),
      mx(context, '服务器分组', 'Server groups'),
      mx(context, '凭据管理', 'Credential management'),
      mx(context, '脚本库', 'Script library'),
      mx(context, '批量连接', 'Batch connections'),
      mx(context, '批量指令', 'Batch commands'),
      mx(context, '通知方式(有限制)', 'Notifications (limited)'),
    ];
    final advanced = [
      mx(context, 'AI 助手写入、删除与变更操作', 'AI write, delete and change operations'),
      mx(context, '服务器代理&跳板机功能', 'Server proxies and jump hosts'),
      mx(context, 'RDP远程win桌面连接', 'Remote Windows desktops via RDP'),
      mx(context, '文件对传', 'File transfer'),
      mx(context, '终端单窗口模式', 'Single-window terminal mode'),
      mx(context, '批量修改实例配置', 'Bulk instance configuration'),
      mx(context, '脚本库批量导出导入', 'Bulk script import and export'),
      mx(
        context,
        '脚本库分组与终端功能栏支持',
        'Script groups and terminal toolbar integration',
      ),
      mx(
        context,
        '终端功能栏docker容器管理',
        'Docker containers in the terminal toolbar',
      ),
      mx(context, '终端会话挂起', 'Terminal session suspension'),
    ];
    Widget card(bool plus, List<String> items) => Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        plus
                            ? mx(context, 'Plus专属功能', 'Plus features')
                            : mx(context, '基础功能(免费)', 'Basic features (free)'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (plus)
                        ManagementLink(
                          label: mx(context, 'Plus说明', 'About Plus'),
                          onPressed: _about,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ManagementTag(
                  plus ? 'PLUS' : 'Basic',
                  color: plus ? context.colors.success : context.colors.accent,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: i < items.length - 1
                          ? Border(
                              bottom: BorderSide(color: context.colors.border),
                            )
                          : null,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check,
                          size: 16,
                          color: context.colors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            items[i],
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              color: plus
                                  ? context.colors.success
                                  : context.colors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, size) => size.maxWidth < 640
          ? Column(
              children: [
                card(false, basic),
                const SizedBox(height: 20),
                card(true, advanced),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: card(false, basic)),
                const SizedBox(width: 20),
                Expanded(child: card(true, advanced)),
              ],
            ),
    );
  }
}
