import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/features/shell/sftp_session_manager.dart';

void main() {
  group('Sftp text exceptions', () {
    test('SftpFileTooLargeException carries size info', () {
      final err = SftpFileTooLargeException(
        path: '/tmp/big.log',
        size: 5 * 1024 * 1024,
        limit: 2 * 1024 * 1024,
      );
      expect(err.path, '/tmp/big.log');
      expect(err.size, 5 * 1024 * 1024);
      expect(err.limit, 2 * 1024 * 1024);
      expect(err.toString(), contains('big.log'));
    });

    test('SftpBinaryFileException carries path', () {
      final err = SftpBinaryFileException(path: '/usr/bin/ls');
      expect(err.path, '/usr/bin/ls');
      expect(err.toString(), contains('ls'));
    });
  });
}
