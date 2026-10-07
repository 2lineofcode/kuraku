import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/__javit_search_entity.dart';
import 'package:javit/app/data/models/__javmost_new_release.dart';
import 'package:javit/app/modules/home/page_download/page_download_controller.dart';
import 'package:javit/app/modules/home/page_download/page_download_search_tab.dart';
import 'package:javit/app/modules/home/page_download/page_download_view.dart';
import 'package:javit/app/utils/helper_opener.dart';

import 'icon_finder.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends PageDownloadController {
  @override
  PageDownloadSearchTab createTab(int id) => _SearchTab(id);
  @override
  Future<void> loadDownloadHistory() async {}
}

class _DownloadController extends _Controller {
  int starts = 0;
  @override
  Future<void> startDownload() async { starts++; }
}

class _SearchTab extends PageDownloadSearchTab {
  _SearchTab(super.id);
  final pending = <Completer<JavMostModel>>[];
  final pages = <int>[];

  @override
  Future<List<String>> loadHistory(String query) async => [];
  @override
  Future<void> saveHistory(String query) async {}

  @override
  Future<JavMostModel> fetchJavMostByCommand(String command, int page) {
    pages.add(page);
    final result = Completer<JavMostModel>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<Set<String>> loadExistingVideoCodes() async => {'SSIS-001'};
}

class _HistoryTab extends _SearchTab {
  _HistoryTab(super.id);
  final history = ['/top-weekly', '/top-monthly'];
  final saved = <String>[];
  Completer<List<String>>? pendingHistory;
  @override
  Future<List<String>> loadHistory(String query) async => pendingHistory?.future ?? history.where((item) => item.contains(query.trim())).toList();
  @override
  Future<void> saveHistory(String query) async { saved.add(query); }
  @override
  Future<void> deleteHistory(String query) async { history.remove(query); }
  @override
  Future<void> clearHistory() async { history.clear(); }
}

class _SearchView extends PageDownloadSearchView {
  const _SearchView({super.key, required super.controller});

  @override
  Widget modeWrapView() {
    final listener = super.modeWrapView() as NotificationListener<ScrollMetricsNotification>;
    final grid = listener.child as GridView;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: listener.onNotification,
      child: GridView.builder(
        key: grid.key,
        controller: grid.controller,
        gridDelegate: grid.gridDelegate,
        itemCount: controller.videos.length,
        itemBuilder: (context, index) => Text(controller.videos[index].videoCode ?? ''),
      ),
    );
  }
}

JavMostModel result(String code, {int total = 1}) => JavMostModel(
  success: true, total: total,
  result: [Result(name: code, fullName: code, release: '2024-01-01', cover: '', genre: 'Drama')],
);

void main() {
  final preferences = _Preferences();
  setUp(() {
    preferences.values.clear();
    Get.put(AppSettingService()..pref = preferences);
  });
  tearDown(Get.reset);

  testWidgets('picking online by click or Enter keeps the search field ready for typing', (tester) async {
    final tab = _SearchTab(1);
    addTearDown(tab.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageDownloadSearchView(controller: tab))));
    final emptyPosition = tester.getTopLeft(find.text('~ Type Something ~'));
    for (final useKeyboard in [false, true]) {
      await tester.enterText(find.byType(CupertinoTextField), '/');
      await tester.pumpAndSettle();
      expect(find.text('/new-release'), findsOneWidget);
      expect(tester.getTopLeft(find.text('~ Type Something ~')), emptyPosition);
      if (useKeyboard) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.testTextInput.receiveAction(TextInputAction.done);
      } else {
        await tester.tap(find.text('/online'));
      }
      await tester.pumpAndSettle();
      expect(tab.fnSearch.hasFocus, isTrue);
      expect(tab.tecSearch.text, '/online ');
      expect(tab.tecSearch.selection, TextSelection.collapsed(offset: 8));
      expect(tab.isCommandSuggestionVisible.value, isFalse);
      expect(tab.pending, isEmpty);
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: '/online keyword', selection: TextSelection.collapsed(offset: 15),
      ));
      await tester.pump();
      expect(tab.tecSearch.text, '/online keyword');
    }
    await tester.enterText(find.byType(CupertinoTextField), '/');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('/new-release'), findsNothing);
    expect(tester.getTopLeft(find.text('~ Type Something ~')), emptyPosition);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}));

  testWidgets('Download history supports filtering, keyboard selection, removal and stale-result guards', (tester) async {
    final tab = _HistoryTab(1);
    addTearDown(tab.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SearchView(controller: tab))));
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), '   ');
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), 't');
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, ['/top-weekly', '/top-monthly']);
    await tester.tap(find.byTooltip('Remove from history').last);
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, ['/top-weekly']);
    expect(tab.fnSearch.hasFocus, isTrue);
    await tester.enterText(find.byType(CupertinoTextField), 'weekly');
    await tester.pump(const Duration(milliseconds: 200));
    expect(tab.historySuggestions, ['/top-weekly']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tab.tecSearch.text, '/top-weekly');
    expect(tab.saved, ['/top-weekly']);
    expect(tab.pending.length, 1);
    expect(tab.historySuggestions, isEmpty);
    tab.pending.single.complete(result('SSIS-001'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField), '');
    await tester.pump(const Duration(milliseconds: 200));
    expect(tab.historySuggestions, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), 'w');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tab.historySuggestions, isEmpty);
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/top-weekly'));
    await tester.pump();
    expect(tab.saved.length, 2);
    tab.pending.last.complete(result('SSIS-001'));
    await tester.pumpAndSettle();

    tab.pendingHistory = Completer<List<String>>();
    await tester.enterText(find.byType(CupertinoTextField), 'old');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(CupertinoTextField), '/on');
    tab.pendingHistory!.complete(['stale']);
    await tester.pump();
    expect(tab.historySuggestions, isEmpty);
    expect(tab.isCommandSuggestionVisible.value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Clear all requires Yes and preserves history when choosing No', (tester) async {
    final tab = _HistoryTab(1);
    addTearDown(tab.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SearchView(controller: tab))));
    await tester.enterText(find.byType(CupertinoTextField), 'weekly');
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, ['/top-weekly']);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(tab.history, ['/top-weekly', '/top-monthly']);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(tab.history, ['/top-weekly', '/top-monthly']);
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(tab.history, isEmpty);
    expect(tab.historySuggestions, isEmpty);
    expect(tab.tecSearch.text, 'weekly');
    expect(tab.fnSearch.hasFocus, isTrue);
    expect(find.text('Clear all'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Download restores tab preferences and Having without restarting downloads', (tester) async {
    await AppPref.setSearchTabs({'tabs': [{'query': 'Local query'}]});
    final controller = Get.put<PageDownloadController>(_Controller());
    final first = controller.activeTab;
    first.tecSearch.text = '/new-release';
    first.filter.tecVideoCode.text = 'SSIS';
    first.filter.tecActressName.text = 'Alice';
    first.filter.tecCategory.text = 'Draft category';
    first.filter.categoriesSelected.assignAll(['Drama']);
    first.filter.currentRange.value = RangeValues(2022, 2025);
    first.filter.isFiltered.value = true;
    first.havingOnly.value = true;
    controller.addTab();
    controller.activeTab.tecSearch.text = '/online unsubmitted draft';
    controller.addTab();
    controller.activeTab.filter.tecCategory.text = 'Unselected category';
    controller.selectTab(1);
    controller.downloadStdout.value = 'Download running';
    final expected = first.toPreferences();
    final saved = jsonDecode(jsonEncode(AppPref.getDownloadTabs())) as Map<String, dynamic>;
    await Get.delete<PageDownloadController>();
    await AppPref.setDownloadTabs(saved);
    final restored = Get.put<PageDownloadController>(_Controller());
    expect(restored.tabs.length, 3);
    expect(restored.activeTabIndex.value, 1);
    expect(restored.activeTab.tecSearch.text, '/online unsubmitted draft');
    expect(restored.tabs.first.toPreferences(), expected);
    expect(restored.tabs.last.filter.tecCategory.text, 'Unselected category');
    expect(restored.downloadStdout.value, '');
    expect(restored.currentProcessDownload.value, isNull);
    (restored.tabs.first as _SearchTab).pending.single.complete(JavMostModel(success: true, total: 2, result: [
      Result(name: 'SSIS-001', genre: 'Drama', star: 'Alice', release: '2024-01-01'),
      Result(name: 'SSIS-002', genre: 'Drama', star: 'Alice', release: '2024-01-01'),
    ]));
    (restored.tabs[1] as _SearchTab).pending.single.complete(result('SSIS-002'));
    await tester.pump();
    expect(restored.tabs.first.havingOnly.value, isTrue);
    expect(restored.tabs.first.videos.single.videoCode, 'SSIS-001');
    restored.tabs[1].tecSearch.text = '/online changed draft';
    final beforeRefresh = jsonDecode(jsonEncode(AppPref.getDownloadTabs()));
    final refresh = restored.onRefresh();
    (restored.tabs.first as _SearchTab).pending.last.complete(JavMostModel(success: true, total: 1, result: [
      Result(name: 'SSIS-001', genre: 'Drama', star: 'Alice', release: '2024-01-01'),
    ]));
    await tester.pump();
    (restored.tabs[1] as _SearchTab).pending.last.complete(result('SSIS-002'));
    await refresh;
    expect(AppPref.getDownloadTabs(), beforeRefresh);
    expect(restored.tabs.first.title.value, '/new-release');
    expect(restored.tabs.first.videos.single.videoCode, 'SSIS-001');
    expect(restored.tabs.first.havingOnly.value, isTrue);
    expect(restored.activeTabIndex.value, 1);
    expect(restored.tabs.last.filter.tecCategory.text, 'Unselected category');
    restored.closeTab(1);
    await tester.pump();
    expect((AppPref.getDownloadTabs()['tabs'] as List).length, 2);
    expect((AppPref.getSearchTabs()['tabs'] as List).single['query'], 'Local query');
    await Get.delete<PageDownloadController>();

    await AppPref.setDownloadTabs({'tabs': [null, {'query': 12, 'yearStart': 3000, 'yearEnd': 1000}], 'activeTab': 99});
    final invalid = Get.put<PageDownloadController>(_Controller());
    expect(invalid.tabs.length, 1);
    expect(invalid.activeTabIndex.value, 0);
    expect(invalid.activeTab.tecSearch.text, '');
    expect(invalid.activeTab.filter.currentRange.value.start, 2000);
    invalid.closeTab(0);
    await tester.pump();
    expect((AppPref.getDownloadTabs()['tabs'] as List).length, 1);
    await Get.delete<PageDownloadController>();
    await tester.pump();
  });

  testWidgets('Download matches all categories while shared local filtering matches any', (tester) async {
    final tab = _SearchTab(1);
    addTearDown(tab.dispose);
    final rows = [
      Result(name: 'SSIS-001', genre: 'Drama', star: 'Alice', release: '2024-01-01'),
      Result(name: 'SSIS-002', genre: 'Romance', star: 'Alice', release: '2024-01-01'),
      Result(name: 'SSIS-003', genre: 'Drama, Romance', star: 'Alice', release: '2024-01-01'),
      Result(name: 'SSIS-004', genre: 'Other', star: 'Alice', release: '2024-01-01'),
      Result(name: 'SSIS-005', genre: '', star: 'Alice', release: '2024-01-01'),
      Result(name: 'SSIS-006', genre: 'Drama', star: 'Alice', release: '2020-01-01'),
      Result(name: 'SSIS-007', genre: 'Drama', star: 'Bob', release: '2024-01-01'),
      Result(name: 'ABP-001', genre: 'Drama', star: 'Alice', release: '2024-01-01'),
    ];
    tab.filter.categoriesSelected.assignAll(['Drama', 'Romance']);
    tab.filter.tecVideoCode.text = 'SSIS';
    tab.filter.tecActressName.text = 'Alice';
    tab.filter.currentRange.value = RangeValues(2023, 2025);
    final search = tab.onSearch('/new-release');
    tab.pending.single.complete(JavMostModel(success: true, total: rows.length, result: rows));
    await search;
    expect(tab.videos.map((video) => video.videoCode), ['SSIS-003']);

    final adapter = VideoFilterAdapter<Result>(
      videoCode: (video) => video.name ?? '',
      actresses: (video) => [video.star ?? ''],
      categories: (video) => (video.genre ?? '').split(',').map((value) => value.trim()),
      releaseDate: (video) => video.release,
    );
    expect(tab.filter.apply(rows, adapter).map((video) => video.name), ['SSIS-001', 'SSIS-002', 'SSIS-003']);
    tab.filter.categoriesSelected.clear();
    expect(tab.filter.apply(rows, adapter).length, 5);
    tab.filter.reset();
    tab.filter.categoriesSelected.add('D***k');
    final decensored = tab.onSearch('/new-release');
    tab.pending.last.complete(JavMostModel(success: true, total: 2, result: [
      Result(name: 'SSIS-008', genre: 'Drunk', release: '2024-01-01'),
      Result(name: 'SSIS-009', genre: 'D***k', release: '2024-01-01'),
    ]));
    await decensored;
    expect(tab.videos.map((video) => video.videoCode), ['SSIS-008', 'SSIS-009']);
    await tester.pump();
  });

  testWidgets('Download blacklist survives Result Having and incoming pages', (tester) async {
    final tab = _SearchTab(1);
    addTearDown(tab.dispose);
    tab.filter.blacklist.addAll([
      VideoBlacklistRule(field: VideoBlacklistField.videoCode, pattern: r'^SSIS-001$'),
      VideoBlacklistRule(field: VideoBlacklistField.title, pattern: '(.*)VR(.*)'),
    ]);
    final search = tab.onSearch('/new-release');
    tab.pending.single.complete(JavMostModel(success: true, total: 3, result: [
      Result(name: 'SSIS-001', fullName: 'Normal', release: '2024-01-01'),
      Result(name: 'SSIS-002', fullName: 'A vr video', release: '2024-01-01'),
      Result(name: 'SSIS-003', fullName: 'Normal', release: '2024-01-01'),
    ]));
    await search;
    expect(tab.allVideos.length, 3);
    expect(tab.videos.map((video) => video.videoCode), ['SSIS-003']);
    expect(tab.havingVideos.value, 0);
    tab.showHavingOnly(true);
    expect(tab.videos, isEmpty);
    tab.showHavingOnly(false);
    expect(tab.videos.map((video) => video.videoCode), ['SSIS-003']);
    final next = tab.onSearch('/top-weekly');
    tab.pending.last.complete(result('SSIS-001'));
    await next;
    expect(tab.videos, isEmpty);
    tab.filter.blacklist.clear();
    tab.showHavingOnly(false);
    expect(tab.videos.single.videoCode, 'SSIS-001');
    await tester.pump();
  });

  testWidgets('Result and Having filter loaded videos and recover from empty matches', (tester) async {
    final tab = _SearchTab(1);
    final other = _SearchTab(2);
    addTearDown(tab.dispose);
    addTearDown(other.dispose);
    final search = tab.onSearch('/new-release');
    tab.pending.single.complete(JavMostModel(success: true, total: 2, result: [
      Result(name: 'SSIS-001', release: '2024-01-01'),
      Result(name: 'SSIS-002', release: '2024-01-01'),
    ]));
    await search;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SearchView(controller: tab))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Having: 1'));
    await tester.pumpAndSettle();
    expect(tab.videos.map((video) => video.videoCode), ['SSIS-001']);
    expect(tab.allVideos.length, 2);
    expect(tab.totalResults.value, 2);
    expect(other.havingOnly.value, isFalse);
    await tester.tap(find.text('Result : 2'));
    await tester.pumpAndSettle();
    expect(tab.videos.length, 2);

    tab.allVideos.first.match = false;
    await tester.tap(find.text('Having: 1'));
    await tester.pumpAndSettle();
    expect(tab.videos, isEmpty);
    expect(find.text('No Owned Videos'), findsOneWidget);
    await tester.tap(find.text('Result : 2'));
    await tester.pumpAndSettle();
    expect(tab.videos.length, 2);

    tab.showHavingOnly(true);
    final next = tab.onSearch('/top-weekly');
    expect(tab.havingOnly.value, isFalse);
    tab.pending.last.complete(result('SSIS-002'));
    await next;
    expect(tab.videos.single.videoCode, 'SSIS-002');
    tab.showHavingOnly(true);
    await tab.onReset();
    expect(tab.havingOnly.value, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Download searches stay independent and ignore stale or closed requests', (tester) async {
    final first = _SearchTab(1);
    final second = _SearchTab(2);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final a = first.onSearch('/new-release');
    final b = second.onSearch('/top-weekly');
    second.pending[0].complete(result('SSIS-002'));
    await b;
    expect(first.isLoading.value, isTrue);
    expect(first.videos, isEmpty);
    expect(second.videos.single.videoCode, 'SSIS-002');
    first.pending[0].complete(result('SSIS-001'));
    await a;
    expect(first.videos.single.videoCode, 'SSIS-001');
    expect(first.havingVideos.value, 1);

    final older = first.onSearch('/top-daily');
    final newer = first.onSearch('/top-monthly');
    first.pending[2].complete(result('SSIS-003'));
    await newer;
    first.pending[1].complete(result('SSIS-004'));
    await older;
    expect(first.videos.single.videoCode, 'SSIS-003');
    expect(first.title.value, '/top-monthly');
    expect(first.isLoading.value, isFalse);

    final failing = second.onSearch('/best-rated');
    second.pending[1].completeError(StateError('Offline'));
    await failing;
    expect(second.error.value, isNotEmpty);
    expect(second.isLoading.value, isFalse);
    expect(first.error.value, isEmpty);

    final closing = first.onSearch('/top-daily');
    first.close();
    first.pending[3].complete(result('SSIS-005'));
    await closing;
    expect(first.videos, isEmpty);
    await tester.pump();
  });

  testWidgets('Download options persist without starting a job and completion clears only job state', (tester) async {
    final controller = Get.put<PageDownloadController>(_Controller());
    controller.mode.value = 'hls';
    controller.headless.value = true;
    controller.allowPopups.value = true;
    controller.tecDirectory.text = '/tmp/videos';
    controller.tecConcurrency.text = '12';
    controller.tecRetries.text = '5';
    controller.tecTimeout.text = '60';
    controller.tecReferer.text = 'https://example.com/';
    controller.tecUserAgent.text = 'Custom agent';
    controller.tecCaptureDuration.text = '45';
    controller.tecPlaySelector.text = '.play-button';
    controller.tecUrl.text = 'https://example.com/video';
    controller.tecFilename.text = 'movie.mp4';
    await tester.pump(const Duration(milliseconds: 300));
    final saved = AppPref.getDownloadOptions();
    expect(saved, {
      'mode': 'hls', 'headless': true, 'allow_popups': true, 'directory': '/tmp/videos',
      'concurrency': '12', 'retries': '5', 'timeout': '60', 'referer': 'https://example.com/',
      'user_agent': 'Custom agent', 'capture_duration': '45', 'play_selector': '.play-button',
    });
    controller.job.status = 'Failed';
    controller.clearCompletedDownload();
    expect(controller.tecUrl.text, 'https://example.com/video');
    expect(controller.tecFilename.text, 'movie.mp4');
    controller.job.status = 'Completed';
    controller.job.outputPath = '/tmp/videos/movie.mp4';
    controller.job.progressText = 'Downloading: 100%';
    controller.job.logs.add('Finished');
    controller.clearCompletedDownload();
    expect(controller.tecUrl.text, '');
    expect(controller.tecFilename.text, '');
    expect(controller.job.status, 'Ready');
    expect(controller.job.logs, isEmpty);
    expect(controller.job.outputPath, '');
    expect(controller.downloadStdout.value, '');
    expect(controller.requestFromForm().concurrency, 12);
    expect(controller.tecDirectory.text, '/tmp/videos');
    await Get.delete<PageDownloadController>();
    final restored = Get.put<PageDownloadController>(_Controller());
    final request = restored.requestFromForm();
    expect(request.mode, 'hls');
    expect(request.directory, '/tmp/videos');
    expect(request.concurrency, 12);
    expect(request.retries, 5);
    expect(request.timeout, 60);
    expect(request.referer, 'https://example.com/');
    expect(request.userAgent, 'Custom agent');
    expect(request.captureDuration, 45);
    expect(request.playSelector, '.play-button');
    expect(request.headless, isTrue);
    expect(request.allowPopups, isTrue);
    expect(restored.tecUrl.text, '');
    expect(restored.tecFilename.text, '');
    expect(restored.job.running, isFalse);
    restored.tecRetries.text = '7';
    await Get.delete<PageDownloadController>();
    expect(AppPref.getDownloadOptions()['retries'], '7');
  });

  testWidgets('Website button starts extraction and preserves an active download', (tester) async {
    final controller = Get.put<PageDownloadController>(_DownloadController()) as _DownloadController;
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: PageDownloadView())));
    await tester.pumpAndSettle();
    controller.mode.value = 'file';
    controller.tecReferer.text = 'https://old.example.com/';
    controller.tecFilename.text = 'old.mp4';
    controller.headless.value = true;
    controller.downloadWebsite('https://example.com/video');
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(controller.starts, 1);
    expect(controller.requestFromForm().url, 'https://example.com/video');
    expect(controller.mode.value, 'extract');
    expect(controller.headless.value, isTrue);
    expect(controller.tecReferer.text, 'https://old.example.com/');
    expect(controller.tecFilename.text, '');
    controller.job.running = true;
    controller.downloadWebsite('https://example.com/other');
    await tester.pump();
    expect(controller.starts, 1);
    expect(controller.tecUrl.text, 'https://example.com/video');
    expect(controller.formError.value, contains('already active'));
    expect(find.byType(Dialog), findsOneWidget);
    controller.job.running = false;
    await tester.tap(find.byTooltip('Close download dialog'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Download opens a compact dialog, keeps drafts and continues when closed', (tester) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = Get.put<PageDownloadController>(_Controller());
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: PageDownloadView())));
    await tester.pumpAndSettle();
    expect(find.byTooltip('New search tab'), findsOneWidget);
    expect(find.text('Catalog'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byTooltip('New download'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Capture'), findsOneWidget);
    final dialogBody = find.byWidgetPredicate((widget) => widget is ConstrainedBox && widget.constraints.maxWidth == 460);
    expect(tester.getSize(dialogBody).height, lessThan(360));
    controller.tecUrl.text = 'https://example.com/watch';
    controller.tecFilename.text = 'My movie.mp4';
    await controller.openDialogDownload();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Workers (1–64)'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close download dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byTooltip('New download'));
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/watch'), findsOneWidget);
    expect(find.text('My movie.mp4'), findsOneWidget);
    controller.job.running = true;
    controller.job.acceptLine('[1] [HLS] https://cdn.example.com/video/master.m3u8');
    controller.job.acceptLine('[2] [DASH (unsupported)] https://cdn.example.com/video/manifest.mpd');
    await tester.pump();
    expect(find.text('[1] HLS'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Download this media')).onPressed, isNotNull);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Unsupported stream')).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close download dialog'));
    await tester.pumpAndSettle();
    expect(controller.job.running, isTrue);
    expect(controller.job.cancelled, isFalse);
    controller.job.running = false;
    await tester.tap(find.byTooltip('Download history'));
    await tester.pumpAndSettle();
    expect(find.text('Downloads'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byTooltip('New download')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('My movie.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close download dialog'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Download tab controls preserve drafts and keep one tab without touching download state', (tester) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put(AppSettingService());
    final controller = Get.put(PageDownloadController());
    addTearDown(Get.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PageDownloadView())));
    await tester.pumpAndSettle();
    expect(controller.activeTab.fnSearch.hasFocus, isFalse);
    final first = controller.activeTab;
    await tester.enterText(find.byType(CupertinoTextField), 'First draft');
    first.filter.tecActressName.text = 'First actress';
    controller.downloadStdout.value = 'Download running';
    await tester.tap(find.byTooltip('New search tab'));
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 2);
    final addButton = findHugeIconButton(HugeIcons.strokeRoundedAdd01).first;
    final lastClose = findHugeIconButton(HugeIcons.strokeRoundedCancel01).last;
    expect(tester.getTopLeft(addButton).dx - tester.getTopRight(lastClose).dx, closeTo(4, 1));
    final second = controller.activeTab;
    expect(second.fnSearch.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 3);
    expect(controller.activeTab.fnSearch.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 2);
    expect(controller.activeTab, same(second));
    expect(second.tecSearch.text, '');
    expect(second.filter.tecActressName.text, '');
    await tester.enterText(find.byType(CupertinoTextField), 'Second draft');
    controller.selectTab(0);
    await tester.pumpAndSettle();
    expect(find.text('First draft'), findsOneWidget);
    expect(first.filter.tecActressName.text, 'First actress');
    controller.closeTab(0);
    await tester.pumpAndSettle();
    expect(first.isClosed, isTrue);
    expect(controller.activeTab, same(second));
    expect(find.text('Second draft'), findsOneWidget);
    await tester.tap(find.byTooltip('Close tab'));
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 1);
    expect(controller.activeTab.tecSearch.text, '');
    expect(controller.downloadStdout.value, 'Download running');
    for (var i = 0; i < 6; i++) {
      controller.addTab();
    }
    await tester.pumpAndSettle();
    expect(controller.tabScrollController.offset, greaterThan(0));
    expect(addButton.hitTestable(), findsOneWidget);
    final selected = controller.activeTab;
    controller.closeTab(1);
    await tester.pumpAndSettle();
    expect(controller.activeTab, same(selected));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Download tabs retain independent scroll and pagination uses submitted filters', (tester) async {
    final first = _SearchTab(1);
    final second = _SearchTab(2);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final active = ValueNotifier<PageDownloadSearchTab>(first);
    addTearDown(active.dispose);
    for (final tab in [first, second]) {
      tab.videos.assignAll(List.generate(100, (i) => JavitSearchResult(videoCode: 'SSIS-$i')));
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<PageDownloadSearchTab>(
      valueListenable: active,
      builder: (context, tab, child) => _SearchView(key: ValueKey(tab.id), controller: tab),
    ))));
    await tester.pumpAndSettle();
    first.scrollController.jumpTo(800);
    await tester.pumpAndSettle();
    active.value = second;
    await tester.pumpAndSettle();
    expect(second.scrollController.offset, 0);
    second.scrollController.jumpTo(400);
    await tester.pumpAndSettle();
    active.value = first;
    await tester.pumpAndSettle();
    expect(first.scrollController.offset, 800);

    first.filter.categoriesSelected.assignAll(['Drama']);
    final search = first.onSearch('/new-release');
    await tester.pump();
    first.pending[0].complete(result('SSIS-001', total: 2));
    await search;
    first.filter.categoriesSelected.assignAll(['Unsubmitted category']);
    await tester.pumpAndSettle();
    expect(first.pages, [1, 2]);
    first.showHavingOnly(true);
    first.pending[1].complete(result('SSIS-002', total: 2));
    await tester.pumpAndSettle();
    expect(first.videos.map((item) => item.videoCode), ['SSIS-001']);
    expect(first.havingVideos.value, 1);
    first.showHavingOnly(false);
    await tester.pumpAndSettle();
    expect(first.videos.map((item) => item.videoCode), ['SSIS-001', 'SSIS-002']);
    expect(first.currentPage.value, 2);
    expect(first.scrollController.offset, 0);
    expect(second.videos.length, 100);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
