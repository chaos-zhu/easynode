import 'package:flutter/material.dart';

void showAgentError(BuildContext context, Object error) {
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|Bad state):\s*'),
    '',
  );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

Future<T?> runAgentAction<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (error) {
    if (context.mounted) showAgentError(context, error);
    return null;
  }
}
