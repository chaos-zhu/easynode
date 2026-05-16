import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/device_id.dart';

class _FakeStore implements DeviceIdStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

void main() {
  test('generates and persists a uuid v4 device id on first read', () async {
    final store = _FakeStore();
    final id = await loadOrCreateDeviceId(store);
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(id),
      isTrue,
      reason: 'expected v4 UUID format but got "$id"',
    );
  });

  test('returns the same id on subsequent reads', () async {
    final store = _FakeStore();
    final first = await loadOrCreateDeviceId(store);
    final second = await loadOrCreateDeviceId(store);
    expect(second, first);
  });
}
