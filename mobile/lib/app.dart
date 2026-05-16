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
  });

  final AppStorage appStorage;
  final SecureAppStorage secureStorage;
  final SessionCookieStore cookieStore;
  final FlutterSecureStorage flutterSecureStorage;

  static Future<EasyNodeApp> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();
    final secureWrapper = SecureAppStorage(secure);
    return EasyNodeApp(
      appStorage: AppStorage(prefs),
      secureStorage: secureWrapper,
      cookieStore: SessionCookieStore(secureWrapper),
      flutterSecureStorage: secure,
    );
  }

  @override
  State<EasyNodeApp> createState() => _EasyNodeAppState();
}

class _EasyNodeAppState extends State<EasyNodeApp> {
  AuthSession? _session;
  String? _publicKeyPem;
  ApiClient? _apiClient;
  String? _initialPassword;

  @override
  void initState() {
    super.initState();
    _hydrateInitialPassword();
  }

  Future<void> _hydrateInitialPassword() async {
    if (!widget.appStorage.savePassword) return;
    final pwd = await widget.secureStorage.readPassword(
      widget.appStorage.serverAddress,
      widget.appStorage.username,
    );
    if (!mounted) return;
    setState(() => _initialPassword = pwd);
  }

  ApiClient _buildApiClient(String serverAddress, {String? token}) {
    return ApiClient(
      serverAddress: serverAddress,
      cookieStore: widget.cookieStore,
      token: token,
    );
  }

  Future<void> _onLoginSuccess(AuthSession session, String? passwordToSave) async {
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
    await widget.secureStorage.deleteToken();
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
    final controller = LoginController(apiClientFactory: _buildApiClient)
      ..onLoginSuccess(_onLoginSuccess);

    Widget home;
    if (_session != null && _apiClient != null && _publicKeyPem != null) {
      home = ServerListPage(
        repository: ServerRepository(
          apiClient: _apiClient!,
          publicKeyPem: _publicKeyPem!,
        ),
        session: _session!,
        onLogout: _logout,
      );
    } else {
      home = LoginPage(
        controller: controller,
        initialServerAddress: widget.appStorage.serverAddress,
        initialUsername: widget.appStorage.username,
        initialSavePassword: widget.appStorage.savePassword,
        initialPassword: _initialPassword ?? '',
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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: home,
    );
  }
}
