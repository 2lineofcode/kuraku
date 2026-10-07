import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/db_r18.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_view.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tab extends PageExploreTab {
  _Tab(super.id, {super.pins, super.savingPin});
  Completer<List<LeftListModel>>? pendingMenu;
  final selections = <Completer<(List<Videos>, int)>>[];
  bool delaySelection = false;
  bool failMenu = false;
  int loads = 0;

  @override
  Future<bool> loadIsFresh() async => false;
  @override
  Future<List<LeftListModel>> getActressList() async => [];
  @override
  Future<List<LeftListModel>> getSeriesList() async {
    if (failMenu) throw StateError('Unavailable');
    return pendingMenu?.future ?? [LeftListModel(id: 'generated-${loads++}', name: 'Series A', count: 100)];
  }
  @override
  Future<List<LeftListModel>> getCategoryList() async => List.generate(100, (i) => LeftListModel(name: 'Category $i', count: 100));
  @override
  Future<(List<Videos>, int)> loadSelection(String menu, LeftListModel item) async {
    if (delaySelection) {
      final pending = Completer<(List<Videos>, int)>();
      selections.add(pending);
      return pending.future;
    }
    return (List.generate(100, (i) => Videos(id: '$i', title: 'Video $i')), 100);
  }
  @override
  Future<void> onSectionR18Tap() async {
    rightListViewMode.value = kR18;
    rightListR18.assignAll([{'video_code': 'TEST-001'}]);
    currentPage.value = 1;
  }
}

class _Controller extends PageExploreController {
  final pins = <String>{}.obs;
  final saving = false.obs;
  @override
  PageExploreTab createTab(int id) => _Tab(id, pins: pins, savingPin: saving);
}

class _View extends PageExploreTabView {
  const _View({super.key, required super.controller});
  @override
  Widget buildLayoutPoster(Videos video, double width, double height, {
    showReleaseDate = true, showViewCount = true, showQuality = true,
  }) => Text(video.title!);
}

void main() {
  final preferences = _Preferences();
  setUp(() {
    preferences.values.clear();
    Get.put(AppSettingService()..pref = preferences);
  });
  tearDown(Get.reset);

  test('actress cast mode restores legacy preferences and saves all three choices', () {
    final tab = _Tab(99);
    addTearDown(tab.dispose);
    tab.restorePreferences({'singleActress': false});
    expect(tab.actressMode.value, ActressMode.all);
    tab.restorePreferences({'singleActress': true});
    expect(tab.actressMode.value, ActressMode.single);
    for (final mode in ActressMode.values) {
      tab.actressMode.value = mode;
      final saved = jsonDecode(jsonEncode(tab.toPreferences())) as Map<String, dynamic>;
      tab.actressMode.value = ActressMode.single;
      tab.restorePreferences(saved);
      expect(tab.actressMode.value, mode);
    }
    tab.restorePreferences({'actressMode': 'unknown'});
    expect(tab.actressMode.value, ActressMode.single);
  });

  test('a pending selection cannot overwrite the count for a newer cast mode', () async {
    for (final menu in [kActress, kCategory, kSeries, kLabel, kStudio, kDirector, kYear]) {
      final tab = _Tab(99)..delaySelection = true;
      addTearDown(tab.dispose);
      tab.currentMenuSelected.value = menu;
      final loading = tab.onLeftListTap(LeftListModel(id: 1, name: menu));
      tab.actressMode.value = ActressMode.multi;
      tab.rightListR18TotalVideo.value = 7;
      tab.selections.single.complete(([Videos(id: '1', title: 'Video')], 99));
      await loading;
      expect(tab.rightListR18TotalVideo.value, 7, reason: menu);
      expect(tab.rightListLocal, hasLength(1));
    }
  });

  testWidgets('every R18 type exposes all, single and multi modes', (tester) async {
    final tab = _Tab(99);
    addTearDown(tab.dispose);
    tab.isFresh.value = false;
    tab.leftListSelected.value = LeftListModel(id: 1, name: 'Actress', imgUrl: '');
    tab.rightListLocal.assignAll([Videos(id: '1', title: 'Video')]);
    await tab.onSectionR18Tap();
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: _View(controller: tab))));
    await tester.pumpAndSettle();
    for (final menu in [kActress, kCategory, kSeries, kLabel, kStudio, kDirector, kYear]) {
      tab.currentMenuSelected.value = menu;
      await tester.pumpAndSettle();
      for (final option in const {'All': ActressMode.all, 'Multi Actress': ActressMode.multi, 'Single Actress': ActressMode.single}.entries) {
        tab.currentPage.value = 3;
        await tester.tap(find.byType(DropdownButton<ActressMode>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(option.key).last);
        await tester.pumpAndSettle();
        expect(tab.actressMode.value, option.value, reason: menu);
        expect(tab.currentPage.value, 1);
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Explore saves and restores tabs, drafts, filters and selection through refresh', (tester) async {
    final controller = Get.put<PageExploreController>(_Controller());
    await tester.pump();
    await controller.openSelection(kSeries, 'Series A');
    final first = controller.activeTab;
    first.tecSearchRight.text = 'draft';
    first.leftSortSelected.value = 'Count';
    first.actressMode.value = ActressMode.multi;
    first.filter.tecVideoCode.text = 'TEST';
    first.filter.categoriesSelected.assignAll(['Category']);
    first.filter.currentRange.value = const RangeValues(2010, 2020);
    first.filter.isFiltered.value = true;
    await first.onSectionR18Tap();
    controller.addTab();
    await tester.pump();
    await controller.openSelection(kCategory, 'Category 2');
    controller.activeTab.tecSearchLeft.text = 'unfinished draft';
    final saved = jsonDecode(jsonEncode(AppPref.getExploreTabs())) as Map<String, dynamic>;
    expect(saved['activeTab'], 1);
    await controller.onRefresh();
    expect(first.currentMenuSelected.value, kSeries);
    expect(first.leftListSelected.value.name, 'Series A');
    expect(first.rightListViewMode.value, kR18);
    expect(first.tecSearchRight.text, 'draft');
    expect(first.filter.categoriesSelected, ['Category']);
    expect(controller.activeTab.tecSearchLeft.text, 'unfinished draft');
    expect(AppPref.getExploreTabs(), saved);
    final after = controller.activeTab.toPreferences();
    await Get.delete<PageExploreController>(force: true);
    final restored = Get.put<PageExploreController>(_Controller());
    await tester.pump();
    expect(restored.tabs.length, 2);
    expect(restored.activeTabIndex.value, 1);
    expect(restored.activeTab.toPreferences(), after);
    expect(restored.tabs.first.title, 'Series A');
    expect(restored.tabs.first.rightListViewMode.value, kR18);
    expect(restored.tabs.first.currentPage.value, 1);
    expect(restored.tabs.first.filter.currentRange.value, const RangeValues(2010, 2020));
    expect(restored.tabs.first.actressMode.value, ActressMode.multi);
    expect(restored.tabs.first.filter.tecVideoCode.text, 'TEST');
    expect(restored.tabs.first.rightListLocal.length, 100);
  });

  testWidgets('Explore opens selections in new active tabs without changing the previous tab', (tester) async {
    final controller = Get.put<PageExploreController>(_Controller());
    await tester.pump();
    await controller.openSelection(kSeries, 'Series A');
    final original = controller.activeTab;
    original.tecSearchRight.text = 'draft';
    final saved = original.toPreferences();

    await controller.openSelection(kCategory, 'Category 2', newTab: true);
    await tester.pump();
    expect(controller.tabs.length, 2);
    expect(controller.activeTabIndex.value, 1);
    expect(controller.activeTab.currentMenuSelected.value, kCategory);
    expect(controller.activeTab.title, 'Category 2');
    expect(controller.activeTab.rightListLocal.length, 100);
    expect(original.toPreferences(), saved);
    expect(original.rightListLocal.length, 100);
    expect(AppPref.getExploreTabs()['activeTab'], 1);

    await controller.openSelection(kSeries, 'Series A', newTab: true);
    await tester.pump();
    expect(controller.tabs.length, 3);
    expect(controller.activeTabIndex.value, 2);
    expect(controller.tabs[1].title, 'Category 2');
    expect(controller.activeTab.title, 'Series A');
  });

  testWidgets('Ctrl and Command click modifiers open a new tab even when released during navigation', (tester) async {
    final controller = Get.put<PageExploreController>(_Controller());
    await tester.pump();
    for (final key in [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight, LogicalKeyboardKey.metaLeft]) {
      await tester.sendKeyDownEvent(key);
      final newTab = PageExploreController.isNewTabModifierPressed;
      await tester.sendKeyUpEvent(key);
      expect(newTab, isTrue);
      final count = controller.tabs.length;
      await controller.openSelection(kSeries, 'Series A', newTab: newTab);
      await tester.pump();
      expect(controller.tabs.length, count + 1);
      expect(controller.activeTab.title, 'Series A');
    }
    final active = controller.activeTab;
    final count = controller.tabs.length;
    expect(PageExploreController.isNewTabModifierPressed, isFalse);
    await controller.openSelection(kCategory, 'Category 2', newTab: PageExploreController.isNewTabModifierPressed);
    await tester.pump();
    expect(controller.tabs.length, count);
    expect(controller.activeTab, same(active));
    expect(active.title, 'Category 2');
  });

  testWidgets('Explore navigation stays in its original tab and closed loads cannot update state', (tester) async {
    final controller = Get.put<PageExploreController>(_Controller());
    await tester.pump();
    final first = controller.activeTab as _Tab;
    first.pendingMenu = Completer<List<LeftListModel>>();
    final navigation = controller.openSelection(kSeries, 'Series A');
    controller.addTab();
    await tester.pump();
    first.pendingMenu!.complete([LeftListModel(name: 'Series A')]);
    await navigation;
    expect(first.title, 'Series A');
    expect(controller.activeTab.title, kActress);
    first.delaySelection = true;
    final older = first.onLeftListTap(LeftListModel(name: 'Older'));
    final newer = first.onLeftListTap(LeftListModel(name: 'Newer'));
    first.selections[1].complete(([Videos(title: 'Newer')], 2));
    await newer;
    first.selections[0].complete(([Videos(title: 'Older')], 1));
    await older;
    expect(first.rightListLocal.single.title, 'Newer');
    final closed = first.onLeftListTap(LeftListModel(name: 'Closed'));
    controller.closeTab(0);
    first.selections.last.complete(([Videos(title: 'Closed')], 3));
    await closed;
    expect(first.isClosed, isTrue);
    expect(first.rightListLocal, isEmpty);
    await tester.pump();
    controller.closeTab(0);
    await tester.pump();
    expect(controller.tabs.length, 1);
    expect(controller.activeTab.isClosed, isFalse);
  });

  testWidgets('Explore pins are shared and failed refresh keeps saved selection', (tester) async {
    final controller = Get.put<PageExploreController>(_Controller());
    await tester.pump();
    await controller.openSelection(kSeries, 'Series A');
    final first = controller.activeTab as _Tab;
    controller.addTab();
    await tester.pump();
    await controller.openSelection(kSeries, 'Series A');
    await first.toggleLeftPin(first.leftListSelected.value);
    expect(controller.activeTab.isLeftPinned(controller.activeTab.leftListSelected.value), isTrue);
    final before = first.toPreferences();
    first.failMenu = true;
    await first.onRefresh();
    expect(first.toPreferences(), before);
    expect(first.error.value, isNotEmpty);
    expect(first.isLoading.value, isFalse);
  });

  testWidgets('Explore tab controls and shortcuts add, switch and close tabs', (tester) async {
    final controller = Get.put<PageExploreController>(_Controller());
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PageExploreView())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New Explore tab'));
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 2);
    expect(controller.activeTabIndex.value, 1);
    await tester.tap(find.text(kActress).first);
    await tester.pumpAndSettle();
    expect(controller.activeTabIndex.value, 0);
    await tester.tap(find.byTooltip('Close tab').first);
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 1);
    final remaining = controller.activeTab;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 2);
    expect(controller.activeTabIndex.value, 1);
    expect(controller.activeTab.fnSearchLeft.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 1);
    expect(controller.activeTab, same(remaining));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 1);
    expect(controller.activeTab, isNot(same(remaining)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Explore tabs keep separate left list and video scroll offsets', (tester) async {
    final controller = Get.put<PageExploreController>(_Controller());
    await tester.pump();
    await controller.openSelection(kCategory, 'Category 0');
    controller.activeTab.tecSearchLeft.clear();
    controller.activeTab.onLeftListDoSearch('');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Obx(() {
      final tab = controller.activeTab;
      return _View(key: ValueKey(tab.id), controller: tab);
    }))));
    await tester.pumpAndSettle();
    ScrollPosition position(String key) => tester.state<ScrollableState>(find.descendant(
      of: find.byKey(PageStorageKey(key)), matching: find.byType(Scrollable),
    )).position;
    position('explore-left-0-Category').jumpTo(200);
    position('explore-local:0:Category:null:Category 0').jumpTo(500);
    await tester.pumpAndSettle();
    controller.addTab();
    await tester.pump();
    await controller.openSelection(kCategory, 'Category 0');
    await tester.pumpAndSettle();
    expect(position('explore-local:1:Category:null:Category 0').pixels, 0);
    position('explore-local:1:Category:null:Category 0').jumpTo(800);
    await tester.pumpAndSettle();
    controller.selectTab(0);
    await tester.pumpAndSettle();
    expect(position('explore-left-0-Category').pixels, 200);
    expect(position('explore-local:0:Category:null:Category 0').pixels, 500);
    controller.selectTab(1);
    await tester.pumpAndSettle();
    expect(position('explore-local:1:Category:null:Category 0').pixels, 800);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
