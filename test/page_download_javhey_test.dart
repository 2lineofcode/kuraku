import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/models/__javit_search_entity.dart';
import 'package:javit/app/data/models/__javmost_new_release.dart';
import 'package:javit/app/modules/home/page_download/page_download_controller.dart';
import 'package:javit/app/modules/home/page_download/page_download_search_tab.dart';
import 'package:javit/app/modules/home/page_download/page_download_view.dart';
import 'package:javit/app/modules/widgets/widget_thumbnail.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

import 'chat_test_database.dart';
import 'icon_finder.dart';

class _Tab extends PageDownloadSearchTab {
  _Tab(super.id);
  final requests = <({String query, int page})>[];
  final pending = <Completer<JavitSearch>>[];
  int javMostRequests = 0;
  @override
  Future<JavitSearch> fetchJavHey(String query, int page) {
    requests.add((query: query, page: page));
    final response = Completer<JavitSearch>();
    pending.add(response);
    return response.future;
  }
  @override
  Future<JavMostModel> fetchJavMostByCommand(String command, int page) async {
    javMostRequests++;
    return JavMostModel(success: true, total: 0, result: []);
  }
  @override
  Future<Set<String>> loadExistingVideoCodes() async => {'ABC-001'};
  @override
  Future<void> saveHistory(String query) async {}
}

class _Controller extends PageDownloadController {
  String? requestedUrl;
  @override
  Future<void> loadDownloadHistory() async {}
  @override
  void downloadWebsite(String url) { requestedUrl = url; }
}

JavitSearch result(String code, {bool hasNext = false, int? total = 100}) => JavitSearch(
  total: total, hasNextPage: hasNext,
  result: [JavitSearchResult(videoId: code, videoCode: code, title: 'Sub Indo $code', fanArt: '',
    sourceUrl: 'https://javhey.com/video/100/${code.toLowerCase()}/',
    releaseDate: '2024-01-02', duration: 120, categories: ['Drama', 'Solowork'], actresses: ['Actor A'])],
);

void main() {
  setUp(() { Get.put(AppSettingService()..pref = ChatTestPreferences()); });
  tearDown(Get.reset);

  testWidgets('JavHey command loads the provider, preserves source and skips filtered pages using API pagination', (tester) async {
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    tab.filter.tecVideoCode.text = 'ABC';
    final search = tab.onSearch('/javhey Subtitle title');
    expect(tab.requests.single, (query: '/javhey Subtitle title', page: 1));
    tab.pending.single.complete(result('DEF-001', hasNext: true));
    await search;
    expect(tab.videos, isEmpty);
    expect(tab.hasNextPage.value, isTrue);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(
      controller: tab.scrollController, children: const [Text('Results')],
    ))));
    tab.onViewportMetricsChanged();
    await tester.pump();
    expect(tab.requests.last.page, 2);
    tab.pending.last.complete(result('ABC-001'));
    await tester.pumpAndSettle();
    expect(tab.currentPage.value, 2);
    expect(tab.hasNextPage.value, isFalse);
    expect(tab.totalResults.value, 100);
    expect(tab.videos.single.sourceUrl, 'https://javhey.com/video/100/abc-001/');
    expect(tab.videos.single.match, isTrue);
    expect(tab.videos.single.categories, ['Drama', 'Solowork']);
    expect(tab.javMostRequests, 0);
    expect(tab.error.value, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late responses cannot replace a newer JavHey query and errors reset loading', (tester) async {
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    final first = tab.onSearch('/javhey first');
    final second = tab.onSearch('/JAVHEY second');
    tab.pending[1].complete(result('ABC-002'));
    await second;
    tab.pending[0].complete(result('ABC-001'));
    await first;
    expect(tab.videos.single.videoCode, 'ABC-002');
    final failed = tab.onSearch('/javhey third');
    tab.pending.last.completeError(StateError('Unavailable'));
    await failed;
    expect(tab.error.value, isNotEmpty);
    expect(tab.isLoading.value, isFalse);
    expect(tab.hasNextPage.value, isFalse);
    final browse = tab.onPickSearchCommand('/javhey');
    expect(tab.requests.last.query, '/javhey');
    tab.pending.last.complete(result('ABC-003', total: null));
    await browse;
    expect(tab.videos.single.videoCode, 'ABC-003');
    expect(tab.totalResults.value, 1);
    expect(tab.javMostRequests, 0);
  });

  testWidgets('saved JavSek queries migrate to JavHey without using the old provider', (tester) async {
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    tab.restorePreferences({'query': '/javsek ABC-001'});
    expect(tab.tecSearch.text, '/javhey ABC-001');
    final restored = tab.restoreSearch();
    expect(tab.requests.single.query, '/javhey ABC-001');
    tab.pending.single.complete(result('ABC-001'));
    await restored;
    final history = tab.onSearch('/JAVSEK ABC-002');
    expect(tab.tecSearch.text, '/javhey ABC-002');
    expect(tab.requests.last.query, '/javhey ABC-002');
    tab.pending.last.complete(result('ABC-002'));
    await history;
    expect(tab.javMostRequests, 0);
  });

  testWidgets('JavHey thumbnail Download uses the actual article link', (tester) async {
    final controller = Get.put<PageDownloadController>(_Controller()) as _Controller;
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    final item = result('ABC-001').result!.single;
    tab.videos.add(item);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageDownloadSearchView(controller: tab))));
    await tester.pumpAndSettle();
    final thumbnail = tester.widget<ExThumbnail>(find.byType(ExThumbnail));
    expect(thumbnail.onDownload, isNotNull);
    final notifier = ValueNotifier<scm.MenuResult?>(null);
    addTearDown(notifier.dispose);
    final request = scm.MenuRequest(onShowMenu: notifier, onHideMenu: notifier, onPreviewAction: notifier, location: Offset.zero);
    final menu = await tester.widgetList<scm.ContextMenuWidget>(find.byType(scm.ContextMenuWidget)).single.menuProvider(request);
    menu!.children.whereType<scm.MenuAction>().firstWhere((action) => action.title == 'Download').callback();
    await tester.pump();
    expect(controller.requestedUrl, item.sourceUrl);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing JavHey release dates stay empty after loading', (tester) async {
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    final search = tab.onSearch('/javhey');
    final response = result('ABC-001');
    response.result!.single.releaseDate = null;
    tab.pending.single.complete(response);
    await search;
    expect(tab.videos.single.releaseDate, isEmpty);
  });

  testWidgets('release badge uses the date field and hides missing or invalid dates', (tester) async {
    Get.put<PageDownloadController>(_Controller());
    final tab = _Tab(1);
    addTearDown(tab.dispose);
    for (final date in <String?>[null, '', 'null', 'invalid', '2024-02-30', '2024-01-02']) {
      final item = result('ABC-001').result!.single;
      item.releaseDate = date;
      item.durationFormated = '2 hrs';
      tab.videos.assignAll([item]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PageDownloadSearchView(controller: tab))));
      await tester.pumpAndSettle();
      expect(findHugeIcon(HugeIcons.strokeRoundedCalendar03), date == '2024-01-02' ? findsOneWidget : findsNothing);
      if (date == '2024-01-02') expect(find.text('Jan 02, 2024'), findsOneWidget);
      expect(find.text('error'), findsNothing);
      expect(find.text('null'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
