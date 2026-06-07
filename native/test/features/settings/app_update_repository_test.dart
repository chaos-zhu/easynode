import 'package:easynode_native/features/settings/app_update_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('nativeVersionFromPackage prefixes the app version', () {
    final packageInfo = PackageInfo(
      appName: 'EasyNode',
      packageName: 'io.github.chaoszhu.easynode',
      version: '0.1.0-beta.1',
      buildNumber: '2',
    );

    expect(nativeVersionFromPackage(packageInfo), 'native-v0.1.0-beta.1');
  });

  test('AppUpdateInfo reads the first entry from version json', () {
    final info = AppUpdateInfo.fromVersionJson([
      {
        'version': 'v3.7.0',
        'nativeVersion': 'native-v0.1.0-beta.2',
        'nativeReleaseUrl': 'https://example.com/releases',
        'nativeFeatures': ['Native update check'],
      },
    ]);

    expect(info.latestVersion, 'native-v0.1.0-beta.2');
    expect(info.releaseUrl, 'https://example.com/releases');
    expect(info.features, ['Native update check']);
  });

  test('AppUpdateCheckResult reports different native versions as update', () {
    final result = AppUpdateCheckResult(
      currentVersion: 'native-v0.1.0-beta.1',
      info: const AppUpdateInfo(
        latestVersion: 'native-v0.1.0-beta.2',
        releaseUrl: nativeGitHubReleaseUrl,
      ),
    );

    expect(result.hasUpdate, isTrue);
  });

  test('missing nativeVersion falls back to the current native version', () {
    final info = AppUpdateInfo.fromVersionJsonOrCurrent([
      {
        'version': 'v3.6.1',
        'features': ['web release only'],
      },
    ], currentVersion: 'native-v0.1.0-beta.1');

    expect(info.latestVersion, 'native-v0.1.0-beta.1');
    expect(info.releaseUrl, nativeGitHubReleaseUrl);
  });
}
