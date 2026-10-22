/// A terminal-scoped assistant executes tools in one existing local PTY.
/// The shared chat UI and reducer do not depend on desktop workspace classes.
class TerminalAgentBinding {
  const TerminalAgentBinding({
    required this.hostId,
    required this.hostName,
    required this.isConnected,
    required this.execute,
    required this.cancel,
  });
  final String hostId;
  final String hostName;
  final bool Function() isConnected;
  final Future<Map<String, dynamic>> Function(
    String command,
    String requestId,
    void Function(Map<String, dynamic>) onProgress,
  )
  execute;
  final Future<Map<String, dynamic>> Function(String requestId) cancel;
}
