import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/core/app_color.dart';
import 'package:javit/app/modules/home/page_download/page_download_search_tab.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_tab.dart';
import 'package:javit/app/modules/home/page_search/page_search_tab.dart';
import 'package:javit/app/modules/widgets/widget_controls.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:javit/app/utils/helper_opener.dart';

import 'icon_finder.dart';

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

  testWidgets('filter foregrounds contrast with their backgrounds in both themes', (tester) async {
    double contrast(Color foreground, Color background) {
      final a = Color.alphaBlend(foreground, background).computeLuminance();
      final b = background.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }
    for (final brightness in Brightness.values) {
      final state = VideoFilterState();
      state.actresses.add('Actress');
      state.categories.add('Category');
      state.categoriesSelected.add('Category');
      await tester.pumpWidget(GetMaterialApp(
        key: ValueKey(brightness), theme: AppStyle.theme(brightness),
        home: Scaffold(body: TextButton(
          onPressed: () => HelperOpener.openFilterDialog(state: state, allVideos: <String>[], videos: <String>[].obs,
            adapter: adapter), child: const Text('Open'))),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final filterIcon = tester.widget<HugeIcon>(findHugeIcon(HugeIcons.strokeRoundedFilter));
      expect(contrast(filterIcon.color!, AppColor.selected), greaterThanOrEqualTo(4.5));
      final chip = tester.widget<InputChip>(find.byType(InputChip));
      expect(contrast((chip.label as Text).style!.color!, chip.backgroundColor!), greaterThanOrEqualTo(4.5));
      expect(contrast((chip.deleteIcon as HugeIcon).color!, chip.backgroundColor!), greaterThanOrEqualTo(4.5));
      for (final label in ['Match any', 'Any year']) {
        final text = tester.widget<Text>(find.text(label));
        expect(contrast(text.style!.color!, label == 'Match any' ? AppColor.container : AppColor.panel), greaterThanOrEqualTo(4.5));
      }
      final addIcon = tester.widget<HugeIcon>(findHugeIcon(HugeIcons.strokeRoundedAdd01));
      expect(contrast(addIcon.color!, AppColor.container), greaterThanOrEqualTo(3));
      final slider = SliderTheme.of(tester.element(find.byType(RangeSlider)));
      expect(contrast(slider.thumbColor!, AppColor.panel), greaterThanOrEqualTo(3));
      expect(contrast(slider.activeTrackColor!, AppColor.panel), greaterThanOrEqualTo(3));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
    }
  });

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

  test('blacklist excludes any matching field and restores only valid rules', () {
    final state = VideoFilterState();
    final adapter = VideoFilterAdapter<Map<String, String>>(
      videoCode: (video) => video['code']!, title: (video) => video['title'],
      actresses: (_) => [], categories: (_) => [], releaseDate: (_) => null,
    );
    final videos = [
      {'code': 'ad-123', 'title': 'Normal'},
      {'code': 'ABC-123', 'title': 'A vr trailer'},
      {'code': 'ABC-124', 'title': 'Normal'},
    ];
    state.blacklist.addAll([
      VideoBlacklistRule(field: VideoBlacklistField.videoCode, pattern: 'AD-(.*)'),
      VideoBlacklistRule(field: VideoBlacklistField.title, pattern: '(.*)VR(.*)'),
    ]);
    expect(state.apply(videos, adapter), [videos.last]);
    expect(state.hasFilters, isTrue);
    expect(() => VideoBlacklistRule(field: VideoBlacklistField.title, pattern: '['), throwsFormatException);
    expect(() => VideoBlacklistRule(field: VideoBlacklistField.title, pattern: '  '), throwsFormatException);
    final tabs = [PageSearchTab(0), PageDownloadSearchTab(0), PageExploreTab(0, pins: <String>{}.obs)];
    final copies = [PageSearchTab(1), PageDownloadSearchTab(1), PageExploreTab(1, pins: <String>{}.obs)];
    for (var i = 0; i < tabs.length; i++) {
      final dynamic tab = tabs[i];
      final dynamic copy = copies[i];
      (tab.filter as VideoFilterState).blacklist.assignAll(state.blacklist);
      copy.restorePreferences(jsonDecode(jsonEncode(tab.toPreferences())) as Map<String, dynamic>);
      expect((copy.filter as VideoFilterState).apply(videos, adapter), [videos.last]);
      expect(copy.filter.isFiltered.value, isTrue);
      tab.dispose();
      copy.dispose();
    }
    state.restoreBlacklist([{'field': 'title', 'pattern': '['}, {'field': 'unknown', 'pattern': 'VR'}, null]);
    expect(state.blacklist, isEmpty);
    state.reset();
    expect(state.hasFilters, isFalse);
    expect(state.apply(videos, adapter), videos);
  });

  test('filters match decensored titles and categories without changing raw values', () {
    final state = VideoFilterState();
    final adapter = VideoFilterAdapter<Map<String, String>>(
      videoCode: (video) => video['code']!, title: (video) => video['title'],
      actresses: (_) => [], categories: (video) => [video['category']!], releaseDate: (_) => null,
    );
    final videos = [
      {'code': 'ABC-001', 'title': 'A D***k scene', 'category': 'D***k'},
      {'code': 'ABC-002', 'title': 'A Drunk scene', 'category': 'Drunk'},
      {'code': 'ABC-003', 'title': 'Normal', 'category': 'Drama'},
    ];
    state.blacklist.add(VideoBlacklistRule(field: VideoBlacklistField.title, pattern: 'Drunk'));
    expect(state.apply(videos, adapter), [videos.last]);
    state.blacklist.clear();
    for (final category in ['D***k', 'Drunk']) {
      state.categoriesSelected.assignAll([category]);
      expect(state.apply(videos, adapter), videos.take(2));
    }
    expect(videos.first['title'], 'A D***k scene');
    expect(videos.first['category'], 'D***k');
  });

  testWidgets('filter category labels are decensored while selections retain raw R18 names', (tester) async {
    final state = VideoFilterState();
    state.categories.add('D***k');
    state.categoriesSelected.add('D***k');
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextButton(
      onPressed: () => HelperOpener.openFilterDialog(state: state, allVideos: <String>[], videos: <String>[].obs,
        adapter: adapter, showActressName: false, showYears: false), child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Drunk'), findsOneWidget);
    expect(find.text('D***k'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(InputChip), matching: findHugeIcon(HugeIcons.strokeRoundedCancel01)));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.placeholder == 'Search and add categories...');
    await tester.enterText(field, 'Drunk');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    final suggestion = find.byWidgetPredicate((widget) => widget is Text && widget.data == 'Drunk');
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(state.categoriesSelected, ['D***k']);
  });

  testWidgets('blacklist editor validates regex, drafts, removes and resets', (tester) async {
    final state = VideoFilterState();
    final videos = ['AD-123', 'ABC-123'].obs;
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: TextButton(
      onPressed: () => HelperOpener.openFilterDialog(state: state, allVideos: ['AD-123', 'ABC-123'], videos: videos,
        adapter: adapter, showActressName: false, showCategories: false, showYears: false), child: const Text('Open')))));
    Future<void> open() async { await tester.tap(find.text('Open')); await tester.pumpAndSettle(); }
    final field = find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.placeholder == 'AD-(.*)');
    await open();
    await tester.tap(find.byTooltip('Add blacklist rule'));
    await tester.pumpAndSettle();
    await tester.enterText(field, '[');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid regex pattern.'), findsOneWidget);
    expect(state.blacklist, isEmpty);
    await tester.enterText(field, 'AD-(.*)');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(videos, ['ABC-123']);
    await open();
    await tester.tap(find.byType(AppDropdown<VideoBlacklistField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.placeholder == '(.*)VR(.*)'), '(.*)VR(.*)');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.blacklist.single.field, VideoBlacklistField.videoCode);
    await open();
    await tester.tap(find.byTooltip('Add blacklist rule'));
    await tester.pumpAndSettle();
    await tester.enterText(field.last, '^ABC-');
    await tester.tap(find.byTooltip('Remove blacklist rule').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('^ABC-'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(state.hasFilters, isFalse);
    expect(videos, ['AD-123', 'ABC-123']);
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
    state.blacklist.addAll([
      VideoBlacklistRule(field: VideoBlacklistField.videoCode, pattern: 'AD-(.*)'),
      VideoBlacklistRule(field: VideoBlacklistField.title, pattern: '(.*)VR(.*)'),
    ]);
    await open();

    expect(tester.takeException(), isNull);
    expect(find.text('Apply').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dialog;
  });
}
