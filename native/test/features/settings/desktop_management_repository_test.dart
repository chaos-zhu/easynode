import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/features/batch/batch_repository.dart';
import 'package:easynode_native/features/scripts/desktop_script_dialogs.dart';
import 'package:easynode_native/features/scripts/script_repository.dart';
import 'package:easynode_native/features/settings/desktop_mcp_settings.dart';
import 'package:easynode_native/features/settings/desktop_settings_repository.dart';
import 'package:easynode_native/features/ai_agent/agent_mcp_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiClient {
  _Api()
    : super(
        serverAddress: 'https://panel.example.com',
        cookieStore: SessionCookieStore.memory(),
      );
  final calls =
      <
        ({
          String method,
          String path,
          Map<String, dynamic>? body,
          Map<String, dynamic>? query,
        })
      >[];
  final responses = <Map<String, dynamic>>[];
  Map<String, dynamic> respond(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) {
    calls.add((method: method, path: path, body: body, query: query));
    return responses.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => respond('GET', path, query: queryParameters);
  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async => respond('POST', path, body: data);
  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> data,
  ) async => respond('PUT', path, body: data);
}

void main() {
  test(
    'batch uses server history pagination, chunk offsets and deletion contracts',
    () async {
      final api = _Api();
      final repo = BatchRepository(api);
      api.responses.addAll([
        {
          'data': {
            'items': [
              {
                'id': 'record',
                'hostId': 'host',
                'batchId': 'batch',
                'status': '执行成功',
                'startDate': 1000,
              },
            ],
            'total': 53,
            'page': 2,
          },
        },
        {
          'data': {'result': 'first', 'nextOffset': 5, 'hasMore': true},
        },
        {
          'data': {'result': 'next', 'nextOffset': 9, 'hasMore': false},
        },
        {},
        {},
      ]);
      final page = await repo.fetch(page: 2, pageSize: 20);
      expect(page.total, 53);
      expect(page.items.single.key, 'batch:host');
      expect(
        page.items.single.start,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final first = await repo.output('record');
      expect(first.hasMore, true);
      final next = await repo.output('record', offset: first.nextOffset);
      expect(next.text, 'next');
      await repo.delete(['record']);
      await repo.delete('ALL');
      expect(api.calls[0].query, {'page': 2, 'pageSize': 20});
      expect(api.calls[1].path, '/onekey/record/output');
      expect(api.calls[2].query, {'offset': 5});
      expect(api.calls[3].body, {
        'ids': ['record'],
      });
      expect(api.calls[4].body, {'ids': 'ALL'});
    },
  );

  test('notifications and Plus write the same payloads as Web', () async {
    final api = _Api();
    final repo = DesktopSettingsRepository(api);
    api.responses.addAll([
      {
        'data': {'type': 'tg'},
      },
      {
        'data': [
          {'type': 'login', 'sw': true},
        ],
      },
      {},
      {},
      {},
      {
        'data': {'deviceLimit': 2, 'devices': []},
      },
      {},
    ]);
    expect((await repo.notificationConfig())['type'], 'tg');
    expect((await repo.notificationEvents()).single['sw'], true);
    await repo.saveNotifications({
      'type': 'tg',
      'tg': {'token': 'secret', 'chatId': '-100'},
    });
    await repo.toggleNotification('login', false);
    await repo.activatePlus('license-key');
    expect((await repo.plusDevices())['deviceLimit'], 2);
    await repo.releasePlusDevice('remote');
    expect(api.calls.map((r) => '${r.method} ${r.path}'), [
      'GET /notify-config',
      'GET /notify',
      'PUT /notify-config',
      'PUT /notify',
      'POST /plus-conf',
      'GET /plus-devices',
      'POST /plus-release',
    ]);
    expect(api.calls[2].body, {
      'noticeConfig': {
        'type': 'tg',
        'tg': {'token': 'secret', 'chatId': '-100'},
      },
    });
    expect(api.calls[3].body, {'type': 'login', 'sw': false});
    expect(api.calls[6].body, {'targetInstanceId': 'remote'});
  });

  test(
    'MCP edits omit masked secrets, replace explicit secrets and remove authentication',
    () {
      final existing = AgentMcpServer.fromJson({
        'id': 'mcp',
        'headers': {'authorization': '***'},
      });
      Map<String, dynamic> payload(
        bool auth,
        String secret, {
        bool create = false,
      }) => desktopMcpPayload(
        name: ' Test ',
        key: 'test',
        url: 'https://example.com/mcp',
        enabled: true,
        connectTimeout: 10,
        callTimeout: 60,
        authorization: auth,
        secret: secret,
        existing: create ? null : existing,
      );
      expect(payload(true, '').containsKey('headers'), false);
      expect(payload(true, ' Bearer replacement ')['headers'], {
        'authorization': 'Bearer replacement',
      });
      expect(payload(false, '')['headers'], isEmpty);
      expect(payload(true, '', create: true)['headers'], isEmpty);
      expect(payload(true, '')['name'], 'Test');
    },
  );

  test(
    'script import handles nested files and deduplicates against catalog and files',
    () {
      final catalog = ScriptCatalog.fromJson({
        'scripts': [
          {'id': 'old', 'command': 'uptime'},
        ],
      });
      final rows = prepareScriptImport(
        [
          [
            {'id': 'old', 'command': 'changed'},
            {'command': 'uptime'},
          ],
          [
            {
              'name': 'List',
              'command': 'ls',
              'group': 'stale',
              'useBase64': true,
            },
            {'command': 'ls'},
            {'command': 'date'},
          ],
        ],
        catalog,
        'target',
      );
      expect(rows.map((r) => r['command']), ['ls', 'date']);
      expect(rows.every((r) => r['group'] == 'target'), true);
      expect(rows.first['useBase64'], true);
      expect(rows.last['name'], 'date');
      expect(rows.first.containsKey('id'), false);
      expect(
        () => prepareScriptImport(
          [
            {'name': 'broken'},
          ],
          catalog,
          'target',
        ),
        throwsFormatException,
      );
    },
  );

  test('script import preserves protocol and returns imported count', () async {
    final api = _Api()
      ..responses.add({
        'data': {'len': 2},
      });
    final scripts = [
      {'name': 'A', 'command': 'ls', 'group': 'default', 'useBase64': false},
    ];
    expect(await ApiScriptRepository(apiClient: api).importScripts(scripts), 2);
    expect(api.calls.single.path, '/import-script');
    expect(api.calls.single.body, {'scripts': scripts});
  });
}
