import 'package:easynode_native/core/api/api_client.dart';
import 'package:easynode_native/core/api/cookie_store.dart';
import 'package:easynode_native/features/order/order_layout.dart';
import 'package:easynode_native/features/servers/desktop_server_order_draft.dart';
import 'package:easynode_native/features/servers/server_group_repository.dart';
import 'package:easynode_native/features/servers/server_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiClient {
  _Api()
    : super(
        serverAddress: 'https://example.com',
        cookieStore: SessionCookieStore.memory(),
      );
  final calls = <({String method, String path, Map<String, dynamic>? data})>[];
  Map<String, dynamic> response = {'status': 200};

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    calls.add((method: 'POST', path: path, data: data));
    return response;
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    calls.add((method: 'PUT', path: path, data: data));
    return response;
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add((method: 'DELETE', path: path, data: null));
    return response;
  }
}

void main() {
  test('group CRUD uses Web endpoints and submits metadata only', () async {
    final api = _Api();
    addTearDown(api.close);
    final repository = ApiServerGroupRepository(api);
    await repository.create('Operations');
    await repository.rename('group/1', 'Production');
    await repository.delete('group/1');
    expect(api.calls.map((c) => '${c.method} ${c.path}'), [
      'POST /group',
      'PUT /group/group%2F1',
      'DELETE /group/group%2F1',
    ]);
    expect(api.calls.map((c) => c.data), [
      {'name': 'Operations'},
      {'name': 'Production'},
      null,
    ]);
  });

  test(
    'ordering uses the existing revision-based API and reads its result',
    () async {
      final api = _Api();
      addTearDown(api.close);
      api.response = {
        'data': {
          'schemaVersion': 1,
          'revision': 8,
          'sections': [
            {
              'groupId': 'default',
              'itemIds': ['b', 'a'],
            },
          ],
          'flatItemIds': ['a', 'b'],
        },
      };
      final layout = await ApiServerRepository(apiClient: api).updateOrder(
        7,
        const [
          OrderChange(
            scope: 'groupItems',
            groupId: 'default',
            orderedIds: ['b', 'a'],
          ),
        ],
      );
      expect(api.calls.single.method, 'PUT');
      expect(api.calls.single.path, '/host-order');
      expect(api.calls.single.data, {
        'revision': 7,
        'changes': [
          {
            'scope': 'groupItems',
            'groupId': 'default',
            'orderedIds': ['b', 'a'],
          },
        ],
      });
      expect(layout.revision, 8);
      expect(layout.sections.single.itemIds, ['b', 'a']);
      expect(layout.flatItemIds, ['a', 'b']);
    },
  );

  test(
    'draft changes are isolated and normalized moves work in both directions',
    () {
      const layout = OrderLayout(
        schemaVersion: 1,
        revision: 7,
        sections: [
          OrderSection(groupId: 'default', itemIds: ['a', 'b', 'c']),
        ],
        flatItemIds: ['c', 'b', 'a'],
      );
      final draft = DesktopServerOrderDraft(layout);
      DesktopServerOrderDraft.move(draft.items['default']!, 0, 2);
      expect(draft.items['default'], ['b', 'c', 'a']);
      DesktopServerOrderDraft.move(draft.items['default']!, 2, 0);
      expect(draft.items['default'], ['a', 'b', 'c']);
      DesktopServerOrderDraft.move(draft.flat, 2, 0);
      expect(draft.flat, ['a', 'c', 'b']);
      expect(layout.flatItemIds, ['c', 'b', 'a']);
      final changes = draft.instanceChanges(grouped: false);
      DesktopServerOrderDraft.move(draft.flat, 0, 2);
      expect(changes.single.orderedIds, ['a', 'c', 'b']);
    },
  );
}
