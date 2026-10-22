import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/scripts/script_repository.dart';
import '../features/terminal/desktop/terminal_catalog_order.dart';
import 'api_providers.dart';

/// Shared by the desktop library, terminal menus and execution forms.
final desktopTerminalScriptCatalogProvider =
    FutureProvider.autoDispose<ScriptCatalog>((ref) async {
      final catalog = await ref.watch(scriptRepositoryProvider).fetchCatalog();
      return ScriptCatalog(
        groups: orderTerminalItems(
          catalog.groups,
          catalog.order.sections.map((s) => s.groupId),
          (g) => g.id,
        ),
        scripts: orderTerminalItems(
          catalog.scripts,
          catalog.order.sections.expand((s) => s.itemIds),
          (s) => s.id,
        ),
        order: catalog.order,
      );
    });
