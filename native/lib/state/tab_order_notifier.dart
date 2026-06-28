import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_storage.dart';
import 'storage_providers.dart';

class TabOrderNotifier extends StateNotifier<List<String>> {
  TabOrderNotifier(this._storage) : super(_storage.tabOrder);

  final AppStorage _storage;

  Future<void> setOrder(List<String> order) async {
    await _storage.setTabOrder(order);
    state = order;
  }

  Future<void> resetToDefault() async {
    await _storage.setTabOrder(AppStorage.defaultTabOrder);
    state = AppStorage.defaultTabOrder;
  }
}

final tabOrderProvider =
    StateNotifierProvider<TabOrderNotifier, List<String>>((ref) {
  return TabOrderNotifier(ref.watch(appStorageProvider));
});

class HomeTabNotifier extends StateNotifier<String> {
  HomeTabNotifier(this._storage) : super(_storage.homeTab);

  final AppStorage _storage;

  Future<void> setHomeTab(String tab) async {
    await _storage.setHomeTab(tab);
    state = tab;
  }

  Future<void> resetToDefault() async {
    await _storage.setHomeTab(AppStorage.defaultTab);
    state = AppStorage.defaultTab;
  }
}

final homeTabProvider =
    StateNotifierProvider<HomeTabNotifier, String>((ref) {
  return HomeTabNotifier(ref.watch(appStorageProvider));
});
