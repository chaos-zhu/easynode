import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/api/cookie_store.dart';
import 'core/storage/app_storage.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/auth_session.dart';
import 'features/auth/login_controller.dart';
import 'features/auth/login_page.dart';
import 'features/shell/main_shell_page.dart';
import 'l10n/app_localizations.dart';
import 'state/auth_notifier.dart';
import 'state/auth_state.dart';
import 'state/locale_notifier.dart';
import 'state/storage_providers.dart';

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
    required this.initialPassword,
    required this.initialAuthState,
  });

  final AppStorage appStorage;
  final SecureAppStorage secureStorage;
  final SessionCookieStore cookieStore;
  final FlutterSecureStorage flutterSecureStorage;
  final String initialPassword;
  final AuthState initialAuthState;
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
      final api = ApiClient(
        serverAddress: appStorage.serverAddress,
        cookieStore: cookieStore,
        token: token,
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
        initialPassword: initialPassword,
        initialAuthState: initialAuthState,
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
      child: _AppRoot(initialPassword: _b.initialPassword),
    );
  }
}

class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot({required this.initialPassword});

  final String initialPassword;

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  late final LoginController _loginController;

  @override
  void initState() {
    super.initState();
    _loginController = LoginController(apiClientFactory: _buildApiClient)
      ..onLoginSuccess(_onLoginSuccess);
  }

  ApiClient _buildApiClient(String serverAddress, {String? token}) {
    return ApiClient(
      serverAddress: serverAddress,
      cookieStore: ref.read(cookieStoreProvider),
      token: token,
    );
  }

  Future<void> _onLoginSuccess(
    AuthSession session,
    String? passwordToSave,
  ) async {
    final api = _buildApiClient(session.serverAddress, token: session.token);
    final pubKey = await api.getPublicKey();
    await ref
        .read(authProvider.notifier)
        .signIn(
          session: session,
          apiClient: api,
          publicKeyPem: pubKey,
          passwordToSave: passwordToSave,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final appStorage = ref.watch(appStorageProvider);

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

    return MaterialApp(
      title: 'EasyNode',
      themeMode: ThemeMode.system,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.amber),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.amber,
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
      home: _BrandedSplashGate(child: home),
    );
  }
}

class _BrandedSplashGate extends StatefulWidget {
  const _BrandedSplashGate({required this.child});

  final Widget child;

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
    _logoScale = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
    );
    _textOffset = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.18, 0.7, curve: Curves.easeOutBack),
      ),
    );
    unawaited(_controller.forward());
    _timer = Timer(const Duration(milliseconds: 1250), () {
      if (mounted) setState(() => _showSplash = false);
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
