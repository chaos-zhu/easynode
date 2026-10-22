import 'dart:async';

import 'package:easynode_native/features/shell/sftp_session_manager.dart';
import 'package:easynode_native/features/terminal/desktop/sftp_transfer_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tasks execute sequentially and cancellation does not start queued work',
    () async {
      final queue = SftpTransferQueue();
      final gate = Completer<void>();
      final events = <String>[];
      final first = SftpTransferTask(
        name: 'one',
        upload: true,
        run: (task) async {
          events.add('one');
          await gate.future;
        },
      );
      final second = SftpTransferTask(
        name: 'two',
        upload: false,
        run: (task) async {
          events.add('two');
        },
      );
      queue.add(first);
      queue.add(second);
      queue.cancel(second);
      expect(first.status, SftpTransferStatus.running);
      expect(second.status, SftpTransferStatus.cancelled);
      expect(events, ['one']);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(first.status, SftpTransferStatus.complete);
      expect(events, ['one']);
      queue.retry(second);
      await Future<void>.delayed(Duration.zero);
      expect(second.status, SftpTransferStatus.complete);
      expect(events, ['one', 'two']);
      queue.clearFinished();
      expect(queue.tasks, isEmpty);
      queue.dispose();
    },
  );
  test(
    'running cancellation and failed transfer are distinct; retry resets progress',
    () async {
      final queue = SftpTransferQueue();
      final gate = Completer<void>();
      var calls = 0;
      final task = SftpTransferTask(
        name: 'large',
        upload: true,
        run: (task) async {
          calls++;
          if (calls == 1) {
            queue.progress(task, 50, 100);
            await gate.future;
            if (task.cancelRequested) throw const SftpTransferCancelled();
          }
          if (calls == 2) throw StateError('permission denied');
          expect(task.transferred, 0);
          expect(task.error, isNull);
          queue.progress(task, 100, 100);
        },
      );
      queue.add(task);
      queue.cancel(task);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(task.status, SftpTransferStatus.cancelled);
      queue.retry(task);
      await Future<void>.delayed(Duration.zero);
      expect(task.status, SftpTransferStatus.error);
      expect(task.error, contains('permission denied'));
      queue.retry(task);
      await Future<void>.delayed(Duration.zero);
      expect(task.status, SftpTransferStatus.complete);
      expect(task.transferred, 100);
      queue.dispose();
    },
  );
  test('disposing panel requests cancellation and stops its queue', () async {
    final queue = SftpTransferQueue();
    final gate = Completer<void>();
    var secondStarted = false;
    final first = SftpTransferTask(
      name: 'one',
      upload: true,
      run: (_) => gate.future,
    );
    queue.add(first);
    queue.add(
      SftpTransferTask(
        name: 'two',
        upload: true,
        run: (_) async {
          secondStarted = true;
        },
      ),
    );
    queue.dispose();
    expect(first.cancelRequested, true);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(secondStarted, false);
  });
}
