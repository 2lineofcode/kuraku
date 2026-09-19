import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_pref.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/page_search/page_search_controller.dart';
import 'package:javit/app/modules/home/page_search/page_search_tab.dart';
import 'package:javit/app/modules/home/page_search/page_search_view.dart';
import 'package:javit/app/utils/semantic_search_service.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedTab extends PageSearchTab {
  _DelayedTab(super.id);
  final local = <Completer<List<Videos>>>[];
  final semantic = <Completer<List<SemanticSearchHit>>>[];

  @override
  Future<List<Videos>> loadVideos(String query) {
    final pending = Completer<List<Videos>>();
    local.add(pending);
    return pending.future;
  }

  @override
  Future<List<SemanticSearchHit>> loadSemanticResults(String query) {
    final pending = Completer<List<SemanticSearchHit>>();
    semantic.add(pending);
    return pending.future;
  }
}

class _ReadyTab extends PageSearchTab {
  _ReadyTab(super.id);

  @override
  Future<List<String>> loadHistory(String query) async => [];

  @override
  Future<void> onRefresh() async {
    await super.onRefresh();
    isFresh.value = false;
  }

  @override
  Future<List<Videos>> loadVideos(String query) async => [];

  @override
  Future<List<SemanticSearchHit>> loadSemanticResults(String query) async => [];
}

class _HistoryTab extends _ReadyTab {
  _HistoryTab(super.id);
  final history = ['Alpha', 'Beta'];
  final saved = <String>[];
  Completer<List<String>>? pendingHistory;
  @override
  Future<List<String>> loadHistory(String query) async => pendingHistory?.future ?? history.where((item) => item.toLowerCase().contains(query.trim().toLowerCase())).toList();
  @override
  Future<void> saveHistory(String query) async { saved.add(query); }
  @override
  Future<void> deleteHistory(String query) async { history.remove(query); }
  @override
  Future<void> clearHistory() async { history.clear(); }
  @override
  Future<List<Videos>> loadVideos(String query) async => [Videos(id: '1', title: query)];
}

class _Controller extends PageSearchController {
  @override
  PageSearchTab createTab(int id) => _ReadyTab(id);
}

class _SearchView extends PageSearchTabView {
  const _SearchView({super.key, required super.controller});

  @override
  Widget buildLayoutPoster(Videos video, double width, double height, {
    bool isFanArt = false, bool interactive = true,
    showReleaseDate = true, showViewCount = true, showQuality = true,
  }) => Text(video.title ?? 'Video');
}

void main() {
  final preferences = _Preferences();
  setUp(() {
    preferences.values.clear();
    Get.put(AppSettingService()..pref = preferences);
  });
  tearDown(Get.reset);

  testWidgets('Search history supports selection, deletion, confirmation and preserves drafts', (tester) async {
    final tab = _HistoryTab(0)..isFresh.value = false;
    addTearDown(tab.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SearchView(controller: tab))));
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), '   ');
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), 'al');
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, ['Alpha']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tab.tecSearch.text, 'Alpha');
    expect(tab.videos.single.title, 'Alpha');
    expect(tab.saved, ['Alpha']);
    expect(tab.historySuggestions, isEmpty);
    await tab.onRefresh();
    expect(tab.saved, ['Alpha']);

    await tester.enterText(find.byType(CupertinoTextField), '');
    await tester.pumpAndSettle();
    expect(tab.historySuggestions, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), 'a');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove from history').first);
    await tester.pumpAndSettle();
    expect(tab.history, ['Beta']);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(tab.saved, ['Alpha', 'Beta']);
    expect(tab.tecSearch.selection, const TextSelection.collapsed(offset: 4));

    await tester.enterText(find.byType(CupertinoTextField), 'be');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(tab.history, ['Beta']);
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(tab.history, isEmpty);
    expect(tab.historySuggestions, isEmpty);
    expect(tab.tecSearch.text, 'be');
    expect(tab.fnSearch.hasFocus, isTrue);

    tab.isSemanticMode.value = true;
    await tester.enterText(find.byType(CupertinoTextField), 'AI query');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tab.saved.last, 'AI query');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Search ignores stale history responses after editing, dismissing and closing', (tester) async {
    final tab = _HistoryTab(0)..isFresh.value = false;
    addTearDown(tab.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SearchView(controller: tab))));
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tab.historySuggestions, isEmpty);
    final pending = Completer<List<String>>();
    tab.pendingHistory = pending;
    await tester.enterText(find.byType(CupertinoTextField), 'old');
    tab.pendingHistory = null;
    await tester.enterText(find.byType(CupertinoTextField), 'be');
    await tester.pumpAndSettle();
    pending.complete(['stale']);
    await tester.pump();
    expect(tab.historySuggestions, ['Beta']);
    tab.pendingHistory = Completer<List<String>>();
    await tester.enterText(find.byType(CupertinoTextField), 'closed');
    tab.close();
    tab.pendingHistory!.complete(['closed']);
    await tester.pump();
    expect(tab.historySuggestions, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Search tabs restore preferences, active tab and drafts after controller recreation', (tester) async {
    final controller = Get.put<PageSearchController>(_Controller());
    final first = controller.activeTab;
    first.tecSearch.text = 'Saved query';
    first.isListView.value = true;
    first.isSemanticMode.value = true;
    first.filter.tecVideoCode.text = 'SSIS';
    first.filter.tecActressName.text = 'Alice';
    first.filter.tecCategory.text = 'Draft category';
    first.filter.categoriesSelected.assignAll(['Drama', 'Romance']);
    first.filter.currentRange.value = RangeValues(2022, 2025);
    first.filter.isFiltered.value = true;
    await first.onSortByChange('File Size');
    controller.addTab();
    controller.activeTab.tecSearch.text = 'Unsubmitted draft';
    await tester.pump(Duration(milliseconds: 300));
    expect((AppPref.getSearchTabs()['tabs'] as List).length, 2);
    expect(AppPref.getSearchTabs()['activeTab'], 1);
    final saved = jsonDecode(jsonEncode(AppPref.getSearchTabs())) as Map<String, dynamic>;
    await Get.delete<PageSearchController>();
    await AppPref.setSearchTabs(saved);
    final restored = Get.put<PageSearchController>(_Controller());
    await tester.pump();
    expect(restored.tabs.length, 2);
    expect(restored.activeTabIndex.value, 1);
    expect(restored.activeTab.tecSearch.text, 'Unsubmitted draft');
    final recovered = restored.tabs.first;
    expect(recovered.toPreferences(), first.toPreferences());
    expect(recovered.phSearch.value, startsWith('Local AI Search'));
    final beforeRefresh = jsonDecode(jsonEncode(AppPref.getSearchTabs()));
    await restored.onRefresh();
    expect(AppPref.getSearchTabs(), beforeRefresh);
    expect(restored.tabs.first.title.value, 'Saved query');
    expect(restored.activeTabIndex.value, 1);
    expect(restored.activeTab.tecSearch.text, 'Unsubmitted draft');
    restored.closeTab(1);
    await tester.pump(Duration(milliseconds: 300));
    expect((AppPref.getSearchTabs()['tabs'] as List).length, 1);
    expect(AppPref.getSearchTabs()['activeTab'], 0);
    await Get.delete<PageSearchController>();

    await AppPref.setSearchTabs({'tabs': [null, {'query': 12, 'yearStart': 3000, 'yearEnd': 1000}], 'activeTab': 99});
    final invalid = Get.put<PageSearchController>(_Controller());
    await tester.pump();
    expect(invalid.tabs.length, 1);
    expect(invalid.activeTabIndex.value, 0);
    expect(invalid.activeTab.tecSearch.text, '');
    expect(invalid.activeTab.filter.currentRange.value.start, 2000);
    await Get.delete<PageSearchController>();
    await tester.pump();
  });

  testWidgets('Search switches grid and list per tab without changing results or query', (tester) async {
    final first = PageSearchTab(1);
    final second = PageSearchTab(2);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final videos = List.generate(20, (i) => Videos(id: '$i', videoCode: 'TEST-$i', title: 'Video $i'));
    first.showResults('Test query', videos);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SearchView(controller: first))));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    first.scrollGridController.jumpTo(300);
    await tester.tap(find.byTooltip('Switch to list view'));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(first.scrollGridController.offset, 0);
    expect(first.videos, videos);
    expect(first.tecSearch.text, 'Test query');
    expect(second.isListView.value, isFalse);
    expect(find.text('TEST-0'), findsOneWidget);
    await tester.tap(find.byTooltip('Switch to grid view'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(first.videos, videos);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Search tabs isolate local and AI results and reject stale or closed requests', (tester) async {
    final first = _DelayedTab(1);
    final second = _DelayedTab(2);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.tecSearch.text = 'Local';
    second.tecSearch.text = 'Semantic';
    second.isSemanticMode.value = true;
    final a = first.onSearch();
    final b = second.onSearch();
    second.semantic[0].complete([SemanticSearchHit(video: Videos(id: 'ai'), score: .9)]);
    await b;
    expect(second.videos.single.id, 'ai');
    expect(second.semanticScoreByVideoId['ai'], .9);
    expect(first.videos, isEmpty);
    expect(first.isLoading.value, isTrue);
    first.local[0].complete([Videos(id: 'local')]);
    await a;
    expect(first.videos.single.id, 'local');
    expect(first.semanticScoreByVideoId, isEmpty);

    final older = first.onSearch();
    first.tecSearch.text = 'Latest';
    final newer = first.onSearch();
    first.local[2].complete([Videos(id: 'latest')]);
    await newer;
    first.local[1].complete([Videos(id: 'stale')]);
    await older;
    expect(first.videos.single.id, 'latest');
    expect(first.title.value, 'Latest');

    final staleAi = second.onSearch();
    final localMode = second.toggleSemanticMode();
    second.local[0].complete([Videos(id: 'normal')]);
    await localMode;
    second.semantic[1].completeError(StateError('Old AI request failed'));
    await staleAi;
    expect(second.videos.single.id, 'normal');
    expect(second.semanticScoreByVideoId, isEmpty);
    expect(second.error.value, '');
    expect(second.isSemanticBusy.value, isFalse);

    final closing = first.onSearch();
    first.close();
    first.local[3].complete([Videos(id: 'closed')]);
    await closing;
    expect(first.videos, isEmpty);
  });

  testWidgets('Search filters and sorting stay local and top search supersedes initial loading', (tester) async {
    final tab = _DelayedTab(1);
    addTearDown(tab.dispose);
    final initial = tab.onRefresh();
    final small = Videos(id: 'small', videoCode: 'SSIS-001', filesize: 100, releaseDate: '2024-01-01');
    final large = Videos(id: 'large', videoCode: 'SSIS-002', filesize: 200, releaseDate: '2024-01-01');
    tab.showResults('Top search', [small, large]);
    tab.local[0].complete([Videos(id: 'old library')]);
    await initial;
    expect(tab.videos.map((item) => item.id), ['small', 'large']);
    expect(tab.title.value, 'Top search');
    await tab.onSortByChange('File Size');
    expect(tab.videos.map((item) => item.id), ['large', 'small']);
    tab.filter.tecVideoCode.text = 'SSIS-001';
    tab.filter.isFiltered.value = true;
    await tab.onSortByChange('File Size');
    expect(tab.videos.single.id, 'small');
    expect(tab.allVideos.length, 2);
    tab.filter.reset();
    await tab.onSortByChange('File Size');
    expect(tab.videos.map((item) => item.id), ['large', 'small']);
    final failing = tab.onSearch();
    tab.local[1].completeError(StateError('Search failed'));
    await failing;
    expect(tab.error.value, isNotEmpty);
    expect(tab.isLoading.value, isFalse);
  });

  testWidgets('Search tab controls preserve independent settings and keep the plus beside the last tab', (tester) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = Get.put<PageSearchController>(_Controller());
    addTearDown(Get.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PageSearchView())));
    await tester.pumpAndSettle();
    final first = controller.activeTab;
    await tester.enterText(find.byType(CupertinoTextField), 'First draft');
    first.filter.tecActressName.text = 'Actress';
    first.sortBy.value = 'File Size';
    first.isSemanticMode.value = true;
    await tester.tap(find.byTooltip('New search tab'));
    await tester.pumpAndSettle();
    final second = controller.activeTab;
    expect(second.tecSearch.text, '');
    expect(second.filter.tecActressName.text, '');
    expect(second.sortBy.value, 'Random');
    expect(second.isSemanticMode.value, isFalse);
    final plus = find.widgetWithIcon(IconButton, Icons.add);
    final lastClose = find.widgetWithIcon(IconButton, Icons.close).last;
    expect(tester.getTopLeft(plus).dx - tester.getTopRight(lastClose).dx, closeTo(4, 1));
    await tester.enterText(find.byType(CupertinoTextField), 'Second draft');
    controller.selectTab(0);
    await tester.pumpAndSettle();
    expect(find.text('First draft'), findsOneWidget);
    expect(first.sortBy.value, 'File Size');
    expect(first.isSemanticMode.value, isTrue);
    controller.closeTab(0);
    await tester.pumpAndSettle();
    expect(first.isClosed, isTrue);
    expect(controller.activeTab, same(second));
    expect(find.text('Second draft'), findsOneWidget);
    controller.closeTab(0);
    await tester.pumpAndSettle();
    expect(controller.tabs.length, 1);
    expect(controller.activeTab.tecSearch.text, '');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Search tabs restore independent scroll positions', (tester) async {
    final first = PageSearchTab(1);
    final second = PageSearchTab(2);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    for (final tab in [first, second]) {
      tab.showResults('Results', List.generate(100, (i) => Videos(id: '$i', title: 'Video $i')));
    }
    final active = ValueNotifier(first);
    addTearDown(active.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<PageSearchTab>(
      valueListenable: active,
      builder: (context, tab, child) => _SearchView(key: ValueKey(tab.id), controller: tab),
    ))));
    await tester.pumpAndSettle();
    first.scrollGridController.jumpTo(800);
    await tester.pumpAndSettle();
    active.value = second;
    await tester.pumpAndSettle();
    expect(second.scrollGridController.offset, 0);
    second.scrollGridController.jumpTo(400);
    await tester.pumpAndSettle();
    active.value = first;
    await tester.pumpAndSettle();
    expect(first.scrollGridController.offset, 800);
    active.value = second;
    await tester.pumpAndSettle();
    expect(second.scrollGridController.offset, 400);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
