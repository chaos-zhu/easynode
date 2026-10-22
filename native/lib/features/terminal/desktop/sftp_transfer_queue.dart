import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shell/sftp_session_manager.dart';

enum SftpTransferStatus { queued, running, complete, cancelled, error }

class SftpTransferTask {
  SftpTransferTask({
    required this.name,
    required this.upload,
    required this.run,
  });
  final String name;
  final bool upload;
  final Future<void> Function(SftpTransferTask) run;
  SftpTransferStatus status = SftpTransferStatus.queued;
  bool cancelRequested = false;
  int transferred = 0;
  int? total;
  String? error;
  DateTime? started;
  double get speed => started == null
      ? 0
      : transferred /
            ((DateTime.now().difference(started!).inMilliseconds / 1000).clamp(
              .1,
              double.infinity,
            ));
  bool get unfinished =>
      status == SftpTransferStatus.queued ||
      status == SftpTransferStatus.running;
}

/// One queue per mounted host panel. Switching tabs or hiding SFTP retains it.
class SftpTransferQueue extends ChangeNotifier {
  final List<SftpTransferTask> tasks = [];
  bool _running = false, _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void add(SftpTransferTask task) {
    tasks.add(task);
    _changed();
    unawaited(_drain());
  }

  void progress(SftpTransferTask task, int bytes, int? total) {
    task.transferred = bytes;
    task.total = total;
    _changed();
  }

  void cancel(SftpTransferTask task) {
    task.cancelRequested = true;
    if (task.status == SftpTransferStatus.queued) {
      task.status = SftpTransferStatus.cancelled;
    }
    _changed();
  }

  void retry(SftpTransferTask task) {
    if (task.unfinished || _disposed) return;
    task.cancelRequested = false;
    task.transferred = 0;
    task.total = null;
    task.error = null;
    task.status = SftpTransferStatus.queued;
    _changed();
    unawaited(_drain());
  }

  void clearFinished() {
    tasks.removeWhere((t) => !t.unfinished);
    _changed();
  }

  Future<void> _drain() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (!_disposed) {
        final task = tasks
            .where((t) => t.status == SftpTransferStatus.queued)
            .firstOrNull;
        if (task == null) break;
        task.status = SftpTransferStatus.running;
        task.started = DateTime.now();
        _changed();
        try {
          await task.run(task);
          task.status = task.cancelRequested
              ? SftpTransferStatus.cancelled
              : SftpTransferStatus.complete;
        } on SftpTransferCancelled {
          task.status = SftpTransferStatus.cancelled;
        } catch (e) {
          task.status = SftpTransferStatus.error;
          task.error = e.toString();
        }
        _changed();
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final task in tasks) {
      task.cancelRequested = true;
    }
    super.dispose();
  }
}
