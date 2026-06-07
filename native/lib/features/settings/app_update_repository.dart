import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/utils/app_store_compliance.dart';

const nativeVersionFeedUrl =
    'https://easynode-version.chaoszhu.com/chaos-zhu/easynode/refs/heads/main/server/version.json';
const nativeVersionFeedFallbackUrl =
    'https://raw.githubusercontent.com/chaos-zhu/easynode/refs/heads/main/server/version.json';
const nativeGitHubReleaseUrl = 'https://github.com/chaos-zhu/easynode/releases';
const nativeIosReleaseUrl = '';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    this.features = const <String>[],
  });

  final String latestVersion;
  final String releaseUrl;
  final List<String> features;

  bool get hasReleaseUrl => releaseUrl.trim().isNotEmpty;

  factory AppUpdateInfo.fromVersionJson(Object? json) {
    return AppUpdateInfo.fromVersionJsonOrCurrent(json, currentVersion: null);
  }

  factory AppUpdateInfo.fromVersionJsonOrCurrent(
    Object? json, {
    required String? currentVersion,
  }) {
    final latest = switch (json) {
      final List<Object?> list when list.isNotEmpty => list.first,
      _ => json,
    };
    if (latest is! Map) {
      throw const FormatException('Invalid version feed');
    }

    final nativeVersion = latest['nativeVersion']?.toString().trim();
    if (nativeVersion == null || nativeVersion.isEmpty) {
      if (currentVersion == null || currentVersion.isEmpty) {
        throw const FormatException('Missing nativeVersion');
      }
      return AppUpdateInfo(
        latestVersion: currentVersion,
        releaseUrl: _releaseUrlForPlatform(latest),
      );
    }

    final features = latest['nativeFeatures'];
    final fallbackFeatures = latest['features'];
    return AppUpdateInfo(
      latestVersion: nativeVersion,
      releaseUrl: _releaseUrlForPlatform(latest),
      features: _parseFeatures(features ?? fallbackFeatures),
    );
  }

  static String _releaseUrlForPlatform(Map latest) {
    if (isIosAppStoreCompliance) {
      return (latest['iosReleaseUrl'] ?? nativeIosReleaseUrl).toString().trim();
    }
    return (latest['nativeReleaseUrl'] ?? nativeGitHubReleaseUrl)
        .toString()
        .trim();
  }

  static List<String> _parseFeatures(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.info,
  });

  final String currentVersion;
  final AppUpdateInfo info;

  bool get hasUpdate => info.latestVersion != currentVersion;
}

class AppUpdateRepository {
  AppUpdateRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<AppUpdateCheckResult> check(PackageInfo packageInfo) async {
    final currentVersion = nativeVersionFromPackage(packageInfo);
    final versionJson = await _fetchVersionJson();
    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      info: AppUpdateInfo.fromVersionJsonOrCurrent(
        versionJson,
        currentVersion: currentVersion,
      ),
    );
  }

  Future<Object?> _fetchVersionJson() async {
    Object? lastError;
    for (final baseUrl in const [
      nativeVersionFeedUrl,
      nativeVersionFeedFallbackUrl,
    ]) {
      try {
        final url = _withTimestamp(baseUrl);
        final response = await _dio
            .get<String>(
              url,
              options: Options(
                receiveTimeout: const Duration(seconds: 5),
                responseType: ResponseType.plain,
              ),
            )
            .timeout(const Duration(seconds: 5));
        return jsonDecode(response.data ?? '');
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Failed to fetch native version feed: $lastError');
  }

  String _withTimestamp(String url) {
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}ts=${DateTime.now().millisecondsSinceEpoch}';
  }
}

String nativeVersionFromPackage(PackageInfo packageInfo) {
  return 'native-v${packageInfo.version}';
}

@visibleForTesting
String releaseUrlForPlatformForTest(Map latest) {
  return AppUpdateInfo._releaseUrlForPlatform(latest);
}
