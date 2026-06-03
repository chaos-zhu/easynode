/// Server `GET /plus-info` response shape — `{ data: PlusInfo | null }`.
/// `null` or empty `data` means inactive. The server now reports the runtime
/// activation state directly via `active` (decryptKey present in memory and
/// the session has not been kicked), so the client trusts that boolean instead
/// of re-deriving it from an expiry date.
class PlusInfo {
  const PlusInfo({
    required this.key,
    required this.instanceId,
    required this.active,
    required this.status,
    required this.needRestart,
    required this.error,
  });

  final String key;
  final String instanceId;

  /// Runtime activation state from the server. `true` only when Plus is truly
  /// usable right now (memory decryptKey present and not kicked).
  final bool active;

  /// One of: `active` | `kicked` | `inactive` | `unset`.
  final String status;

  /// `true` when the current process was kicked by the license server and the
  /// user must restart the panel service to re-activate.
  final bool needRestart;

  /// Human-readable error to surface when kicked / abnormal.
  final String error;

  /// Trust the server-reported runtime state.
  bool get isActive => active;

  factory PlusInfo.empty() => const PlusInfo(
        key: '',
        instanceId: '',
        active: false,
        status: 'unset',
        needRestart: false,
        error: '',
      );

  factory PlusInfo.fromJson(Map<String, dynamic> json) {
    bool parseBool(Object? raw) =>
        raw == true || raw == 1 || raw == '1' || raw == 'true';

    return PlusInfo(
      key: (json['key'] ?? '').toString(),
      instanceId: (json['instanceId'] ?? '').toString(),
      active: parseBool(json['active']),
      status: (json['status'] ?? '').toString(),
      needRestart: parseBool(json['needRestart']),
      error: (json['error'] ?? '').toString(),
    );
  }
}

class PlusDiscount {
  const PlusDiscount({required this.discount, required this.content});

  final bool discount;
  final String content;

  factory PlusDiscount.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PlusDiscount(discount: false, content: '');
    return PlusDiscount(
      discount: json['discount'] == true,
      content: (json['content'] ?? '').toString(),
    );
  }
}
