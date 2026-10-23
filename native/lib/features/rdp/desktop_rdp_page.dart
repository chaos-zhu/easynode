import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_color_theme.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/desktop_management_dialog.dart';
import '../../core/ui/desktop_management.dart';
import '../../core/ui/desktop_popover.dart';
import '../../core/ui/desktop_select.dart';
import '../../state/desktop_server_catalog_provider.dart';
import '../../state/plus_info_notifier.dart';
import '../servers/server_model.dart';
import '../terminal/desktop/terminal_widgets.dart';
import 'desktop_rdp_workspace.dart';
import 'rdp_engine.dart';

class DesktopRdpPage extends ConsumerStatefulWidget {
  const DesktopRdpPage({super.key});
  @override
  ConsumerState<DesktopRdpPage> createState() => _DesktopRdpPageState();
}

class _DesktopRdpPageState extends ConsumerState<DesktopRdpPage> {
  String _resolution = 'adaptive';
  RdpQuality _quality = RdpQuality.medium;
  bool _clipboard = true;
  RdpOptions get _options => RdpOptions(
    resolution: _resolution,
    quality: _quality,
    clipboard: _clipboard,
  );

  Future<void> _choose(BuildContext anchor, List<ServerModel> hosts) async {
    final emptyLabel = mx(context, '暂无 Windows 实例', 'No Windows instances');
    const style = TextStyle(
      fontSize: 14,
      height: 22 / 14,
      fontWeight: FontWeight.w400,
    );
    // Element dropdowns size to their labels rather than a fixed card width.
    double width = 0;
    for (final label
        in hosts.isEmpty ? [emptyLabel] : hosts.map((h) => h.displayName)) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width > width) width = painter.width;
      painter.dispose();
    }
    final host = await showDesktopPopover<ServerModel>(
      context: anchor,
      width: (width + 34).clamp(100, 360),
      dropdown: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 5),
        shrinkWrap: true,
        children: [
          if (hosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Text(
                emptyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: context.colors.softMuted),
              ),
            ),
          for (final host in hosts)
            TextButton(
              onPressed: () => Navigator.pop(context, host),
              style: ButtonStyle(
                alignment: Alignment.centerLeft,
                minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused)
                      ? context.colors.accent
                      : context.colors.text,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused)
                      ? context.colors.accentSoft
                      : Colors.transparent,
                ),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                textStyle: const WidgetStatePropertyAll(style),
                splashFactory: NoSplash.splashFactory,
                shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              ),
              child: Text(
                host.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    if (host != null && mounted) {
      ref.read(desktopRdpWorkspaceProvider).open(host, options: _options);
    }
  }

  Future<void> _showSettings() => showAppDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => DesktopManagementDialog(
        width: 480,
        title: mx(context, '连接设置', 'Connection settings'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mx(context, '应用于之后新建的连接', 'Applies to new connections'),
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: DesktopSelect(
                    controlHeight: 32,
                    options: {
                      'adaptive': mx(context, '自适应分辨率', 'Adaptive resolution'),
                      '1280x800': '1280 × 800',
                      '1920x1080': '1920 × 1080',
                      '2560x1440': '2560 × 1440',
                    },
                    values: [_resolution],
                    onSelected: (v) => update(() => _resolution = v),
                  ),
                ),
                SizedBox(
                  width: 125,
                  child: DesktopSelect(
                    controlHeight: 32,
                    options: {
                      'low': mx(context, '低画质', 'Low quality'),
                      'medium': mx(context, '中画质', 'Medium quality'),
                      'high': mx(context, '高画质', 'High quality'),
                    },
                    values: [_quality.name],
                    onSelected: (v) =>
                        update(() => _quality = RdpQuality.values.byName(v)),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: _clipboard,
                        onChanged: (v) => update(() => _clipboard = v!),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mx(context, '共享剪贴板', 'Share clipboard'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          ManagementButton(
            height: 32,
            primary: true,
            label: mx(context, '完成', 'Done'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );

  String _status(RdpWindowStatus status) => switch (status) {
    RdpWindowStatus.connecting => mx(context, '连接中', 'Connecting'),
    RdpWindowStatus.connected => mx(context, '已连接', 'Connected'),
    RdpWindowStatus.disconnected => mx(
      context,
      '已断开 · 点击重连',
      'Disconnected · Reconnect',
    ),
    RdpWindowStatus.error => mx(context, '连接失败 · 点击重试', 'Failed · Retry'),
  };
  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(desktopRdpWorkspaceProvider);
    final catalog = ref.watch(desktopServerCatalogProvider);
    final hosts =
        catalog.valueOrNull?.hosts
            .where((h) => h.isWindows && h.canConnect)
            .toList() ??
        [];
    final plus = ref.watch(isPlusActiveProvider);
    return AnimatedBuilder(
      animation: workspace,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(35, 15, 35, 15),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ManagementButton(
                  label: mx(context, '连接设置', 'Connection settings'),
                  height: 32,
                  leading: const TerminalIcon(Icons.settings_outlined),
                  onPressed: _showSettings,
                ),
                Builder(
                  builder: (anchor) => ManagementButton(
                    label: mx(context, '新建连接', 'New connection'),
                    trailing: const TerminalIcon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                    ),
                    height: 32,
                    primary: true,
                    onPressed: plus ? () => _choose(anchor, hosts) : null,
                  ),
                ),
              ],
            ),
          ),
          if (catalog.hasError)
            ManagementError(
              message: managementError(catalog.error!),
              onRetry: () => ref.invalidate(desktopServerCatalogProvider),
            ),
          if (!plus)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                mx(
                  context,
                  '远程桌面为 Plus 功能，请先激活授权。',
                  'Remote desktop requires an active Plus license.',
                ),
                style: TextStyle(color: context.colors.warning),
              ),
            ),
          Expanded(
            child: workspace.connections.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/terminal/icons/empty-${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}.svg',
                          width: 160,
                          height: 174,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          mx(
                            context,
                            '无远程桌面连接',
                            'No remote desktop connections',
                          ),
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final entry in workspace.connections)
                          _card(workspace, entry, plus),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    DesktopRdpWorkspace workspace,
    DesktopRdpConnection entry,
    bool plus,
  ) {
    final color = switch (entry.status) {
      RdpWindowStatus.connected => context.colors.success,
      RdpWindowStatus.connecting => context.colors.accent,
      RdpWindowStatus.error => context.colors.danger,
      _ => context.colors.muted,
    };
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        children: [
          Positioned.fill(
            child: Tooltip(
              message:
                  entry.error ??
                  '${entry.server.displayName}\n${_status(entry.status)}',
              child: OutlinedButton(
                onPressed: plus
                    ? () => workspace.open(entry.server, options: entry.options)
                    : null,
                style: ButtonStyle(
                  padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
                  foregroundColor: WidgetStatePropertyAll(context.colors.text),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered)
                        ? context.colors.accentSoft
                        : Colors.transparent,
                  ),
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.hovered)
                          ? context.colors.accent.withValues(alpha: .5)
                          : context.colors.accent,
                    ),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  splashFactory: NoSplash.splashFactory,
                  animationDuration: const Duration(milliseconds: 200),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const TerminalIcon(
                      Icons.desktop_windows_outlined,
                      size: 36,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      entry.server.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _status(entry.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: color,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Tooltip(
              message: mx(context, '关闭连接', 'Close connection'),
              child: TextButton(
                onPressed: () => workspace.close(entry),
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(24, 24)),
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered)
                        ? context.colors.danger
                        : context.colors.text,
                  ),
                ),
                child: const TerminalIcon(Icons.close, size: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
