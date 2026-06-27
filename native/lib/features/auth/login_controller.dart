import '../../core/api/api_client.dart';
import '../../core/api/api_result.dart';
import '../../core/crypto/rsa_crypto.dart';
import '../../core/utils/jwt_expiry.dart';
import '../../core/utils/validators.dart';
import 'auth_session.dart';

/// Result of [LoginController.login].
class LoginResult {
  const LoginResult({
    this.success = false,
    this.requiresHttpRiskConfirmation = false,
    this.message = '',
    this.messageKey,
    this.session,
  });

  /// `true` only when login fully succeeded.
  final bool success;

  /// `true` when the user attempted to log in over HTTP without confirming
  /// the risk warning yet. UI should show the warning and re-call login with
  /// `httpRiskAccepted: true` once the user confirms.
  final bool requiresHttpRiskConfirmation;

  /// Fallback / backend-provided message. UI should prefer localizing
  /// [messageKey] when it is set; otherwise display this verbatim.
  final String message;

  /// i18n key for static, controller-side errors (empty fields, invalid
  /// server address, etc.). `null` for backend-returned strings.
  final String? messageKey;

  final AuthSession? session;
}

/// Builds an [ApiClient] for a given server address. Allows tests to inject
/// a stub client so the controller can be exercised without real network.
typedef ApiClientFactory = ApiClient Function(String serverAddress, {String? token});

/// Orchestrates the native client login flow.
class LoginController {
  LoginController({
    required ApiClientFactory apiClientFactory,
    RsaCrypto? rsa,
  })  : _apiClientFactory = apiClientFactory,
        _rsa = rsa ?? RsaCrypto();

  /// Test factory that returns a controller without a real HTTP client. Real
  /// network calls will fail because the factory throws when invoked.
  factory LoginController.fake() => LoginController(
        apiClientFactory: (_, {String? token}) =>
            throw StateError('apiClientFactory not configured for tests'),
      );

  final ApiClientFactory _apiClientFactory;
  final RsaCrypto _rsa;

  Future<LoginResult> login({
    required String serverAddress,
    required String username,
    required String password,
    required String mfa2Token,
    required bool httpRiskAccepted,
    required bool savePassword,
    LoginExpiry expiry = LoginExpiry.threeDays,
  }) async {
    final String normalized;
    try {
      normalized = normalizeServerAddress(serverAddress);
    } on ServerAddressException catch (error) {
      return LoginResult(message: error.message, messageKey: error.code);
    } on FormatException catch (error) {
      return LoginResult(message: error.message);
    }

    if (isHttpAddress(normalized) && !httpRiskAccepted) {
      return const LoginResult(requiresHttpRiskConfirmation: true);
    }

    if (username.trim().isEmpty) {
      return const LoginResult(
        message: '请输入用户名',
        messageKey: 'login.errEmptyUsername',
      );
    }
    if (password.isEmpty) {
      return const LoginResult(
        message: '请输入密码',
        messageKey: 'login.errEmptyPassword',
      );
    }

    final api = _apiClientFactory(normalized);
    try {
      final publicKey = await api.getPublicKey();
      final ciphertext = _rsa.encryptPassword(publicKey, password);
      final response = await api.postJson('/login', {
        'loginName': username,
        'ciphertext': ciphertext,
        'jwtExpires': jwtExpiresFor(expiry),
        if (mfa2Token.isNotEmpty) 'mfa2Token': mfa2Token,
      });

      if (response['status'] != 200) {
        return LoginResult(
          message: response['msg']?.toString() ?? '登录失败',
          messageKey: response['msg'] == null ? 'login.errLoginGeneric' : null,
        );
      }
      final data = response['data'];
      if (data is! Map || data['token'] is! String || data['deviceId'] is! String) {
        return const LoginResult(
          message: '服务端登录响应缺少必要字段',
          messageKey: 'login.errMissingFields',
        );
      }
      final session = AuthSession(
        serverAddress: normalized,
        username: username,
        token: data['token'] as String,
        deviceId: data['deviceId'] as String,
      );
      // ignore: parameter_assignments
      _onLoginSuccess?.call(session, savePassword ? password : null);
      return LoginResult(success: true, session: session);
    } on ApiFailure catch (error) {
      return LoginResult(message: error.message);
    }
  }

  /// Optional callback invoked on successful login. The end-to-end wiring
  /// step (Task 13) supplies this so the controller stays decoupled from
  /// concrete storage in tests.
  void Function(AuthSession session, String? passwordToSave)? _onLoginSuccess;
  // ignore: use_setters_to_change_properties
  void onLoginSuccess(void Function(AuthSession session, String? passwordToSave) cb) {
    _onLoginSuccess = cb;
  }
}
