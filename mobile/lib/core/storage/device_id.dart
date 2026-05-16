import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Abstraction over secure-storage so the UUID generator can be unit-tested
/// without touching the platform Keystore/Keychain.
abstract class DeviceIdStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureDeviceIdStore implements DeviceIdStore {
  SecureDeviceIdStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'mobileDeviceId';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Returns the persisted per-install device id, generating and storing a new
/// UUID v4 if none exists yet.
Future<String> loadOrCreateDeviceId(DeviceIdStore store) async {
  final existing = await store.read();
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await store.write(id);
  return id;
}
