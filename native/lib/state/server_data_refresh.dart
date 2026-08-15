import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credential_list_notifier.dart';
import 'group_list_notifier.dart';
import 'host_list_notifier.dart';
import 'plus_info_notifier.dart';
import 'proxy_list_notifier.dart';

/// Starts the shared reads needed by the server list and server editor.
///
/// Waiting on each provider's first future reuses an in-flight build instead
/// of issuing a second request through `refresh()` during app startup.
final serverSharedDataBootstrapProvider = FutureProvider<void>((ref) async {
  await Future.wait<dynamic>([
    ref.watch(groupListProvider.future),
    ref.watch(hostListProvider.future),
    ref.watch(credentialListProvider.future),
    ref.watch(proxyListProvider.future),
    ref.watch(plusInfoProvider.future),
  ]);
});

Future<void> refreshServerSharedData(WidgetRef ref) async {
  await Future.wait([
    ref.read(groupListProvider.notifier).refresh(throwOnError: true),
    ref.read(hostListProvider.notifier).refresh(throwOnError: true),
    ref.read(credentialListProvider.notifier).refresh(throwOnError: true),
    ref.read(proxyListProvider.notifier).refresh(throwOnError: true),
  ]);
}
