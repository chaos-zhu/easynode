import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/auth_session.dart';
import 'package:mobile/features/auth/login_controller.dart';
import 'package:mobile/features/auth/login_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  testWidgets('renders all required fields with prefilled values', (tester) async {
    final controller = LoginController.fake();
    await tester.pumpWidget(
      wrap(
        LoginPage(
          controller: controller,
          initialServerAddress: 'https://example.com',
          initialUsername: 'root',
          initialPassword: 'secret',
          initialSavePassword: true,
          onLoginSuccess: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('field-server')), findsOneWidget);
    expect(find.byKey(const Key('field-username')), findsOneWidget);
    expect(find.byKey(const Key('field-password')), findsOneWidget);
    expect(find.byKey(const Key('field-mfa')), findsOneWidget);
    expect(find.byKey(const Key('switch-save-password')), findsOneWidget);
    expect(find.byKey(const Key('btn-login')), findsOneWidget);

    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('shows local validation error for empty username', (tester) async {
    final controller = LoginController.fake();
    await tester.pumpWidget(
      wrap(
        LoginPage(
          controller: controller,
          initialServerAddress: 'https://example.com',
          initialUsername: '',
          initialSavePassword: false,
          onLoginSuccess: (_) {},
        ),
      ),
    );

    // Provide a password so we trip the username check.
    await tester.enterText(find.byKey(const Key('field-password')), 'secret');
    await tester.tap(find.byKey(const Key('btn-login')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('请输入用户名'), findsOneWidget);
  });

  testWidgets('does not invoke onLoginSuccess when login fails', (tester) async {
    final controller = LoginController.fake();
    var called = 0;
    AuthSession? captured;
    await tester.pumpWidget(
      wrap(
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
      ),
    );

    await tester.enterText(find.byKey(const Key('field-password')), '');
    await tester.tap(find.byKey(const Key('btn-login')));
    await tester.pumpAndSettle();

    expect(called, 0);
    expect(captured, isNull);
    expect(find.text('请输入密码'), findsOneWidget);
  });

  testWidgets('exposes loginPageShouldWarnHttp helper', (tester) async {
    expect(loginPageShouldWarnHttp('http://10.0.0.1'), isTrue);
    expect(loginPageShouldWarnHttp('https://10.0.0.1'), isFalse);
  });
}
