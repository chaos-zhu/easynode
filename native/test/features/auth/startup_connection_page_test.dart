import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easynode_native/core/api/api_result.dart';
import 'package:easynode_native/features/auth/startup_connection_page.dart';
import 'package:easynode_native/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Completer<void>> attempts;
  late List<CancelToken> tokens;
  late int connected;
  late int unauthorized;
  late int relogins;

  setUp(() {
    attempts = [];
    tokens = [];
    connected = 0;
    unauthorized = 0;
    relogins = 0;
  });

  Widget app({
    String address = 'http://100.64.0.1:8082',
    Future<void> Function()? relogin,
  }) => MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: StartupConnectionPage(
      serverAddress: address,
      connect: ({required cancelToken}) {
        final attempt = Completer<void>();
        attempts.add(attempt);
        tokens.add(cancelToken);
        return attempt.future;
      },
      onConnected: () => connected++,
      onUnauthorized: (_) async {
        unauthorized++;
      },
      onRelogin:
          relogin ??
          () async {
            relogins++;
          },
    ),
  );

  testWidgets(
    'shows centered connection status and address until five seconds',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('正在连接服务器'), findsOneWidget);
      expect(find.text('http://100.64.0.1:8082'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('正在连接服务器')).textAlign,
        TextAlign.center,
      );
      expect(
        tester.widget<Text>(find.text('http://100.64.0.1:8082')).textAlign,
        TextAlign.center,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4999));
      expect(find.text('重新连接'), findsNothing);
      expect(connected, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('连接超时'), findsOneWidget);
      expect(find.text('重新连接'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tokens.single.isCancelled, isTrue);
      expect(connected, 0);
      expect(unauthorized, 0);
      expect(relogins, 0);
    },
  );

  testWidgets('retry ignores late completion of the timed-out attempt', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('重新连接'));
    await tester.pump();
    expect(attempts, hasLength(2));
    expect(find.text('正在连接服务器'), findsOneWidget);
    attempts.first.complete();
    await tester.pump();
    expect(connected, 0);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(find.text('重新连接'), findsNothing);
    attempts.last.complete();
    await tester.pump();
    expect(connected, 1);
  });

  testWidgets('relogin cancels the old request and never opens the home page', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('重新登录'));
    await tester.pump();
    expect(relogins, 1);
    attempts.single.completeError(
      UnauthorizedFailure('expired', statusCode: 403),
    );
    await tester.pump();
    expect(connected, 0);
    expect(unauthorized, 0);
  });

  testWidgets(
    'invalid session is handed to auth handling instead of opening home',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      attempts.single.completeError(
        UnauthorizedFailure('expired', statusCode: 403),
      );
      await tester.pump();
      expect(unauthorized, 1);
      expect(connected, 0);
    },
  );

  testWidgets('IP denial keeps the retry page and credentials intact', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    attempts.single.completeError(
      IpAccessDeniedFailure('denied', statusCode: 403),
    );
    await tester.pump();
    expect(find.text('重新连接'), findsOneWidget);
    expect(unauthorized, 0);
    expect(relogins, 0);
    expect(connected, 0);
  });

  testWidgets(
    'relogin disables actions while authorization cleanup is pending',
    (tester) async {
      final cleanup = Completer<void>();
      await tester.pumpWidget(app(relogin: () => cleanup.future));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('重新登录'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      cleanup.complete();
      await tester.pump();
    },
  );

  testWidgets('disposed connection page ignores late auth failures', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tokens.single.isCancelled, isTrue);
    attempts.single.completeError(
      UnauthorizedFailure('late failure', statusCode: 403),
    );
    await tester.pump();
    expect(unauthorized, 0);
    expect(connected, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long addresses fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      app(
        address:
            'https://very-long-server-address.tailnet-example.ts.net:18090',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
    expect(find.text('重新登录'), findsOneWidget);
  });
}
