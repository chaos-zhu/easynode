import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/features/servers/server_list_config.dart';
import 'package:easynode_native/features/servers/server_list_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiClient {
  _Api()
    : super(
        serverAddress: 'https://example.com',
        cookieStore: SessionCookieStore.memory(),
      );

  Map<String, dynamic> response = {};
  final requests =
      <({String method, String path, Map<String, dynamic>? data})>[];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add((method: 'GET', path: path, data: null));
    return response;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    requests.add((method: 'POST', path: path, data: data));
    return {'status': 200};
  }
}

void main() {
  test(
    'reads Web list preferences and saves only the two supported settings',
    () async {
      final api = _Api();
      addTearDown(api.close);
      api.response = {
        'data': {
          'columnSettings': {
            'username': false,
            'proxyType': true,
            'futureColumn': true,
            'index': true,
          },
          'displayMode': 'list',
          'unrelatedConfig': 'keep on server',
        },
      };
      final repository = ApiServerListConfigRepository(api);
      final config = await repository.fetch();
      expect(config.shows('username'), isFalse);
      expect(config.shows('proxyType'), isTrue);
      expect(config.shows('name'), isTrue);
      expect(config.displayMode, 'list');
      final edited = config.withColumn('tag', false).withDisplayMode('group');
      await repository.save(edited);
      expect(config.shows('tag'), isTrue);
      expect(api.requests.map((r) => '${r.method} ${r.path}'), [
        'GET /server-list-config',
        'POST /server-list-config',
      ]);
      expect(
        api.requests.last.data!.keys,
        unorderedEquals(['columnSettings', 'displayMode']),
      );
      final columns = api.requests.last.data!['columnSettings'] as Map;
      expect(columns['futureColumn'], isTrue);
      expect(columns.containsKey('index'), isFalse);
      expect(columns['tag'], isFalse);
      expect(api.requests.last.data!['displayMode'], 'group');
    },
  );

  test('missing or invalid individual values retain server defaults', () {
    final config = ServerListConfig.fromJson({
      'columnSettings': {'name': 'false', 'host': null, 'tag': false},
      'displayMode': 'unknown',
    });
    expect(config.shows('name'), isTrue);
    expect(config.shows('host'), isTrue);
    expect(config.shows('proxyType'), isFalse);
    expect(config.shows('tag'), isFalse);
    expect(config.displayMode, 'group');
    expect(
      ServerListConfig.fromJson({}).columnSettings,
      ServerListConfig.defaultColumns,
    );
  });

  test(
    'malformed response fails instead of overwriting preferences with defaults',
    () async {
      final api = _Api();
      addTearDown(api.close);
      api.response = {'data': null};
      await expectLater(
        ApiServerListConfigRepository(api).fetch(),
        throwsA(isA<ApiFailure>()),
      );
      expect(api.requests, hasLength(1));
    },
  );
}
