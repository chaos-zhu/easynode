import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final app = await EasyNodeApp.bootstrap();
    runApp(app);
  } catch (_) {
    runApp(const _BootstrapRecoveryApp());
  }
}

/// Storage can be temporarily locked or unavailable. Keep a retry path on
/// screen without exposing stack traces or falling back to plaintext files.
class _BootstrapRecoveryApp extends StatefulWidget {
  const _BootstrapRecoveryApp();

  @override
  State<_BootstrapRecoveryApp> createState() => _BootstrapRecoveryAppState();
}

class _BootstrapRecoveryAppState extends State<_BootstrapRecoveryApp> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      final app = await EasyNodeApp.bootstrap();
      if (mounted) runApp(app);
    } catch (_) {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EasyNode',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final l = AppLocalizations.of(context);
        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      l.tr('startup.storageFailedTitle'),
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.tr('startup.storageFailedBody'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _retrying ? null : _retry,
                      child: Text(l.tr('common.retry')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
