import '../../core/api/api_client.dart';

class BatchRecord {
  BatchRecord.fromJson(Map value, {this.pending = false})
    : id = '${value['id'] ?? value['_id'] ?? ''}',
      batchId = '${value['batchId'] ?? ''}',
      hostId = '${value['hostId'] ?? ''}',
      name = '${value['name'] ?? ''}',
      host = '${value['host'] ?? ''}',
      port = '${value['port'] ?? 22}',
      command = '${value['command'] ?? ''}',
      status = '${value['status'] ?? ''}',
      output = '${value['result'] ?? ''}',
      start = _date(value['startDate']),
      end = _date(value['endDate']);
  final String id, batchId, hostId, name, host, port, command, status, output;
  final DateTime? start, end;
  final bool pending;
  String get key => batchId.isEmpty ? id : '$batchId:$hostId';
  bool get canStop => pending && const {'连接中', '执行中'}.contains(status);
}

class BatchRecordPage {
  BatchRecordPage.fromJson(Map data)
    : items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map(BatchRecord.fromJson)
          .toList(),
      total = (data['total'] as num?)?.toInt() ?? 0,
      page = (data['page'] as num?)?.toInt() ?? 1;
  final List<BatchRecord> items;
  final int total, page;
}

class BatchOutput {
  BatchOutput.fromJson(Map data)
    : text = '${data['result'] ?? ''}',
      nextOffset = (data['nextOffset'] as num?)?.toInt() ?? 0,
      hasMore = data['hasMore'] == true;
  final String text;
  final int nextOffset;
  final bool hasMore;
}

class BatchRepository {
  const BatchRepository(this.api);
  final ApiClient api;
  Future<BatchRecordPage> fetch({int page = 1, int pageSize = 20}) async {
    final response = await api.getJson(
      '/onekey',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return BatchRecordPage.fromJson(response['data'] as Map);
  }

  Future<BatchOutput> output(String id, {int offset = 0}) async {
    final response = await api.getJson(
      '/onekey/${Uri.encodeComponent(id)}/output',
      queryParameters: {'offset': offset},
    );
    return BatchOutput.fromJson(response['data'] as Map);
  }

  Future<void> delete(Object ids) async {
    await api.postJson('/onekey', {'ids': ids});
  }
}

DateTime? _date(Object? raw) {
  final n = raw is num ? raw.toInt() : int.tryParse('$raw');
  return n == null ? null : DateTime.fromMillisecondsSinceEpoch(n);
}
