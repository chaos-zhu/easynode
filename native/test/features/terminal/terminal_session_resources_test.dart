import 'package:flutter_test/flutter_test.dart';

import 'package:easynode_native/features/terminal/terminal_session_resources.dart';

void main() {
  group('TerminalSessionResources', () {
    test('reuses terminal-scoped managers for the same host', () {
      final resources = TerminalSessionResources();

      expect(
        identical(
          resources.sftpForHost('host-a'),
          resources.sftpForHost('host-a'),
        ),
        isTrue,
      );
      expect(
        identical(
          resources.dockerForHost('host-a'),
          resources.dockerForHost('host-a'),
        ),
        isTrue,
      );

      resources.dispose();
    });

    test('keeps managers for different hosts independent', () {
      final resources = TerminalSessionResources();

      expect(
        identical(
          resources.sftpForHost('host-a'),
          resources.sftpForHost('host-b'),
        ),
        isFalse,
      );
      expect(
        identical(
          resources.dockerForHost('host-a'),
          resources.dockerForHost('host-b'),
        ),
        isFalse,
      );

      resources.dispose();
    });
  });
}
