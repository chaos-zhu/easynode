import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/desktop_management.dart';
import 'desktop_account_settings.dart';
import 'desktop_ai_settings.dart';
import 'desktop_ip_settings.dart';
import 'desktop_notification_settings.dart';
import 'desktop_plus_settings.dart';
import 'desktop_proxy_settings.dart';
import 'desktop_session_settings.dart';

enum DesktopSettingsSection {
  account,
  sessions,
  access,
  notifications,
  proxies,
  ai,
  plus,
}

final desktopSettingsSectionProvider = StateProvider<DesktopSettingsSection>(
  (ref) => DesktopSettingsSection.account,
);

class DesktopSettingsPage extends ConsumerStatefulWidget {
  const DesktopSettingsPage({super.key});
  @override
  ConsumerState<DesktopSettingsPage> createState() =>
      _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends ConsumerState<DesktopSettingsPage> {
  final _visited = <DesktopSettingsSection>{};
  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(desktopSettingsSectionProvider);
    _visited.add(selected);
    final labels = [
      mx(context, '修改密码', 'Account'),
      mx(context, '登录管理', 'Sessions'),
      mx(context, '访问控制', 'Access control'),
      mx(context, '通知配置', 'Notifications'),
      mx(context, '代理服务', 'Proxies'),
      mx(context, 'AI 助手', 'AI assistant'),
      mx(context, 'Plus 激活', 'Plus activation'),
    ];
    final titles = [
      mx(context, '账户与安全', 'Account and security'),
      ...labels.skip(1),
    ];
    final descriptions = [
      mx(
        context,
        '更新登录信息与两步验证，修改后所有设备需要重新登录。',
        'Update login credentials and two-factor authentication. Changing credentials signs out all devices.',
      ),
      mx(
        context,
        '查看当前设备和历史登录会话，并撤销不再使用的登录凭证。',
        'Review current and past sessions and revoke credentials that are no longer needed.',
      ),
      mx(
        context,
        '限制可以访问面板、WebSocket 与 RDP 服务的来源 IP。',
        'Restrict source IP addresses for the panel, WebSocket and RDP services.',
      ),
      mx(
        context,
        '配置通知渠道，并选择需要接收提醒的事件。',
        'Configure notification channels and choose events to receive.',
      ),
      mx(
        context,
        '集中维护远程连接使用的代理节点。',
        'Manage proxy nodes for remote connections.',
      ),
      mx(
        context,
        '配置模型服务、外部工具和主机权限策略。',
        'Configure model providers, external tools and host permission policies.',
      ),
      mx(
        context,
        '管理授权状态、设备额度与 Plus 专属功能。',
        'Manage licensing, device allowance and Plus features.',
      ),
    ];
    Widget pane(DesktopSettingsSection section) => SingleChildScrollView(
      key: ValueKey(section),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                [
                  DesktopSettingsSection.sessions,
                  DesktopSettingsSection.proxies,
                ].contains(section)
                ? 1440
                : section == DesktopSettingsSection.account
                ? 900
                : 1200,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titles[section.index],
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: context.colors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                descriptions[section.index],
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: switch (section) {
                  DesktopSettingsSection.account =>
                    const DesktopAccountSettings(),
                  DesktopSettingsSection.sessions =>
                    const DesktopSessionSettings(),
                  DesktopSettingsSection.access => const DesktopIpSettings(),
                  DesktopSettingsSection.notifications =>
                    const DesktopNotificationSettings(),
                  DesktopSettingsSection.proxies =>
                    const DesktopProxySettings(),
                  DesktopSettingsSection.ai => const DesktopAiSettings(),
                  DesktopSettingsSection.plus => const DesktopPlusSettings(),
                },
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 148,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final section in DesktopSettingsSection.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: selected == section
                          ? context.colors.accentSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        key: ValueKey('desktop-settings-${section.name}'),
                        onTap: () =>
                            ref
                                    .read(
                                      desktopSettingsSectionProvider.notifier,
                                    )
                                    .state =
                                section,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          alignment: Alignment.centerLeft,
                          constraints: const BoxConstraints(minHeight: 42),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            labels[section.index],
                            style: TextStyle(
                              fontSize: 14,
                              color: selected == section
                                  ? context.colors.accent
                                  : context.colors.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: IndexedStack(
              index: selected.index,
              children: [
                for (final section in DesktopSettingsSection.values)
                  _visited.contains(section)
                      ? ExcludeFocus(
                          excluding: section != selected,
                          child: TickerMode(
                            enabled: section == selected,
                            child: pane(section),
                          ),
                        )
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
