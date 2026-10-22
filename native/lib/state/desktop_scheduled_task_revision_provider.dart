import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifies an open desktop list after the global assistant changes tasks.
final desktopScheduledTaskRevisionProvider = StateProvider<int>((ref) => 0);
