import 'dart:async';

/// Coalesces live mutation notices. History rendering never enters this queue.
class PanelCatalogRefresh {
  PanelCatalogRefresh({required this.refresh, required this.onError});

  final Future<void> Function(Set<String>) refresh;
  final void Function() onError;
  final _domains = <String>{};
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  void schedule(Object? domains) {
    if (_disposed) return;
    if (domains is List) {
      _domains.addAll(
        domains.whereType<String>().where(
          (domain) =>
              const {'hosts', 'scripts', 'scheduled_tasks'}.contains(domain),
        ),
      );
    }
    if (_domains.isEmpty || _timer != null || _running) return;
    _timer = Timer(const Duration(milliseconds: 100), _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    _running = true;
    final domains = {..._domains};
    _domains.clear();
    try {
      await refresh(domains);
    } catch (_) {
      if (!_disposed) onError();
    } finally {
      _running = false;
      schedule(null);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _domains.clear();
  }
}
