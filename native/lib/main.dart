import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await EasyNodeApp.bootstrap();
  runApp(app);
}
