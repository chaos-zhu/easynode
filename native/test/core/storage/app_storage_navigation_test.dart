import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppStorage> createStorage(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return AppStorage(await SharedPreferences.getInstance());
  }

  test(
    'adds scheduled tasks before settings in an existing navigation order',
    () async {
      final storage = await createStorage({
        'app.tabOrder': ['scripts', 'servers', 'settings', 'docker', 'sftp'],
      });

      expect(storage.tabOrder, [
        'scripts',
        'servers',
        'scheduledTasks',
        'settings',
        'docker',
        'sftp',
      ]);
    },
  );

  test('filters unknown and duplicate navigation entries', () async {
    final storage = await createStorage({
      'app.tabOrder': [
        'servers',
        'unknown',
        'servers',
        'settings',
        'scheduledTasks',
      ],
    });

    expect(storage.tabOrder, [
      'servers',
      'settings',
      'scheduledTasks',
      'sftp',
      'docker',
      'scripts',
    ]);
  });
}
