import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_controller.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  bool failWrite = false;

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  void writeInMemory(String key, dynamic value) { values[key] = value; }

  @override
  Future<void> write(String key, dynamic value) async {
    writeInMemory(key, value);
    if (failWrite) throw StateError('Storage unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedExploreController extends PageExploreTab {
  _DelayedExploreController() : super(0);
  final first = Completer<List<LeftListModel>>();
  final second = Completer<List<LeftListModel>>();
  int calls = 0;

  @override
  Future<List<LeftListModel>> getActressList() => calls++ == 0 ? first.future : second.future;
}

void main() {
  final preferences = _Preferences();
  setUpAll(() => Get.put(AppSettingService()..pref = preferences));
  tearDownAll(Get.reset);
  setUp(() {
    preferences.values.clear();
    preferences.failWrite = false;
  });

  test('Explore pins survive reload and respect sort, search, selection and menu', () async {
    final controller = PageExploreTab(0);
    addTearDown(controller.dispose);
    final alpha = LeftListModel(id: 1, name: 'Alpha', count: 10);
    final beta = LeftListModel(id: 2, name: 'Beta', count: 1);
    final gamma = LeftListModel(id: 3, name: 'Gamma', count: 20);
    controller.leftList.assignAll([alpha, beta, gamma]);
    controller.leftListSelected.value = alpha;
    controller.onLeftListDoSearch('');

    await controller.toggleLeftPin(beta);
    expect(controller.leftListFiltered, [beta, alpha, gamma]);
    expect(controller.leftListSelected.value, same(alpha));
    expect(controller.leftListSelectedIndex.value, 1);
    controller.onLeftSortChange('Count');
    expect(controller.leftListFiltered, [beta, gamma, alpha]);
    await controller.toggleLeftPin(alpha);
    expect(controller.leftListFiltered, [alpha, beta, gamma]);
    controller.onLeftListDoSearch('gam');
    expect(controller.leftListFiltered, [gamma]);
    controller.onLeftListDoSearch('');
    await controller.toggleLeftPin(alpha);
    await controller.toggleLeftPin(beta);
    expect(controller.leftListFiltered, [gamma, alpha, beta]);

    await controller.toggleLeftPin(beta);
    final restored = PageExploreTab(0);
    addTearDown(restored.dispose);
    expect(restored.isLeftPinned(LeftListModel(id: 2, name: 'Renamed')), isTrue);
    restored.currentMenuSelected.value = kSeries;
    expect(restored.isLeftPinned(beta), isFalse);
    await restored.toggleLeftPin(LeftListModel(id: 'random-old', name: 'Series'));
    expect(restored.isLeftPinned(LeftListModel(id: 'random-new', name: 'Series')), isTrue);
    restored.currentMenuSelected.value = kLabel;
    expect(restored.isLeftPinned(LeftListModel(name: 'Series')), isFalse);

    final previous = AppPref.getExplorePins();
    preferences.failWrite = true;
    await expectLater(AppPref.setExplorePins(['new']), throwsStateError);
    expect(AppPref.getExplorePins(), previous);
  });

  test('Explore totals local filesize and handles missing sizes', () {
    final controller = PageExploreTab(0);
    addTearDown(controller.dispose);
    expect(controller.rightListLocalTotalSize, 0);
    controller.rightListLocal.assignAll([
      Videos(filesize: 1024),
      Videos(filesize: 2048),
      Videos(filesize: null),
    ]);
    expect(controller.rightListLocalTotalSize, 3072);
    controller.rightListLocal.assignAll([Videos(filesize: 512)]);
    expect(controller.rightListLocalTotalSize, 512);
  });

  test('latest Explore menu request wins', () async {
    final controller = _DelayedExploreController();
    addTearDown(controller.dispose);

    final older = controller.onMenuChange(kActress);
    final latest = controller.onMenuChange(kActress);

    controller.second.complete([LeftListModel(id: 2, name: 'Latest', count: 1)]);
    await latest;
    controller.first.complete([LeftListModel(id: 1, name: 'Older', count: 1)]);
    await older;

    expect(controller.leftList.map((item) => item.name), ['Latest']);
  });
}
