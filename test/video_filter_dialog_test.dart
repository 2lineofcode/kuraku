import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/modules/home/page_download/page_download_search_tab.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_tab.dart';
import 'package:javit/app/modules/home/page_search/page_search_tab.dart';
import 'package:javit/app/utils/helper_opener.dart';

const adapter = VideoFilterAdapter<String>(
  videoCode: code,
  actresses: names,
  categories: names,
  releaseDate: date,
);
String code(String value) => value;
Iterable<String> names(String value) => [value];
String? date(String value) => null;

void main() {
  tearDown(Get.reset);

  test('empty filters preserve undated videos; reset retains loaded options', () {
    final state = VideoFilterState();
    state.categories.add('Category');
    state.actresses.add('Actress');
    expect(state.apply(['ABC'], adapter), ['ABC']);
    expect(state.isFiltered.value, isFalse);
    state.tecVideoCode.text = ' abc ';
    expect(state.apply(['ABC', 'DEF'], adapter), ['ABC']);
    state.currentRange.value = const RangeValues(2020, 2021);
    expect(state.apply(['ABC'], adapter), isEmpty);
    state.reset();
    expect(state.categories, ['Category']);
    expect(state.actresses, ['Actress']);
    expect(state.hasFilters, isFalse);
  });

  test('duration bounds include endpoints and exclude missing runtime only when active', () {
    final state = VideoFilterState();
    final durations = VideoFilterAdapter<num?>(videoCode: (_) => '', actresses: (_) => [], categories: (_) => [],
      releaseDate: (_) => null, durationMinutes: (value) => value);
    final values = <num?>[null, 0, 59, 60, 90, 120, 121, 600];
    expect(state.apply(values, durations), values);
    state.durationMin.value = 60;
    state.durationMax.value = 120;
    expect(state.apply(values, durations), [60, 90, 120]);
    expect(state.hasFilters, isTrue);
    state.durationMax.value = null;
    expect(state.apply(values, durations), [60, 90, 120, 121, 600]);
    state.durationMin.value = null;
    state.durationMax.value = 60;
    expect(state.apply(values, durations), [59, 60]);
    state.reset();
    expect(state.apply(values, durations), values);
    expect(state.hasFilters, isFalse);
  });

  test('duration preferences survive tab recreation in Search Download and Explore', () {
    final tabs = [PageSearchTab(0), PageDownloadSearchTab(0), PageExploreTab(0, pins: <String>{}.obs)];
    final restored = [PageSearchTab(1), PageDownloadSearchTab(1), PageExploreTab(1, pins: <String>{}.obs)];
    for (var i = 0; i < tabs.length; i++) {
      final dynamic tab = tabs[i];
      final dynamic copy = restored[i];
      tab.filter.durationMin.value = 60;
      tab.filter.durationMax.value = 180;
      copy.restorePreferences(tab.toPreferences());
      expect(copy.filter.durationMin.value, 60);
      expect(copy.filter.durationMax.value, 180);
      tab.dispose();
      copy.dispose();
    }
  });

  testWidgets('duration draft validates, applies, cancels and resets', (tester) async {
    final state = VideoFilterState();
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextButton(
      onPressed: () => HelperOpener.openFilterDialog(state: state, allVideos: <String>[], videos: <String>[].obs,
        adapter: adapter, showActressName: false, showCategories: false, showYears: false), child: const Text('Open')))));
    Future<void> open() async { await tester.tap(find.text('Open')); await tester.pumpAndSettle(); }
    await open();
    await tester.enterText(find.byKey(const ValueKey('filter-duration-min')), '120');
    await tester.enterText(find.byKey(const ValueKey('filter-duration-max')), '60');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Enter valid minutes; max must be at least min.'), findsOneWidget);
    expect(state.hasFilters, isFalse);
    await tester.enterText(find.byKey(const ValueKey('filter-duration-max')), '180');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(state.durationMin.value, 120);
    expect(state.durationMax.value, 180);
    await open();
    await tester.tap(find.text('Reset'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.durationMin.value, 120);
    await open();
    await tester.tap(find.text('Reset'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(state.hasFilters, isFalse);
  });

  testWidgets('filter drafts cancel, reset, apply and reject stale tabs', (tester) async {
    final state = VideoFilterState();
    state.actresses.add('Actress');
    state.categories.addAll(List.generate(20, (index) => 'Category $index'));
    state.tecVideoCode.text = 'ABC';
    state.isFiltered.value = true;
    final videos = ['ABC'].obs;
    var available = true;
    Future<void>? dialog;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextButton(
      onPressed: () {
        dialog = HelperOpener.openFilterDialog(
          state: state,
          allVideos: ['ABC', 'DEF'],
          videos: videos,
          adapter: adapter,
          isAvailable: () => available,
        );
      },
      child: const Text('Open'),
    ))));
    Future<void> open() async {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }
    final field = find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.placeholder == 'Contains video code...');
    await open();
    await tester.enterText(field, 'DEF');
    expect(state.tecVideoCode.text, 'ABC');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.tecVideoCode.text, 'ABC');
    expect(videos, ['ABC']);

    await open();
    await tester.tap(find.text('Reset'));
    expect(state.tecVideoCode.text, 'ABC');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.hasFilters, isFalse);
    expect(state.isFiltered.value, isFalse);
    expect(videos, ['ABC', 'DEF']);

    await open();
    await tester.enterText(field, ' DEF ');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.tecVideoCode.text, 'DEF');
    expect(videos, ['DEF']);

    await open();
    await tester.enterText(field, 'ABC');
    available = false;
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await dialog;
    expect(state.tecVideoCode.text, 'DEF');
    expect(videos, ['DEF']);

    available = true;
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    state.categoriesSelected.assignAll(state.categories);
    await open();

    expect(tester.takeException(), isNull);
    expect(find.text('Apply').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dialog;
  });
}
