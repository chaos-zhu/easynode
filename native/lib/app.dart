import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/api/cookie_store.dart';
import 'core/api/api_result.dart';
import 'core/storage/app_storage.dart';
import 'core/storage/secure_storage.dart';
import 'core/security/server_certificate_trust.dart';
import 'features/auth/auth_session.dart';
import 'features/auth/login_controller.dart';
import 'features/auth/login_page.dart';
import 'features/auth/startup_connection_page.dart';
import 'features/ai_agent/agent_overlay.dart';
import 'features/shell/main_shell_page.dart';
import 'l10n/app_localizations.dart';
import 'state/api_access_notifier.dart';
import 'state/auth_notifier.dart';
import 'state/auth_state.dart';
import 'state/color_theme_notifier.dart';
import 'state/locale_notifier.dart';
import 'state/storage_providers.dart';
import 'state/theme_mode_notifier.dart';

/// Bootstrap result. Wraps the values [EasyNodeApp] needs to install on the
/// root [ProviderScope]. Building these synchronously up front keeps the
/// providers free of async initialization and lets storage be read in
/// `build` without futures.
class _Bootstrap {
  _Bootstrap({
    required this.appStorage,
    required this.secureStorage,
    required this.cookieStore,
    required this.flutterSecureStorage,
    required this.appVersion,
    required this.initialPassword,
    required this.initialAuthState,
    required this.certificateTrust,
  });

  final AppStorage appStorage;
  final SecureAppStorage secureStorage;
  final SessionCookieStore cookieStore;
  final FlutterSecureStorage flutterSecureStorage;
  final String appVersion;
  final String initialPassword;
  final AuthState initialAuthState;
  final ServerCertificateTrustStore certificateTrust;
}

class EasyNodeApp extends StatelessWidget {
  const EasyNodeApp._({required _Bootstrap bootstrap}) : _b = bootstrap;

  final _Bootstrap _b;

  static Future<Widget> bootstrap({ApiClientFactory? apiClientFactory}) async {
    final prefs = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();
    final secureWrapper = SecureAppStorage(secure);
    final appStorage = AppStorage(prefs);
    final cookieStore = SessionCookieStore(secureWrapper);
    final certificateTrust = ServerCertificateTrustStore(secureWrapper);
    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = packageInfo.buildNumber.isEmpty
        ? packageInfo.version
        : '${packageInfo.version}+${packageInfo.buildNumber}';

    var initialPassword = '';
    if (appStorage.savePassword) {
      initialPassword =
          await secureWrapper.readPassword(
            appStorage.serverAddress,
            appStorage.username,
          ) ??
          '';
    }

    AuthState initialAuthState = AuthState.empty;
    final token = await secureWrapper.readToken();
    final cookie = await secureWrapper.readSessionCookie();
    final deviceId = await secureWrapper.readDeviceId();
    final hasStoredLogin =
        appStorage.serverAddress.isNotEmpty &&
        appStorage.username.isNotEmpty &&
        token != null &&
        token.isNotEmpty &&
        cookie != null &&
        cookie.isNotEmpty &&
        deviceId != null &&
        deviceId.isNotEmpty;

    if (hasStoredLogin) {
      await certificateTrust.prepare(appStorage.serverAddress);
      final api =
          apiClientFactory?.call(appStorage.serverAddress, token: token) ??
          ApiClient(
            serverAddress: appStorage.serverAddress,
            cookieStore: cookieStore,
            token: token,
            appVersion: appVersion,
            certificateTrust: certificateTrust,
          );
      // Restore locally so the connection check can run on the visible logo
      // page. Encryption operations fetch the public key lazily.
      initialAuthState = AuthState(
        session: AuthSession(
          serverAddress: appStorage.serverAddress,
          username: appStorage.username,
          token: token,
          deviceId: deviceId,
        ),
        apiClient: api,
      );
    }

    return EasyNodeApp._(
      bootstrap: _Bootstrap(
        appStorage: appStorage,
        secureStorage: secureWrapper,
        cookieStore: cookieStore,
        flutterSecureStorage: secure,
        appVersion: appVersion,
        initialPassword: initialPassword,
        initialAuthState: initialAuthState,
        certificateTrust: certificateTrust,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(_b.appStorage),
        secureStorageProvider.overrideWithValue(_b.secureStorage),
        cookieStoreProvider.overrideWithValue(_b.cookieStore),
        certificateTrustProvider.overrideWithValue(_b.certificateTrust),
        authProvider.overrideWith(
          (ref) => AuthNotifier(ref, _b.initialAuthState),
        ),
      ],
      child: _AppRoot(
        initialPassword: _b.initialPassword,
        appVersion: _b.appVersion,
      ),
    );
  }
}

class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot({required this.initialPassword, required this.appVersion});

  final String initialPassword;
  final String appVersion;

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  late final LoginController _loginController;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  var _ipAccessDeniedDialogShowing = false;
  var _splashFinished = false;
  final AgentNavigationObserver _agentNavigationObserver =
      AgentNavigationObserver();

  @override
  void dispose() {
    _agentNavigationObserver.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loginController = LoginController(
      apiClientFactory: _buildAnonymousApiClient,
      certificateTrust: ref.read(certificateTrustProvider),
    )..onLoginSuccess(_onLoginSuccess);
    // The restored client is constructed before ProviderScope exists. Bind
    // its session-failure handler once the global coordinator is available.
    ref
        .read(authProvider)
        .apiClient
        ?.setOnSessionFailure(_handleSessionFailure);
  }

  Future<void> _handleSessionFailure(ApiSessionFailure failure) {
    return ref.read(apiAccessProvider.notifier).handleSessionFailure(failure);
  }

  ApiClient _buildAnonymousApiClient(String serverAddress, {String? token}) {
    return ApiClient(
      serverAddress: serverAddress,
      cookieStore: ref.read(cookieStoreProvider),
      token: token,
      appVersion: widget.appVersion,
      certificateTrust: ref.read(certificateTrustProvider),
    );
  }

  Future<void> _onLoginSuccess(
    AuthSession session,
    String? passwordToSave,
  ) async {
    // Public-key validation is part of the login flow, so errors still belong
    // to LoginPage. Bind global session handling only after it succeeds.
    final api = _buildAnonymousApiClient(
      session.serverAddress,
      token: session.token,
    );
    final pubKey = await api.getPublicKey();
    api.setOnSessionFailure(_handleSessionFailure);
    await ref
        .read(authProvider.notifier)
        .signIn(
          session: session,
          apiClient: api,
          publicKeyPem: pubKey,
          passwordToSave: passwordToSave,
        );
    ref.read(apiAccessProvider.notifier).reset();
    if (mounted) setState(() => _splashFinished = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final appStorage = ref.watch(appStorageProvider);

    ref.listen<bool>(authProvider.select((state) => state.signedIn), (
      previous,
      next,
    ) {
      if (previous == true && !next) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });

    // Show the server-provided reason after the REST coordinator signs out,
    // then clear it so the same message isn't shown twice on rebuilds.
    ref.listen<String?>(
      apiAccessProvider.select((state) => state.signOutReason),
      (_, next) {
        if (next == null || next.isEmpty) return;
        final messenger = _messengerKey.currentState;
        if (messenger == null) return;
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(next),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        // Reset on the next frame so we don't trigger another listener pass
        // while the current one is still running.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(apiAccessProvider.notifier).consumeSignOutReason();
        });
      },
    );

    ref.listen<bool>(
      apiAccessProvider.select((state) => state.ipAccessDenied),
      (previous, next) {
        if (next && previous != true && ref.read(authProvider).signedIn) {
          _showIpAccessDeniedDialog();
        }
      },
    );

    final Widget home;
    if (auth.signedIn) {
      home = const MainShellPage();
    } else {
      home = LoginPage(
        controller: _loginController,
        initialServerAddress: appStorage.serverAddress,
        initialUsername: appStorage.username,
        initialSavePassword: appStorage.savePassword,
        initialPassword: widget.initialPassword,
        initialAccounts: appStorage.savedLoginAccounts,
        loadSavedPassword: (account) => ref
            .read(secureStorageProvider)
            .readPassword(account.serverAddress, account.username),
        onDeleteAccount: (account) async {
          await ref
              .read(secureStorageProvider)
              .deletePassword(account.serverAddress, account.username);
          await appStorage.removeSavedLoginAccount(account);
        },
        onLoginSuccess: (_) {},
      );
    }

    final palette = ref.watch(colorThemeProvider);
    final lightColors = palette.colorsFor(Brightness.light);
    final darkColors = palette.colorsFor(Brightness.dark);

    return MaterialApp(
      title: 'EasyNode',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      navigatorObservers: [_agentNavigationObserver],
      scaffoldMessengerKey: _messengerKey,
      themeMode: ref.watch(themeModeProvider),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: palette.seed),
        extensions: [lightColors],
        appBarTheme: AppBarTheme(
          centerTitle: false,
          titleSpacing: 4,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: lightColors.text,
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.seed,
          brightness: Brightness.dark,
        ),
        extensions: [darkColors],
        appBarTheme: AppBarTheme(
          centerTitle: false,
          titleSpacing: 4,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: darkColors.text,
          ),
        ),
      ),
      locale: ref.watch(localeProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (deviceLocale, supported) {
        return AppLocalizations.resolve(deviceLocale, supported);
      },
      builder: (context, child) => Stack(
        children: [
          ?child,
          if (auth.signedIn && _splashFinished)
            AgentGlobalOverlay(
              navigationObserver: _agentNavigationObserver,
              navigatorKey: _navigatorKey,
            ),
        ],
      ),
      home: auth.signedIn && !_splashFinished
          ? StartupConnectionPage(
              serverAddress: auth.session!.serverAddress,
              connect: auth.apiClient!.checkSession,
              onConnected: () => setState(() => _splashFinished = true),
              onUnauthorized: (failure) => ref
                  .read(apiAccessProvider.notifier)
                  .handleSessionFailure(failure, waitForCleanup: true),
              onRelogin: () async {
                await ref.read(authProvider.notifier).signOutAfterCleanup();
                if (!mounted) return;
                ref.read(apiAccessProvider.notifier).reset();
              },
            )
          : home,
    );
  }

  Future<void> _showIpAccessDeniedDialog() async {
    if (_ipAccessDeniedDialogShowing || !mounted) return;
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showIpAccessDeniedDialog();
      });
      return;
    }
    _ipAccessDeniedDialogShowing = true;
    final l = AppLocalizations.of(dialogContext);
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l.tr('access.ipDeniedTitle')),
          content: Text(l.tr('access.ipDeniedBody')),
          actions: [
            if (!Platform.isIOS)
              TextButton(
                onPressed: _exitApp,
                child: Text(l.tr('common.exitApp')),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await ref
                    .read(apiAccessProvider.notifier)
                    .signOutFromIpAccessDenied();
              },
              child: Text(l.tr('settings.logout')),
            ),
          ],
        ),
      ),
    );
    _ipAccessDeniedDialogShowing = false;
  }

  Future<void> _exitApp() async {
    await SystemNavigator.pop();
  }
}
