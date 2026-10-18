import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_result.dart';
import '../../l10n/app_localizations.dart';

/// Keeps restored credentials behind a connection check until the server is
/// reachable. Network failures never discard the saved session.
class StartupConnectionPage extends StatefulWidget {
  const StartupConnectionPage({
    super.key,
    required this.serverAddress,
    required this.connect,
    required this.onConnected,
    required this.onUnauthorized,
    required this.onRelogin,
  });

  final String serverAddress;
  final Future<void> Function({required CancelToken cancelToken}) connect;
  final VoidCallback onConnected;
  final Future<void> Function(UnauthorizedFailure failure) onUnauthorized;
  final Future<void> Function() onRelogin;

  @override
  State<StartupConnectionPage> createState() => _StartupConnectionPageState();
}

class _StartupConnectionPageState extends State<StartupConnectionPage>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _loadingController;
  CancelToken? _cancelToken;
  int _attempt = 0;
  String? _failureKey;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_signingOut) return;
    final attempt = ++_attempt;
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;
    setState(() => _failureKey = null);
    unawaited(_loadingController.repeat());
    try {
      await widget
          .connect(cancelToken: token)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              token.cancel('Startup connection timed out');
              throw TimeoutException('Startup connection timed out');
            },
          );
    } catch (error) {
      if (!mounted || attempt != _attempt) return;
      token.cancel();
      _loadingController.stop();
      if (error is UnauthorizedFailure) {
        await widget.onUnauthorized(error);
        return;
      }
      setState(() {
        _failureKey = switch (error) {
          TimeoutException() => 'startup.timeout',
          IpAccessDeniedFailure() => 'startup.ipDenied',
          _ => 'startup.failed',
        };
      });
      return;
    }
    if (!mounted || attempt != _attempt) return;
    _loadingController.stop();
    widget.onConnected();
  }

  Future<void> _relogin() async {
    if (_signingOut) return;
    ++_attempt;
    _cancelToken?.cancel();
    setState(() => _signingOut = true);
    await widget.onRelogin();
  }

  @override
  void dispose() {
    ++_attempt;
    _cancelToken?.cancel();
    _logoController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final failed = _failureKey != null;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoController,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.88, end: 1).animate(
                      CurvedAnimation(
                        parent: _logoController,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
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
                Text(
                  'EasyNode',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 22,
                  width: 22,
                  child: failed
                      ? Icon(
                          Icons.cloud_off_rounded,
                          size: 22,
                          color: colors.onSurfaceVariant,
                        )
                      : RotationTransition(
                          turns: _loadingController,
                          child: const CircularProgressIndicator(
                            value: 0.72,
                            strokeWidth: 2.4,
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  l.tr(_failureKey ?? 'startup.connecting'),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.serverAddress,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: _signingOut ? null : _connect,
                        child: Text(l.tr('startup.reconnect')),
                      ),
                      OutlinedButton(
                        onPressed: _signingOut ? null : _relogin,
                        child: Text(l.tr('startup.relogin')),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
