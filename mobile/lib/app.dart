import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/api/cookie_store.dart';
import 'core/storage/app_storage.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/auth_session.dart';
import 'features/auth/login_controller.dart';
import 'features/auth/login_page.dart';
import 'features/servers/server_list_page.dart';
import 'features/servers/server_repository.dart';
import 'features/terminal/terminal_session_manager.dart';

/// Top-level container that swaps between login and server-list screens
/// without a full router. Keeping it small avoids the overhead of go_router
/// or auto_route in the first release.
class EasyNodeApp extends StatefulWidget {
  const EasyNodeApp({
    super.key,
    required this.appStorage,
    required this.secureStorage,
    required this.cookieStore,
    required this.flutterSecureStorage,
    required this.terminalSessionManager,
    this.initialPassword = '',
    this.initialSession,
    this.initialApiClient,
    this.initialPublicKeyPem,
  });

  final AppStorage appStorage;
  final SecureAppStorage secureStorage;
  final SessionCookieStore cookieStore;
  final FlutterSecureStorage flutterSecureStorage;
  final TerminalSessionManager terminalSessionManager;
  final String initialPassword;
  final AuthSession? initialSession;
  final ApiClient? initialApiClient;
  final String? initialPublicKeyPem;

  static Future<EasyNodeApp> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();
    final secureWrapper = SecureAppStorage(secure);
    final appStorage = AppStorage(prefs);
    final cookieStore = SessionCookieStore(secureWrapper);
    final terminalSessionManager = TerminalSessionManager();

    var initialPassword = '';
    if (appStorage.savePassword) {
      initialPassword =
          await secureWrapper.readPassword(
            appStorage.serverAddress,
            appStorage.username,
          ) ??
          '';
    }

    AuthSession? initialSession;
    ApiClient? initialApiClient;
    String? initialPublicKeyPem;
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
        initialPublicKeyPem = await api.getPublicKey();
        initialApiClient = api;
        initialSession = AuthSession(
          serverAddress: appStorage.serverAddress,
          username: appStorage.username,
          token: token,
          deviceId: deviceId,
        );
      } catch (_) {
        await secureWrapper.deleteToken();
        await secureWrapper.deleteSessionCookie();
        await secureWrapper.deleteDeviceId();
      }
    }

    return EasyNodeApp(
      appStorage: appStorage,
      secureStorage: secureWrapper,
      cookieStore: cookieStore,
      flutterSecureStorage: secure,
      terminalSessionManager: terminalSessionManager,
      initialPassword: initialPassword,
      initialSession: initialSession,
      initialApiClient: initialApiClient,
      initialPublicKeyPem: initialPublicKeyPem,
    );
  }

  @override
  State<EasyNodeApp> createState() => _EasyNodeAppState();
}

class _EasyNodeAppState extends State<EasyNodeApp> {
  AuthSession? _session;
  String? _publicKeyPem;
  ApiClient? _apiClient;
  late final LoginController _loginController;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _apiClient = widget.initialApiClient;
    _publicKeyPem = widget.initialPublicKeyPem;
    _loginController = LoginController(apiClientFactory: _buildApiClient)
      ..onLoginSuccess(_onLoginSuccess);
  }

  ApiClient _buildApiClient(String serverAddress, {String? token}) {
    return ApiClient(
      serverAddress: serverAddress,
      cookieStore: widget.cookieStore,
      token: token,
    );
  }

  Future<void> _onLoginSuccess(
    AuthSession session,
    String? passwordToSave,
  ) async {
    await widget.appStorage.setServerAddress(session.serverAddress);
    await widget.appStorage.setUsername(session.username);
    if (passwordToSave != null) {
      await widget.appStorage.setSavePassword(true);
      await widget.secureStorage.writePassword(
        session.serverAddress,
        session.username,
        passwordToSave,
      );
    } else {
      await widget.appStorage.setSavePassword(false);
      await widget.secureStorage.deletePassword(
        session.serverAddress,
        session.username,
      );
    }
    await widget.secureStorage.writeToken(session.token);
    await widget.secureStorage.writeDeviceId(session.deviceId);

    final api = _buildApiClient(session.serverAddress, token: session.token);
    final pubKey = await api.getPublicKey();

    if (!mounted) return;
    setState(() {
      _session = session;
      _apiClient = api;
      _publicKeyPem = pubKey;
    });
  }

  Future<void> _logout() async {
    await widget.terminalSessionManager.closeAll();
    await widget.secureStorage.deleteToken();
    await widget.secureStorage.deleteDeviceId();
    await widget.cookieStore.clear();
    if (!mounted) return;
    setState(() {
      _session = null;
      _apiClient = null;
      _publicKeyPem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (_session != null && _apiClient != null && _publicKeyPem != null) {
      home = ServerListPage(
        repository: ApiServerRepository(
          apiClient: _apiClient!,
          publicKeyPem: _publicKeyPem!,
        ),
        session: _session!,
        terminalSessionManager: widget.terminalSessionManager,
        onLogout: _logout,
      );
    } else {
      home = LoginPage(
        controller: _loginController,
        initialServerAddress: widget.appStorage.serverAddress,
        initialUsername: widget.appStorage.username,
        initialSavePassword: widget.appStorage.savePassword,
        initialPassword: widget.initialPassword,
        onLoginSuccess: (session) {
          // Login result already triggered _onLoginSuccess via the callback
          // bound on the controller; nothing else to do here.
          if (_session == null) {
            setState(() => _session = session);
          }
        },
      );
    }

    return MaterialApp(
      title: 'EasyNode',
      themeMode: ThemeMode.system,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
      ),
      home: home,
    );
  }
}
