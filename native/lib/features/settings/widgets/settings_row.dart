import 'package:flutter/material.dart';

import '../../../core/ui/app_color_theme.dart';

/// A single row inside a [SettingsSection]: 36×36 icon box on the left,
/// title (+ optional subtitle) in the middle, optional trailing chip, and a
/// trailing chevron when [onTap] is provided.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final titleColor = danger ? context.colors.danger : context.colors.text;
    final iconColor = danger ? context.colors.danger : context.colors.primary;
    final iconBg = danger ? context.colors.dangerSoft : context.colors.chip;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: context.colors.softMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.colors.softMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
