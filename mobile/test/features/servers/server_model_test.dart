import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/servers/server_model.dart';

void main() {
  test('parses host-list entry into ServerModel', () {
    final model = ServerModel.fromJson({
      'id': 'h1',
      'name': 'prod',
      'host': '10.0.0.2',
      'port': 22,
      'username': 'root',
      'authType': 'password',
      'group': 'g1',
      'tag': ['a', 'b'],
      'expired': false,
      'isConfig': true,
    });

    expect(model.id, 'h1');
    expect(model.host, '10.0.0.2');
    expect(model.port, 22);
    expect(model.tag, ['a', 'b']);
    expect(model.canConnect, isTrue);
  });

  test('falls back to _id and default port', () {
    final model = ServerModel.fromJson({
      '_id': 'h2',
      'name': 'fallback',
      'host': '10.0.0.3',
      'username': 'root',
      'authType': 'credential',
      'group': '',
      'expired': false,
      'isConfig': true,
    });

    expect(model.id, 'h2');
    expect(model.port, 22);
    expect(model.tag, isEmpty);
  });

  test('canConnect is false when expired or not configured', () {
    final expired = ServerModel.fromJson({
      'id': 'h3',
      'name': 'old',
      'host': '10.0.0.4',
      'port': 22,
      'username': 'root',
      'authType': 'password',
      'group': '',
      'tag': const [],
      'expired': true,
      'isConfig': true,
    });
    final unconfigured = ServerModel.fromJson({
      'id': 'h4',
      'name': 'broken',
      'host': '10.0.0.5',
      'port': 22,
      'username': 'root',
      'authType': '',
      'group': '',
      'tag': const [],
      'expired': false,
      'isConfig': false,
    });

    expect(expired.canConnect, isFalse);
    expect(unconfigured.canConnect, isFalse);
  });
}
