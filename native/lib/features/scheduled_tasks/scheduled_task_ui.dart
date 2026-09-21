import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../core/ui/app_color_theme.dart';
import '../../l10n/app_localizations.dart';

String scheduledTaskStatusLabel(AppLocalizations l, String status) {
  final key = 'scheduledTasks.status.$status';
  final label = l.tr(key);
  return label == key ? status : label;
}

Color scheduledTaskStatusColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'success' => c.success,
    'running' => c.primary,
    'partial' || 'timeout' || 'skipped' || 'interrupted' => c.warning,
    'failed' || 'cancelled' => c.danger,
    _ => c.muted,
  };
}

bool _timezonesInitialized = false;

String formatTaskDate(DateTime? value, {String? timezoneName}) {
  if (value == null) return '--';
  var displayValue = value.toLocal();
  if (timezoneName?.isNotEmpty == true) {
    if (!_timezonesInitialized) {
      timezone_data.initializeTimeZones();
      _timezonesInitialized = true;
    }
    try {
      displayValue = timezone.TZDateTime.from(
        value,
        timezone.getLocation(timezoneName!),
      );
    } on timezone.LocationNotFoundException {
      // Keep the device-local fallback for legacy records with an invalid zone.
    }
  }
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(displayValue);
}

String formatTaskDuration(int milliseconds) {
  if (milliseconds <= 0) return '--';
  if (milliseconds < 1000) return '$milliseconds ms';
  final seconds = milliseconds / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).round();
  return '${minutes}m ${rest}s';
}

class ScheduledTaskStatusChip extends StatelessWidget {
  const ScheduledTaskStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = scheduledTaskStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        scheduledTaskStatusLabel(l, status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
