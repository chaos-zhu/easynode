import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';
import 'server_model.dart';
import 'server_proxy_model.dart';

/// Shared desktop cells for the catalog and its drag-to-order view.
class DesktopServerCell extends StatelessWidget {
  const DesktopServerCell({
    super.key,
    required this.host,
    required this.column,
    required this.allHosts,
    this.proxies = const [],
    this.onEdit,
    this.onAction,
    this.ordering = false,
  });

  final ServerModel host;
  final String column;
  final List<ServerModel> allHosts;
  final List<ServerProxyModel> proxies;
  final ValueChanged<ServerModel>? onEdit;
  final VoidCallback? onAction;
  final bool ordering;

  @override
  Widget build(BuildContext context) {
    final child = _cell(context);
    return ordering ? IgnorePointer(child: ExcludeFocus(child: child)) : child;
  }

  static double columnWidth(String column) => switch (column) {
    'name' || 'consoleUrl' => 180,
    'username' => 90,
    'host' || 'proxyType' => 150,
    'port' => 48,
    'authType' => 85,
    'expired' => 110,
    'tag' => 140,
    _ => 0,
  };

  Widget _text(String value, double width) => SizedBox(
    width: width,
    child: Text(
      value.isEmpty ? '--' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _cell(BuildContext context) {
    final l = AppLocalizations.of(context);
    switch (column) {
      case 'name':
        return SizedBox(
          width: 180,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ServerCellLink(
              key: ValueKey('desktop-server-name-${host.id}'),
              label: host.displayName,
              tooltip: ordering ? '' : l.tr('desktop.servers.edit'),
              icon: host.isWindows ? 'assets/windows.svg' : 'assets/linux.svg',
              onPressed: ordering || onEdit == null
                  ? null
                  : () => onEdit!(host),
            ),
          ),
        );
      case 'username':
        return _text(host.username, 90);
      case 'host':
        return SizedBox(
          width: 150,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ServerCellLink(
              key: ValueKey('desktop-server-host-${host.id}'),
              label: host.host.isEmpty ? '--' : host.host,
              tooltip: ordering ? '' : l.tr('servers.copyHost'),
              copy: true,
              onPressed: ordering || host.host.isEmpty
                  ? null
                  : () => _copyHost(context, host.host),
            ),
          ),
        );
      case 'port':
        return _text('${host.port}', 48);
      case 'authType':
        return _text(
          l.tr(
            'servers.auth.${host.authType == 'password' ? 'password' : 'privateKey'}',
          ),
          85,
        );
      case 'proxyType':
        var label = '--';
        if (host.proxyType == 'jumpHosts' && host.jumpHosts.isNotEmpty) {
          final hosts = {
            for (final item in allHosts) item.id: item.displayName,
          };
          label =
              '[${l.tr('servers.proxy.jumpHosts')}]${host.jumpHosts.map((id) => hosts[id] ?? 'Error').join('>>>')}';
        } else if (host.proxyType == 'proxyServer') {
          final proxy = proxies
              .where((item) => item.id == host.proxyServer)
              .firstOrNull;
          if (proxy != null) label = '[${proxy.type}]${proxy.displayName}';
        }
        return _text(label, 150);
      case 'expired':
        final date = host.expiredAt;
        return _text(
          date == null
              ? '--'
              : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          110,
        );
      case 'consoleUrl':
        if (host.consoleUrl.isEmpty) return _text('--', 180);
        return SizedBox(
          width: 180,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ServerCellLink(
              label: host.consoleUrl,
              tooltip: ordering ? '' : l.tr('desktop.comingSoon'),
              onPressed: ordering ? null : onAction,
            ),
          ),
        );
      case 'tag':
        final colors = context.colors;
        return SizedBox(
          width: 140,
          child: host.tag.isEmpty
              ? const Text('--')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tag in host.tag)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.success.withValues(alpha: .08),
                            border: Border.all(
                              color: colors.success.withValues(alpha: .3),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: colors.success,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _copyHost(BuildContext context, String host) async {
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: host));
      message = 'servers.hostCopied';
    } catch (_) {
      message = 'desktop.servers.copyFailed';
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).tr(message))),
    );
  }
}

/// Text-only table actions matching Web's name and copyable host cells.
class _ServerCellLink extends StatelessWidget {
  const _ServerCellLink({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.copy = false,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? icon;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    bool highlighted(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 3),
          ),
          alignment: Alignment.centerLeft,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          mouseCursor: WidgetStatePropertyAll(
            copy ? SystemMouseCursors.copy : SystemMouseCursors.click,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => highlighted(states) ? colors.accent : colors.text,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 13,
              fontWeight: copy ? FontWeight.w400 : FontWeight.w600,
              decoration: highlighted(states)
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationStyle: TextDecorationStyle.dashed,
              decorationColor: colors.accent.withValues(alpha: .5),
            ),
          ),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? colors.accent
                  : Colors.transparent,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          ),
          animationDuration: const Duration(milliseconds: 180),
          splashFactory: NoSplash.splashFactory,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              SvgPicture.asset(icon!, width: 17, height: 17),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
