import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_controller.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_search_tab.dart';
import 'package:kuraku/app/modules/home/page_sqleditor/page_sqleditor_tab.dart';
import 'package:kuraku/app/modules/home/page_sqleditor/page_sqleditor_view.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tab extends PageDownloadSearchTab {
  _Tab(super.id);
  Completer<Set<String>>? pendingCodes;
  @override
  Future<Set<String>> loadExistingVideoCodes() async => pendingCodes == null ? {'ABC-123'} : await pendingCodes!.future;
}

class _Download extends PageDownloadController {
  @override
  PageDownloadSearchTab createTab(int id) => _Tab(id);
  @override
  Future<void> loadDownloadHistory() async {}
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  void onReady() {}
  @override
  void onClose() { tecTopNavSearch.dispose(); fnTopNavSearch.dispose(); }
}

Map<String, dynamic> _result() => {
  'columns': [' Video_Code ', 'release_date', 'title', 'runtime_mins', 'categories', 'source_url'],
  'rows': [
    [' ABC-124 ', '2025-01-01', 'First result', 60, 'Drama, Older', 'https://example.com/selected-video'],
    ['ABC-123', '2024-01-01', 'Second result', 120, 'Drama'],
    ['ABC-124', '2025-01-01', 'Duplicate', 60, 'Drama'],
    [null], [42], ['invalid'],
  ],
};

void main() {
  setUp(() { Get.testMode = true; Get.put(AppSettingService()..pref = _Preferences()); });
  tearDown(Get.reset);

  test('SQL result mapping validates codes, aliases and partial rows without modifying the result', () {
    final sql = PageSqleditorTab(sources: const {'r18*.db': null});
    addTearDown(() => sql.onDelete());
    final data = _result();
    sql.result.value = data;
    expect(sql.downloadRows.map((row) => row['video_code']), ['ABC-124', 'ABC-123']);
    expect(sql.downloadRows.first['title'], 'First result');
    expect(sql.downloadRows.first['duration'], 60);
    expect((data['rows'] as List), hasLength(6));
    sql.result.value = {'columns': ['dvd_id', 'jacket_thumb_url'], 'rows': [['ABC-123', 'cover.jpg']]};
    expect(sql.downloadRows.single['poster'], 'cover.jpg');
    expect(sql.downloadRows.single['fan_art'], 'cover.jpg');
    for (final duration in ['NaN', 'Infinity', '-Infinity', 'not a number']) {
      sql.result.value = {'columns': ['video_code', 'duration', 'source_url'],
        'rows': [['ABC-123', duration, ' https://example.com/selected-video ']]};
      expect(sql.downloadRows.single['duration'], isNull);
      expect(sql.downloadRows.single['source_url'], 'https://example.com/selected-video');
    }
    sql.result.value = {'columns': ['code', 'title'], 'rows': [['ABC-123', 'Chat result']],
      'covers': {'ABC-123': 'https://example.com/cover.jpg'}};
    expect(sql.downloadRows.single['video_code'], 'ABC-123');
    expect(sql.downloadRows.single['fan_art'], 'https://example.com/cover.jpg');
    sql.running.value = true;
    expect(sql.downloadRows, isEmpty);
    sql.running.value = false;
    sql.result.value = {'columns': ['title'], 'rows': [['ABC-123']]};
    expect(sql.downloadRows, isEmpty);
    sql.result.value = {..._result(), 'write': true};
    expect(sql.downloadRows, isEmpty);
  });

  testWidgets('Results button opens a new Download tab with the exact ordered SQL snapshot', (tester) async {
    final download = Get.put<PageDownloadController>(_Download());
    final home = Get.put<HomeController>(_Home());
    final original = download.activeTab;
    original.tecSearch.text = 'Unsubmitted draft';
    final sql = Get.put(PageSqleditorTab(sources: const {'r18*.db': null}));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: sql))));
    await tester.pumpAndSettle();
    final button = find.byTooltip('Open results in Download');
    expect(tester.widget<AppIconButton>(find.byWidgetPredicate((widget) => widget is AppIconButton
      && widget.tooltip == 'Open results in Download')).onPressed, isNull);
    final data = _result();
    data['rows'] = (data['rows'] as List).map((row) => List.generate(6, (i) => i < (row as List).length ? row[i] : null)).toList();
    sql.result.value = data;
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(home.currentMenuSelected.value, kMenuDownload);
    expect(download.tabs, hasLength(2));
    expect(original.tecSearch.text, 'Unsubmitted draft');
    final tab = download.activeTab;
    expect(tab.videos.map((item) => item.videoCode), ['ABC-124', 'ABC-123']);
    expect(tab.videos.first.title, 'First result');
    expect(tab.havingVideos.value, 1);
    expect(tab.currentPage.value, 1);
    expect(tab.hasNextPage.value, isFalse);
    sql.result.value = null;
    await tab.onRefresh();
    expect(tab.videos, hasLength(2));
    tab.showHavingOnly(true);
    expect(tab.videos.single.videoCode, 'ABC-123');
    final saved = Map<String, dynamic>.from(jsonDecode(jsonEncode(tab.toPreferences())) as Map);
    final restored = _Tab(999)..restorePreferences(saved);
    addTearDown(restored.dispose);
    await restored.restoreSearch();
    expect(restored.allVideos.map((item) => item.videoCode), ['ABC-124', 'ABC-123']);
    expect(restored.videos.single.videoCode, 'ABC-123');
    expect(restored.title.value, 'SQL results');
    expect(restored.allVideos.first.categories, ['Drama', 'Older']);
    expect(restored.allVideos.first.sourceUrl, 'https://example.com/selected-video');
    restored.showHavingOnly(false);
    restored.filter.categoriesSelected.assignAll(['Drama', 'Older']);
    await restored.onRefresh();
    expect(restored.videos.single.videoCode, 'ABC-124');
    restored.filter.reset();
    await restored.onRefresh();
    expect(restored.videos, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('leaving a SQL snapshot immediately saves normal search and reset state', () async {
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    void save() { unawaited(AppPref.setDownloadTabs({'tabs': [tab.toPreferences()]})); }
    tab.watchPreferences(save);
    await tab.showResultRows('Saved SQL result', [{'video_code': 'ABC-123'}]);
    Map<String, dynamic> saved() => Map<String, dynamic>.from((AppPref.getDownloadTabs()['tabs'] as List).single as Map);
    expect(saved()['resultTitle'], 'Saved SQL result');
    tab.tecSearch.text = '/search';
    expect(saved().containsKey('resultRows'), isTrue);
    await tab.onSearch('/search');
    expect(saved().containsKey('resultRows'), isFalse);
    expect(saved()['query'], '/search');
    final restored = _Tab(2)..restorePreferences(saved());
    addTearDown(restored.dispose);
    await restored.restoreSearch();
    expect(restored.title.value, '/search');
    expect(restored.allVideos, isEmpty);
    await tab.showResultRows('SQL results', [{'video_code': 'ABC-123'}]);
    await tab.onReset();
    expect(saved().containsKey('resultRows'), isFalse);
    expect(saved()['query'], isEmpty);
  });

  test('SQL snapshots keep all returned rows beyond Download page size', () async {
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    await tab.showResultRows('SQL results', [for (var i = 100; i < 350; i++) {'video_code': 'ABC-$i'}]);
    expect(tab.videos, hasLength(250));
    expect(tab.totalResults.value, 250);
    expect(tab.hasNextPage.value, isFalse);
  });

  test('SQL snapshot loads cannot repopulate a reset or closed Download tab', () async {
    final sql = PageSqleditorTab(sources: const {'r18*.db': null})..result.value = _result();
    addTearDown(() => sql.onDelete());
    for (final close in [false, true]) {
      final tab = _Tab(1)..pendingCodes = Completer<Set<String>>();
      addTearDown(tab.dispose);
      final loading = tab.showResultRows('SQL results', sql.downloadRows);
      if (close) { tab.close(); } else { await tab.onReset(); }
      tab.pendingCodes!.complete({});
      await loading;
      expect(tab.videos, isEmpty);
    }
  });
}
