import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../state/api_providers.dart';
import '../ai_agent/agent_models.dart';

final desktopSettingsRepositoryProvider = Provider<DesktopSettingsRepository>(
  (ref) => DesktopSettingsRepository(ref.watch(apiClientProvider)),
);

/// Settings not previously exposed by the mobile UI. Secrets stay on the
/// server and in transient form state; none are copied to local preferences.
class DesktopSettingsRepository {
  const DesktopSettingsRepository(this.api);
  final ApiClient api;
  Future<Map<String, dynamic>> notificationConfig() async =>
      stringMap((await api.getJson('/notify-config'))['data']);
  Future<List<Map<String, dynamic>>> notificationEvents() async =>
      mapList((await api.getJson('/notify'))['data']);
  Future<void> saveNotifications(Map<String, dynamic> config) async {
    await api.putJson('/notify-config', {'noticeConfig': config});
  }

  Future<void> toggleNotification(String type, bool enabled) async {
    await api.putJson('/notify', {'type': type, 'sw': enabled});
  }

  Future<void> activatePlus(String key) async {
    await api.postJson('/plus-conf', {'key': key});
  }

  Future<Map<String, dynamic>> plusDevices() async =>
      stringMap((await api.getJson('/plus-devices'))['data']);
  Future<void> releasePlusDevice(String instanceId) async {
    await api.postJson('/plus-release', {'targetInstanceId': instanceId});
  }
}
