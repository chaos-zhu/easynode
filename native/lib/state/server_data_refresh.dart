import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credential_list_notifier.dart';
import 'group_list_notifier.dart';
import 'host_list_notifier.dart';
import 'proxy_list_notifier.dart';

Future<void> refreshServerSharedData(WidgetRef ref) async {
  await Future.wait([
    ref.read(groupListProvider.notifier).refresh(throwOnError: true),
    ref.read(hostListProvider.notifier).refresh(throwOnError: true),
    ref.read(credentialListProvider.notifier).refresh(throwOnError: true),
    ref.read(proxyListProvider.notifier).refresh(throwOnError: true),
  ]);
}
