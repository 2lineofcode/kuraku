import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/page_home/page_home_controller.dart';
import 'package:javit/app/modules/home/page_home/page_home_view.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => true as T;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends PageHomeController {
  @override
  Future<void> onRefresh() async {}
}

class _HomeView extends PageHomeView {
  @override
  Widget buildLayoutFanArt(Videos video, {List<Videos>? items}) => SizedBox(width: 260, child: Text(video.title!));

  @override
  Widget buildLayoutPoster(Videos video, {
    List<Videos>? items,
    double width = 135, double height = 210,
    showReleaseDate = true, showViewCount = true, showQuality = true,
  }) => SizedBox(width: width, child: Text(video.title!));
}

void main() {
  testWidgets('Home previews four Hugeicons at the shared size in both themes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Get.put(AppSettingService()..pref = _Preferences());
    final controller = Get.put<PageHomeController>(_Controller());
    addTearDown(Get.reset);
    controller.totalVideo.value = 1;
    controller.homeSectionOrder.assignAll([
      AppPref.homeSecNewRelease, AppPref.homeSecRecommendation, AppPref.homeSecRandom, AppPref.homeSecFavorite,
    ]);
    for (final list in [controller.listNewRelease, controller.listRecommendation, controller.listRandom, controller.listFavorite]) {
      list.add(Videos(title: 'Video'));
    }
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: brightness), home: Scaffold(body: _HomeView())));
      await tester.pumpAndSettle();
      final headingIcons = find.descendant(of: find.byType(ReorderableDragStartListener), matching: find.byType(HugeIcon));
      final icons = tester.widgetList<HugeIcon>(headingIcons).toList();
      expect(icons.map((icon) => icon.icon), [
        HugeIcons.strokeRoundedFire, HugeIcons.strokeRoundedSparkles, HugeIcons.strokeRoundedShuffle, HugeIcons.strokeRoundedFavourite,
      ]);
      for (final icon in icons) expect(icon.size, AppStyle.iconSize);
      for (final element in headingIcons.evaluate()) {
        expect(tester.getSize(find.byWidget(element.widget)), const Size(AppStyle.iconSize, AppStyle.iconSize));
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Home handles unknown sections in saved order', (tester) async {
    Get.put(AppSettingService()..pref = _Preferences());
    final controller = Get.put<PageHomeController>(_Controller());
    addTearDown(Get.reset);
    controller.totalVideo.value = 1;
    controller.homeSectionOrder.assignAll(['unknown-section', AppPref.homeSecNewRelease]);
    controller.listNewRelease.add(Videos(title: 'Video'));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _HomeView())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Video'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Home restores vertical and per-section horizontal scroll after leaving the page', (tester) async {
    Get.put(AppSettingService()..pref = _Preferences());
    final controller = Get.put<PageHomeController>(_Controller());
    addTearDown(Get.reset);
    controller.totalVideo.value = 100;
    controller.homeSectionOrder.assignAll([
      AppPref.homeSecNewRelease, AppPref.homeSecFavorite, AppPref.homeSecRandom, AppPref.homeSecOldest,
    ]);
    final videos = List.generate(100, (i) => Videos(title: 'Video $i'));
    for (final list in [controller.listNewRelease, controller.listFavorite, controller.listRandom, controller.listOldest]) {
      list.assignAll(videos);
    }
    final showHome = ValueNotifier(true);
    addTearDown(showHome.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<bool>(
      valueListenable: showHome,
      builder: (context, visible, child) => visible ? _HomeView() : const Text('Other page'),
    ))));
    await tester.pumpAndSettle();
    ScrollPosition position(String key) => tester.state<ScrollableState>(find.descendant(
      of: find.byKey(PageStorageKey(key)), matching: find.byType(Scrollable),
    ).first).position;
    final releaseKey = 'home-videos-${AppPref.homeSecNewRelease}';
    final favoriteKey = 'home-videos-${AppPref.homeSecFavorite}';
    position(releaseKey).jumpTo(600);
    position(favoriteKey).jumpTo(300);
    position('home-sections').jumpTo(150);
    await tester.pumpAndSettle();
    showHome.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsNothing);
    showHome.value = true;
    await tester.pumpAndSettle();
    expect(position('home-sections').pixels, 150);
    expect(position(releaseKey).pixels, 600);
    expect(position(favoriteKey).pixels, 300);
    controller.homeSectionOrder.assignAll([
      AppPref.homeSecFavorite, AppPref.homeSecNewRelease, AppPref.homeSecRandom, AppPref.homeSecOldest,
    ]);
    await tester.pumpAndSettle();
    expect(position(releaseKey).pixels, 600);
    expect(position(favoriteKey).pixels, 300);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
