import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Resolves the running app's version / build number from the platform's
/// PackageInfo so UI surfaces don't hardcode strings that drift from
/// `pubspec.yaml`. Cached for the lifetime of the process — package info
/// never changes after install.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});
