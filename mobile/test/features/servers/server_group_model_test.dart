import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/servers/server_group_model.dart';

void main() {
  test('parses group entry into ServerGroupModel', () {
    final model = ServerGroupModel.fromJson({
      'id': 'default',
      'name': 'Default group',
      'index': 1,
    });

    expect(model.id, 'default');
    expect(model.name, 'Default group');
    expect(model.index, 1);
    expect(model.isDefault, isTrue);
  });

  test('falls back to _id and default index', () {
    final model = ServerGroupModel.fromJson({
      '_id': 'g2',
      'name': 'Overseas',
    });

    expect(model.id, 'g2');
    expect(model.name, 'Overseas');
    expect(model.index, 0);
    expect(model.isDefault, isFalse);
  });
}
