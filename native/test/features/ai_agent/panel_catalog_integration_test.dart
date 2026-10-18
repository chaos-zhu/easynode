import 'dart:async';

import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/core/storage/secure_storage.dart';
import 'package:easynode_native/features/ai_agent/panel_catalog_refresh.dart';
import 'package:easynode_native/features/scripts/script_repository.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:easynode_native/state/agent_providers.dart';
import 'package:easynode_native/state/api_providers.dart';
import 'package:easynode_native/state/group_list_notifier.dart';
import 'package:easynode_native/state/host_list_notifier.dart';
import 'package:easynode_native/state/order_notifiers.dart';
import 'package:easynode_native/state/script_group_list_notifier.dart';
import 'package:easynode_native/state/script_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogApi extends ApiClient {
  _CatalogApi()
    : super(
        serverAddress: 'https://fixture.invalid',
        cookieStore: SessionCookieStore(
          SecureAppStorage(const FlutterSecureStorage()),
        ),
      );

  int revision = 0;
  bool hold = false;
  bool fail = false;
  final requests = <String>[];
  final pending = <Completer<void>>[];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(path);
    final shouldFail = fail;
    final data = {
      if (path == '/host-catalog')
        'hosts': [
          {'_id': 'host', 'name': 'host-$revision', 'host': '127.0.0.1'},
        ]
      else
        'scripts': [
          {'_id': 'script', 'name': 'script-$revision', 'command': 'true'},
        ],
      'groups': [
        {'_id': 'default', 'name': 'group-$revision'},
      ],
      'order': {
        'schemaVersion': 1,
        'revision': revision,
        'sections': [
          {
            'groupId': 'default',
            'itemIds': [path == '/host-catalog' ? 'host' : 'script'],
          },
        ],
      },
    };
    if (hold) {
      final completion = Completer<void>();
      pending.add(completion);
      await completion.future;
    }
    if (shouldFail) throw StateError('offline');
    return {'data': data};
  }
}

ProviderContainer _container(_CatalogApi api) => ProviderContainer(
  overrides: [
    scriptRepositoryProvider.overrideWithValue(
      ApiScriptRepository(apiClient: api),
    ),
    serverRepositoryProvider.overrideWithValue(
      ApiServerRepository(apiClient: api),
    ),
  ],
);

void _expectCatalog(ProviderContainer container, String domain, int revision) {
  if (domain == 'hosts') {
    expect(
      container.read(hostListProvider).requireValue.single.name,
      'host-$revision',
    );
    expect(
      container.read(groupListProvider).requireValue.single.name,
      'group-$revision',
    );
    expect(container.read(hostOrderProvider)?.revision, revision);
  } else {
    expect(
      container.read(scriptListProvider).requireValue.single.name,
      'script-$revision',
    );
    expect(
      container.read(scriptGroupListProvider).requireValue.single.name,
      'group-$revision',
    );
    expect(container.read(scriptOrderProvider)?.revision, revision);
  }
}

void main() {
  for (final domain in ['hosts', 'scripts']) {
    testWidgets(
      '$domain notification waits for old read then fetches fresh catalog',
      (tester) async {
        final api = _CatalogApi()..hold = true;
        final container = _container(api);
        addTearDown(container.dispose);
        final oldReads = domain == 'hosts'
            ? Future.wait<Object>([
                container.read(hostListProvider.future),
                container.read(groupListProvider.future),
              ])
            : Future.wait<Object>([
                container.read(scriptListProvider.future),
                container.read(scriptGroupListProvider.future),
              ]);
        await tester.pump();
        expect(api.requests, hasLength(1));
        var errors = 0;
        final queue = PanelCatalogRefresh(
          refresh: container.read(panelDataRefreshProvider),
          onError: () => errors++,
        );
        addTearDown(queue.dispose);
        api.revision = 1;
        queue.schedule([domain]);
        queue.schedule([domain]);
        await tester.pump(const Duration(milliseconds: 101));
        expect(api.requests, hasLength(1));
        api.hold = false;
        api.pending.single.complete();
        await tester.pump();
        await oldReads;
        await tester.pump(const Duration(milliseconds: 101));
        _expectCatalog(container, domain, 1);
        expect(errors, 0);
        expect(api.requests, hasLength(2));
        expect(api.requests.toSet(), {
          domain == 'hosts' ? '/host-catalog' : '/script-catalog',
        });
      },
    );

    testWidgets('$domain retries after an earlier read failed', (tester) async {
      final api = _CatalogApi()
        ..hold = true
        ..fail = true;
      final container = _container(api);
      addTearDown(container.dispose);
      final Future<Object> oldRead = domain == 'hosts'
          ? container.read(serverRepositoryProvider).fetchCatalog()
          : container.read(scriptRepositoryProvider).fetchCatalog();
      final oldFailure = expectLater(oldRead, throwsStateError);
      var done = false;
      final refresh = container
          .read(panelDataRefreshProvider)({domain})
          .then((_) => done = true);
      await tester.pump();
      expect(done, false);
      api
        ..hold = false
        ..fail = false
        ..revision = 1;
      api.pending.single.complete();
      await tester.pump();
      await oldFailure;
      await refresh;
      _expectCatalog(container, domain, 1);
      expect(api.requests, hasLength(2));
    });

    testWidgets(
      '$domain shares fresh reads and preserves data on refresh failure',
      (tester) async {
        final api = _CatalogApi();
        final container = _container(api);
        addTearDown(container.dispose);
        var errors = 0;
        final queue = PanelCatalogRefresh(
          refresh: container.read(panelDataRefreshProvider),
          onError: () => errors++,
        );
        addTearDown(queue.dispose);
        queue.schedule([domain]);
        await tester.pump(const Duration(milliseconds: 101));
        _expectCatalog(container, domain, 0);
        expect(api.requests, hasLength(1));
        api
          ..revision = 1
          ..fail = true;
        queue.schedule([domain]);
        await tester.pump(const Duration(milliseconds: 101));
        _expectCatalog(container, domain, 0);
        expect(errors, 1);
        expect(api.requests, hasLength(2));
        api
          ..fail = false
          ..hold = true;
        queue.schedule([domain]);
        await tester.pump(const Duration(milliseconds: 101));
        expect(api.requests, hasLength(3));
        api
          ..revision = 2
          ..hold = false;
        queue.schedule([domain]);
        api.pending.single.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 101));
        _expectCatalog(container, domain, 2);
        expect(errors, 1);
        expect(api.requests, hasLength(4));
      },
    );
  }
}
