import 'dart:async';
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
import 'features/auth/auth_session.dart';
import 'features/auth/login_controller.dart';
import 'features/auth/login_page.dart';
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
    required this.initialIpAccessDenied,
  });

  final AppStorage appStorage;
  final SecureAppStorage secureStorage;
  final SessionCookieStore cookieStore;
  final FlutterSecureStorage flutterSecureStorage;
  final String appVersion;
  final String initialPassword;
  final AuthState initialAuthState;
  final bool initialIpAccessDenied;
}

class EasyNodeApp extends StatelessWidget {
  const EasyNodeApp._({required _Bootstrap bootstrap}) : _b = bootstrap;

  final _Bootstrap _b;

  static Future<Widget> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();
    final secureWrapper = SecureAppStorage(secure);
    final appStorage = AppStorage(prefs);
    final cookieStore = SessionCookieStore(secureWrapper);
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
    var initialIpAccessDenied = false;
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
      final api = ApiClient(
        serverAddress: appStorage.serverAddress,
        cookieStore: cookieStore,
        token: token,
        appVersion: appVersion,
      );
      try {
        final pubKey = await api.getPublicKey();
        initialAuthState = AuthState(
          session: AuthSession(
            serverAddress: appStorage.serverAddress,
            username: appStorage.username,
            token: token,
            deviceId: deviceId,
          ),
          apiClient: api,
          publicKeyPem: pubKey,
        );
      } on IpAccessDeniedFailure {
        // The saved session can still be used from an allowed network. Keep
        // the main shell behind the blocking prompt; its data requests cannot
        // proceed while the IP policy is active, but showing LoginPage here
        // incorrectly implies that the credentials were invalidated.
        initialAuthState = AuthState(
          session: AuthSession(
            serverAddress: appStorage.serverAddress,
            username: appStorage.username,
            token: token,
            deviceId: deviceId,
          ),
          apiClient: api,
          // Repositories are not used while the access-denied prompt blocks
          // the UI. A non-null placeholder preserves the restored shell until
          // the user exits or explicitly signs out.
          publicKeyPem: '',
        );
        initialIpAccessDenied = true;
      } catch (_) {
        await secureWrapper.deleteToken();
        await secureWrapper.deleteSessionCookie();
        await secureWrapper.deleteDeviceId();
      }
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
        initialIpAccessDenied: initialIpAccessDenied,
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
        authProvider.overrideWith(
          (ref) => AuthNotifier(ref, _b.initialAuthState),
        ),
      ],
      child: _AppRoot(
        initialPassword: _b.initialPassword,
        appVersion: _b.appVersion,
        initialIpAccessDenied: _b.initialIpAccessDenied,
      ),
    );
  }
}

class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot({
    required this.initialPassword,
    required this.appVersion,
    required this.initialIpAccessDenied,
  });

  final String initialPassword;
  final String appVersion;
  final bool initialIpAccessDenied;

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
    )..onLoginSuccess(_onLoginSuccess);
    // The restored client is constructed before ProviderScope exists. Bind
    // its session-failure handler once the global coordinator is available.
    ref
        .read(authProvider)
        .apiClient
        ?.setOnSessionFailure(_handleSessionFailure);
    if (widget.initialIpAccessDenied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(apiAccessProvider.notifier)
            .handleSessionFailure(
              IpAccessDeniedFailure('IP access denied', statusCode: 403),
            );
      });
    }
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
      home: _BrandedSplashGate(
        onFinished: () {
          if (mounted && !_splashFinished) {
            setState(() => _splashFinished = true);
          }
        },
        child: home,
      ),
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

class _BrandedSplashGate extends StatefulWidget {
  const _BrandedSplashGate({required this.child, required this.onFinished});

  final Widget child;
  final VoidCallback onFinished;

  @override
  State<_BrandedSplashGate> createState() => _BrandedSplashGateState();
}

class _BrandedSplashGateState extends State<_BrandedSplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _textOffset;
  bool _showSplash = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _logoScale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
    );
    _textOffset = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.18, 0.7, curve: Curves.easeOutBack),
          ),
        );
    unawaited(_controller.forward());
    _timer = Timer(const Duration(milliseconds: 1250), () {
      if (mounted) {
        setState(() => _showSplash = false);
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: _showSplash
          ? _BrandedSplash(
              key: const ValueKey('splash'),
              controller: _controller,
              logoScale: _logoScale,
              logoFade: _logoFade,
              textOffset: _textOffset,
            )
          : KeyedSubtree(key: const ValueKey('home'), child: widget.child),
    );
  }
}

class _BrandedSplash extends StatelessWidget {
  const _BrandedSplash({
    super.key,
    required this.controller,
    required this.logoScale,
    required this.logoFade,
    required this.textOffset,
  });

  final AnimationController controller;
  final Animation<double> logoScale;
  final Animation<double> logoFade;
  final Animation<Offset> textOffset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: Center(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: logoFade,
                  child: ScaleTransition(
                    scale: logoScale,
                    child: Container(
                      width: 104,
                      height: 104,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/logo_v2_01.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SlideTransition(
                  position: textOffset,
                  child: FadeTransition(
                    opacity: logoFade,
                    child: Text(
                      'EasyNode',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
