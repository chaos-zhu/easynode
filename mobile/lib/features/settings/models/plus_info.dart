/// Server `GET /plus-info` response shape — `{ data: PlusInfo | null }`.
/// `null` or empty `data` means inactive. Active records carry expiry + IP
/// usage statistics from the license server.
class PlusInfo {
  const PlusInfo({
    required this.key,
    required this.expiryDate,
    required this.usedIPCount,
    required this.maxIPs,
    required this.usedIPs,
  });

  final String key;
  final String expiryDate;
  final int usedIPCount;
  final int maxIPs;
  final List<String> usedIPs;

  bool get isActive => key.isNotEmpty;

  factory PlusInfo.empty() => const PlusInfo(
        key: '',
        expiryDate: '',
        usedIPCount: 0,
        maxIPs: 0,
        usedIPs: [],
      );

  factory PlusInfo.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? 0;
      return 0;
    }

    final ips = (json['usedIPs'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const <String>[];

    return PlusInfo(
      key: (json['key'] ?? '').toString(),
      expiryDate: (json['expiryDate'] ?? '').toString(),
      usedIPCount: parseInt(json['usedIPCount']),
      maxIPs: parseInt(json['maxIPs']),
      usedIPs: ips,
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
