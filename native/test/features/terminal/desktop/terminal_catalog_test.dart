import 'package:easynode_native/features/scripts/script_repository.dart';
import 'package:easynode_native/features/terminal/desktop/desktop_terminal_scripts.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements ScriptRepository {
  @override
  Future<ScriptCatalog> fetchCatalog() async => ScriptCatalog.fromJson({
    'groups': [
      {'_id': 'default', 'name': 'Default'},
      {'_id': 'custom', 'name': 'Custom'},
    ],
    'scripts': [
      {'_id': 'a', 'group': 'custom', 'name': 'A', 'command': 'echo A'},
      {'_id': 'b', 'group': 'custom', 'name': 'B', 'command': 'echo B'},
      {'_id': 'new', 'group': 'default', 'name': 'New', 'command': 'echo new'},
    ],
    'order': {
      'sections': [
        {
          'groupId': 'custom',
          'itemIds': ['b', 'removed', 'a'],
        },
        {'groupId': 'default', 'itemIds': []},
      ],
    },
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'script menus follow saved group/item order and retain new records',
    () async {
      final container = ProviderContainer(
        overrides: [scriptRepositoryProvider.overrideWithValue(_Repository())],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(
        desktopTerminalScriptCatalogProvider.future,
      );
      expect(catalog.groups.map((g) => g.id), ['custom', 'default']);
      expect(catalog.scripts.map((s) => s.id), ['b', 'a', 'new']);
    },
  );
}
