import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_color_theme.dart';
import 'desktop_form_controls.dart';

/// Shared desktop management surface; show with `showAppDialog` for transitions.
class DesktopManagementDialog extends StatelessWidget {
  const DesktopManagementDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.busy = false,
    this.width = 680,
    this.topAligned = false,
    this.topInsetFraction = .03,
    this.bodyPadding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool busy;
  final double width;
  final bool topAligned;
  final double topInsetFraction;
  final EdgeInsets bodyPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: !busy,
      child: Dialog(
        alignment: topAligned ? Alignment.topCenter : null,
        insetPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: topAligned
              ? MediaQuery.sizeOf(context).height * topInsetFraction
              : 24,
        ),
        constraints: BoxConstraints(maxWidth: width),
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(
            filledButtonTheme: FilledButtonThemeData(
              style: desktopButtonStyle(context, primary: true),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: desktopButtonStyle(context),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colors.border.withValues(alpha: .6),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context).tr('common.close'),
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 17),
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(padding: bodyPadding, child: body),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.border.withValues(alpha: .6)),
                  ),
                ),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
