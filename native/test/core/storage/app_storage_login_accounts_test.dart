import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppStorage> createStorage([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    return AppStorage(await SharedPreferences.getInstance());
  }

  test(
    'migrates the legacy current account into the saved account list',
    () async {
      final storage = await createStorage({
        'serverAddress': 'https://legacy.example.com',
        'username': 'root',
        'savePassword': true,
      });

      expect(storage.savedLoginAccounts, hasLength(1));
      expect(
        storage.savedLoginAccounts.single.serverAddress,
        'https://legacy.example.com',
      );
      expect(storage.savedLoginAccounts.single.username, 'root');
      expect(storage.savedLoginAccounts.single.savePassword, isTrue);
    },
  );

  test('upserts accounts in most recently used order', () async {
    final storage = await createStorage();
    const first = SavedLoginAccount(
      serverAddress: 'https://one.example.com',
      username: 'root',
      savePassword: false,
    );
    const second = SavedLoginAccount(
      serverAddress: 'https://two.example.com',
      username: 'admin',
      savePassword: true,
    );

    await storage.upsertSavedLoginAccount(first);
    await storage.upsertSavedLoginAccount(second);
    await storage.upsertSavedLoginAccount(
      const SavedLoginAccount(
        serverAddress: 'https://one.example.com',
        username: 'root',
        savePassword: true,
      ),
    );

    final accounts = storage.savedLoginAccounts;
    expect(accounts.map((item) => item.serverAddress), [
      'https://one.example.com',
      'https://two.example.com',
    ]);
    expect(accounts.first.savePassword, isTrue);
  });

  test('removes only the requested saved account', () async {
    final storage = await createStorage();
    const first = SavedLoginAccount(
      serverAddress: 'https://one.example.com',
      username: 'root',
      savePassword: false,
    );
    const second = SavedLoginAccount(
      serverAddress: 'https://two.example.com',
      username: 'admin',
      savePassword: false,
    );
    await storage.upsertSavedLoginAccount(first);
    await storage.upsertSavedLoginAccount(second);

    await storage.removeSavedLoginAccount(first);

    expect(storage.savedLoginAccounts, hasLength(1));
    expect(
      storage.savedLoginAccounts.single.serverAddress,
      second.serverAddress,
    );
  });
}
