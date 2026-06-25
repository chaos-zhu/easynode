import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final app = await EasyNodeApp.bootstrap();
    runApp(app);
  } catch (e, s) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText('Bootstrap error:\n$e\n\n$s'),
            ),
          ),
        ),
      ),
    );
  }
}
