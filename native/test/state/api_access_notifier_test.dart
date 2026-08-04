import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/state/api_access_notifier.dart';
import 'package:easynode_native/state/auth_notifier.dart';
import 'package:easynode_native/state/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAuthNotifier extends AuthNotifier {
  _RecordingAuthNotifier(Ref ref) : super(ref, AuthState.empty);

  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ProviderContainer container;
  late _RecordingAuthNotifier auth;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          auth = _RecordingAuthNotifier(ref);
          return auth;
        }),
      ],
    );
    container.read(authProvider);
  });

  tearDown(() => container.dispose());

  test('deduplicates concurrent unauthorized sign-outs', () async {
    final notifier = container.read(apiAccessProvider.notifier);
    final first = notifier.handleSessionFailure(
      UnauthorizedFailure('expired', statusCode: 401),
    );
    final second = notifier.handleSessionFailure(
      UnauthorizedFailure('expired again', statusCode: 403),
    );

    await Future.wait([first, second]);

    expect(auth.signOutCalls, 1);
    expect(container.read(apiAccessProvider).signOutReason, 'expired');
  });

  test('IP access denial preserves auth and raises blocking state', () async {
    await container
        .read(apiAccessProvider.notifier)
        .handleSessionFailure(IpAccessDeniedFailure('denied', statusCode: 403));

    expect(auth.signOutCalls, 0);
    expect(container.read(apiAccessProvider).ipAccessDenied, isTrue);
  });

  test('reset clears access state and allows a later sign-out', () async {
    final notifier = container.read(apiAccessProvider.notifier);
    await notifier.handleSessionFailure(
      UnauthorizedFailure('expired', statusCode: 401),
    );
    notifier.reset();
    await notifier.handleSessionFailure(
      UnauthorizedFailure('new session expired', statusCode: 401),
    );

    expect(auth.signOutCalls, 2);
    expect(
      container.read(apiAccessProvider).signOutReason,
      'new session expired',
    );
  });
}
