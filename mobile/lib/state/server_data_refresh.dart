import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credential_list_notifier.dart';
import 'group_list_notifier.dart';
import 'host_list_notifier.dart';
import 'proxy_list_notifier.dart';

Future<void> refreshServerSharedData(WidgetRef ref) async {
  await Future.wait([
    ref.read(groupListProvider.notifier).refresh(),
    ref.read(hostListProvider.notifier).refresh(),
    ref.read(credentialListProvider.notifier).refresh(),
    ref.read(proxyListProvider.notifier).refresh(),
  ]);
}
