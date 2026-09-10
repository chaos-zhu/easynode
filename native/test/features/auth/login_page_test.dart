import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/features/auth/auth_session.dart';
import 'package:easynode_native/features/auth/login_controller.dart';
import 'package:easynode_native/features/auth/login_page.dart';
import 'package:easynode_native/core/ui/app_color_theme.dart';
import 'package:easynode_native/core/security/server_certificate_trust.dart';
import 'package:easynode_native/core/storage/app_storage.dart';
import 'package:easynode_native/core/utils/jwt_expiry.dart';
import 'package:easynode_native/l10n/app_localizations.dart';

class _CertificateLoginController extends LoginController {
  _CertificateLoginController(this.certificate)
    : super(
        apiClientFactory: (_, {String? token}) =>
            throw StateError('API client is not used by this UI test'),
      );

  final PresentedServerCertificate certificate;

  @override
  Future<LoginResult> login({
    required String serverAddress,
    required String username,
    required String password,
    required String mfa2Token,
    required bool httpRiskAccepted,
    required bool savePassword,
    LoginExpiry expiry = LoginExpiry.threeDays,
  }) async => LoginResult(certificate: certificate);
}

PresentedServerCertificate _certificate() => PresentedServerCertificate(
  origin: 'https://100.74.175.1:8092',
  fingerprint: List.filled(32, 'ab').join(),
);

void main() {
  Widget wrap(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColorTheme.defaultLight]),
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  Future<void> pumpLoginPage(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(child));
    await tester.pumpAndSettle();
  }

  Finder byKey(Key key) => find.byKey(key, skipOffstage: false);

  testWidgets('renders all required fields with prefilled values', (
    tester,
  ) async {
    final controller = LoginController.fake();
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: controller,
        initialServerAddress: 'https://example.com',
        initialUsername: 'root',
        initialPassword: 'secret',
        initialSavePassword: true,
        onLoginSuccess: (_) {},
      ),
    );

    expect(byKey(const Key('field-server')), findsOneWidget);
    expect(byKey(const Key('field-username')), findsOneWidget);
    expect(byKey(const Key('field-password')), findsOneWidget);
    expect(byKey(const Key('field-mfa')), findsOneWidget);
    expect(byKey(const Key('switch-save-password')), findsOneWidget);
    expect(byKey(const Key('btn-login')), findsOneWidget);

    expect(find.text('https://example.com'), findsWidgets);
    expect(find.text('root'), findsWidgets);
  });

  testWidgets('shows local validation error for empty username', (
    tester,
  ) async {
    final controller = LoginController.fake();
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: controller,
        initialServerAddress: 'https://example.com',
        initialUsername: '',
        initialSavePassword: false,
        onLoginSuccess: (_) {},
      ),
    );

    await tester.ensureVisible(byKey(const Key('field-password')));
    await tester.enterText(byKey(const Key('field-password')), 'secret');
    await tester.tap(byKey(const Key('btn-login')));
    await tester.pumpAndSettle();

    expect(byKey(const Key('login-error')), findsOneWidget);
  });

  testWidgets('does not invoke onLoginSuccess when login fails', (
    tester,
  ) async {
    final controller = LoginController.fake();
    var called = 0;
    AuthSession? captured;
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: controller,
        initialServerAddress: 'https://example.com',
        initialUsername: 'root',
        initialSavePassword: false,
        onLoginSuccess: (s) {
          called++;
          captured = s;
        },
      ),
    );

    await tester.ensureVisible(byKey(const Key('field-password')));
    await tester.enterText(byKey(const Key('field-password')), '');
    await tester.tap(byKey(const Key('btn-login')));
    await tester.pumpAndSettle();

    expect(called, 0);
    expect(captured, isNull);
    expect(byKey(const Key('login-error')), findsOneWidget);
  });

  testWidgets('exposes loginPageShouldWarnHttp helper', (tester) async {
    expect(loginPageShouldWarnHttp('http://10.0.0.1'), isTrue);
    expect(loginPageShouldWarnHttp('https://10.0.0.1'), isFalse);
  });

  testWidgets('offers cancel and permanent trust for an invalid certificate', (
    tester,
  ) async {
    final certificate = _certificate();
    final controller = _CertificateLoginController(certificate);
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: controller,
        initialServerAddress: certificate.origin,
        initialUsername: 'root',
        initialSavePassword: false,
        onLoginSuccess: (_) {},
      ),
    );

    await tester.ensureVisible(byKey(const Key('field-password')));
    await tester.enterText(byKey(const Key('field-password')), 'secret');
    await tester.tap(byKey(const Key('btn-login')));
    await tester.pumpAndSettle();

    expect(find.text('无法验证服务器证书'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('信任此证书'), findsOneWidget);
    expect(find.text('仅本次继续'), findsNothing);
    expect(find.text(certificate.displayFingerprint), findsOneWidget);
  });

  testWidgets('opens login history from its icon and switches account', (
    tester,
  ) async {
    const account = SavedLoginAccount(
      serverAddress: 'https://saved.example.com',
      username: 'admin',
      savePassword: true,
    );
    const currentAccount = SavedLoginAccount(
      serverAddress: 'https://current.example.com',
      username: 'root',
      savePassword: false,
    );
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: LoginController.fake(),
        initialServerAddress: '',
        initialUsername: '',
        initialSavePassword: false,
        initialAccounts: const [currentAccount, account],
        loadSavedPassword: (_) async => 'saved-secret',
        onLoginSuccess: (_) {},
      ),
    );

    final usernameTopBefore = tester.getTopLeft(
      byKey(const Key('field-username')),
    );
    await tester.tap(byKey(const Key('btn-login-history')));
    await tester.pumpAndSettle();
    expect(byKey(const Key('saved-account-menu')), findsOneWidget);
    expect(
      tester.getTopLeft(byKey(const Key('field-username'))),
      usernameTopBefore,
    );

    await tester.tap(
      byKey(const ValueKey('saved-account-https://saved.example.com-admin')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(byKey(const Key('field-server')))
          .controller!
          .text,
      account.serverAddress,
    );
    expect(
      tester
          .widget<TextField>(byKey(const Key('field-username')))
          .controller!
          .text,
      account.username,
    );
    expect(
      tester
          .widget<TextField>(byKey(const Key('field-password')))
          .controller!
          .text,
      'saved-secret',
    );
    expect(
      tester.widget<Switch>(byKey(const Key('switch-save-password'))).value,
      isTrue,
    );
  });

  testWidgets('asks for confirmation before deleting a saved account', (
    tester,
  ) async {
    const account = SavedLoginAccount(
      serverAddress: 'https://saved.example.com',
      username: 'admin',
      savePassword: false,
    );
    const currentAccount = SavedLoginAccount(
      serverAddress: 'https://current.example.com',
      username: 'root',
      savePassword: false,
    );
    SavedLoginAccount? deleted;
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: LoginController.fake(),
        initialServerAddress: '',
        initialUsername: '',
        initialSavePassword: false,
        initialAccounts: const [currentAccount, account],
        onDeleteAccount: (value) async => deleted = value,
        onLoginSuccess: (_) {},
      ),
    );

    await tester.tap(byKey(const Key('btn-login-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      byKey(
        const ValueKey('delete-saved-account-https://saved.example.com-admin'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('删除记录？'), findsOneWidget);
    expect(byKey(const Key('saved-account-menu')), findsOneWidget);
    expect(deleted, isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(byKey(const Key('saved-account-menu')), findsOneWidget);
    expect(deleted, isNull);

    await tester.tap(
      byKey(
        const ValueKey('delete-saved-account-https://saved.example.com-admin'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(deleted, account);
    expect(byKey(const Key('saved-account-menu')), findsOneWidget);
    expect(
      byKey(
        const ValueKey('delete-saved-account-https://saved.example.com-admin'),
      ),
      findsNothing,
    );
  });

  testWidgets('always shows login history icon', (tester) async {
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: LoginController.fake(),
        initialServerAddress: 'https://only.example.com',
        initialUsername: 'root',
        initialSavePassword: false,
        initialAccounts: const [
          SavedLoginAccount(
            serverAddress: 'https://only.example.com',
            username: 'root',
            savePassword: false,
          ),
        ],
        onLoginSuccess: (_) {},
      ),
    );

    expect(byKey(const Key('btn-login-history')), findsOneWidget);
    await tester.tap(byKey(const Key('btn-login-history')));
    await tester.pumpAndSettle();
    expect(byKey(const Key('saved-account-menu')), findsOneWidget);
    expect(find.text('root'), findsWidgets);
  });

  testWidgets('shows an empty history state and closes on outside tap', (
    tester,
  ) async {
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: LoginController.fake(),
        initialServerAddress: '',
        initialUsername: '',
        initialSavePassword: false,
        onLoginSuccess: (_) {},
      ),
    );

    expect(byKey(const Key('btn-login-history')), findsOneWidget);
    await tester.tap(byKey(const Key('btn-login-history')));
    await tester.pumpAndSettle();
    expect(find.text('暂无历史登录'), findsOneWidget);

    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(byKey(const Key('saved-account-menu')), findsNothing);
  });

  testWidgets('dismisses input focus and opens history from the bottom', (
    tester,
  ) async {
    const accounts = [
      SavedLoginAccount(
        serverAddress: 'https://one.example.com',
        username: 'root',
        savePassword: false,
      ),
      SavedLoginAccount(
        serverAddress: 'https://two.example.com',
        username: 'admin',
        savePassword: false,
      ),
      SavedLoginAccount(
        serverAddress: 'https://three.example.com',
        username: 'ops',
        savePassword: false,
      ),
    ];
    await pumpLoginPage(
      tester,
      LoginPage(
        controller: LoginController.fake(),
        initialServerAddress: '',
        initialUsername: '',
        initialSavePassword: false,
        initialAccounts: accounts,
        onLoginSuccess: (_) {},
      ),
    );

    await tester.tap(byKey(const Key('field-server')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(byKey(const Key('field-server')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.tap(byKey(const Key('btn-login-history')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(byKey(const Key('field-server')))
          .focusNode!
          .hasFocus,
      isFalse,
    );
    final menuBottom = tester
        .getBottomRight(byKey(const Key('saved-account-menu')))
        .dy;
    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(menuBottom, screenBottom);
  });
}
