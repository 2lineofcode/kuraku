import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:kuraku/app/modules/home/page_explore/page_explore_view.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_tab.dart';
import 'package:kuraku/app/modules/home/page_search/page_search_view.dart';

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SearchView extends PageSearchTabView {
  const _SearchView({required super.controller});
  @override
  Widget buildLayoutPoster(Videos video, double width, double height, {
    bool isFanArt = false, bool interactive = true,
    showReleaseDate = true, showViewCount = true, showQuality = true, showTitle = true,
  }) => Text(video.title!);
}

class _ExploreView extends PageExploreTabView {
  const _ExploreView({required super.controller});
  @override
  Widget buildLayoutPoster(Videos video, double width, double height, {
    showReleaseDate = true, showViewCount = true, showQuality = true,
  }) => Text(video.title!);
}

void main() {
  testWidgets('Search and Explore restore independent scroll positions after switching pages', (tester) async {
    Get.put(AppSettingService()..pref = _Preferences());
    final search = PageSearchTab(0);
    addTearDown(search.dispose);
    final explore = PageExploreTab(0);
    addTearDown(explore.dispose);
    addTearDown(Get.reset);
    final showSearch = ValueNotifier(true);
    addTearDown(showSearch.dispose);
    final videos = List.generate(100, (i) => Videos(id: '$i', title: 'Video $i'));
    search.isFresh.value = false;
    search.tecSearch.text = 'Video';
    search.videos.assignAll(videos);
    explore.isFresh.value = false;
    explore.currentMenuSelected.value = kCategory;
    explore.leftListFiltered.assignAll(List.generate(100, (i) => LeftListModel(name: 'Category $i', count: 100)));
    explore.leftListSelected.value = explore.leftListFiltered.first;
    explore.rightListLocal.assignAll(videos);

    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: showSearch,
        builder: (context, searching, child) => searching ? _SearchView(controller: search) : _ExploreView(controller: explore),
      ),
    )));
    await tester.pumpAndSettle();
    search.scrollGridController.jumpTo(800);
    await tester.pumpAndSettle();
    showSearch.value = false;
    await tester.pumpAndSettle();
    expect(search.scrollGridController.hasClients, isFalse);

    ScrollPosition position(String key) => tester.state<ScrollableState>(find.descendant(
      of: find.byKey(PageStorageKey(key)), matching: find.byType(Scrollable),
    )).position;
    const leftKey = 'explore-left-0-Category';
    const localKey = 'explore-local:0:Category:null:Category 0';
    position(leftKey).jumpTo(200);
    position(localKey).jumpTo(500);
    await tester.pumpAndSettle();
    showSearch.value = true;
    await tester.pumpAndSettle();
    expect(search.scrollGridController.offset, 800);
    expect(search.tecSearch.text, 'Video');
    expect(search.videos.length, 100);

    showSearch.value = false;
    await tester.pumpAndSettle();
    expect(position(leftKey).pixels, 200);
    expect(position(localKey).pixels, 500);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
