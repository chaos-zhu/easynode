import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../l10n/app_localizations.dart';

abstract final class SftpMediaPalette {
  static const surface = Color(0xFFF7EFE0);
  static const card = Color(0xFFFBF5E6);
  static const border = Color(0xFFE2D5B3);
  static const text = Color(0xFF2A2418);
  static const muted = Color(0xFF6B5E3F);
  static const mediaSurface = Color(0xFF0A0F14);
}

class SftpMediaTopBar extends StatelessWidget {
  const SftpMediaTopBar({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(color: SftpMediaPalette.surface),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left, color: SftpMediaPalette.text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SftpMediaPalette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SftpMediaPalette.muted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SftpMediaProgressIndicator extends StatelessWidget {
  const SftpMediaProgressIndicator({
    super.key,
    required this.received,
    required this.total,
  });

  final int received;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ratio = (total != null && total! > 0) ? received / total! : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                value: ratio,
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              ratio == null
                  ? l.tr('media.downloading')
                  : '${(ratio * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class SftpMediaInfoCard extends StatelessWidget {
  const SftpMediaInfoCard({
    super.key,
    required this.format,
    required this.size,
    required this.modifyTime,
    required this.path,
  });

  final String format;
  final int? size;
  final DateTime? modifyTime;
  final String path;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: SftpMediaPalette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SftpMediaPalette.border),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.tr('media.info.title'),
              style: const TextStyle(
                color: SftpMediaPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _MediaInfoRow(
              label: l.tr('media.info.format'),
              value: format.toUpperCase(),
            ),
            const SizedBox(height: 6),
            _MediaInfoRow(
              label: l.tr('media.info.size'),
              value: formatMediaBytes(size),
            ),
            const SizedBox(height: 6),
            _MediaInfoRow(
              label: l.tr('media.info.modifiedTime'),
              value: formatMediaDate(modifyTime),
            ),
            const SizedBox(height: 6),
            _MediaInfoRow(
              label: l.tr('media.info.path'),
              value: path,
              monospace: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaInfoRow extends StatelessWidget {
  const _MediaInfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: SftpMediaPalette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: SftpMediaPalette.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

String formatMediaBytes(int? size) {
  if (size == null) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = size.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '${value.toInt()} ${units[unit]}'
      : '${value.toStringAsFixed(1)} ${units[unit]}';
}

String formatMediaDate(DateTime? date) {
  if (date == null) return '-';
  final l = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} '
      '${two(l.hour)}:${two(l.minute)}';
}

String parentDirOf(String path) {
  if (path == '/' || path.isEmpty) return '/';
  final trimmed = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final i = trimmed.lastIndexOf('/');
  if (i <= 0) return '/';
  return trimmed.substring(0, i);
}

Future<File> resolveSftpMediaCacheFile(String fileName) async {
  final dir = await getTemporaryDirectory();
  final cacheDir = Directory('${dir.path}/sftp_media');
  if (!await cacheDir.exists()) {
    await cacheDir.create(recursive: true);
  }
  final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return File('${cacheDir.path}/${stamp}_$safe');
}
