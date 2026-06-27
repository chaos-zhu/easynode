import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/docker/docker_session_manager.dart';

final dockerSessionManagerProvider = Provider<DockerSessionManager>((ref) {
  final manager = DockerSessionManager();
  ref.onDispose(manager.dispose);
  return manager;
});
