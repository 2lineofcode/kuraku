import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_chat.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/page_chat/page_chat_controller.dart';
import 'package:kuraku/app/modules/home/page_chat/page_chat_view.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_controller.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_search_tab.dart';
import 'package:kuraku/app/utils/chat_knowledge.dart';
import 'package:kuraku/app/utils/chat_service.dart';

import 'chat_test_database.dart';

class _Knowledge extends ChatKnowledge {
  _Knowledge() : super(mainPath: '/fixture/kuraku.db');
  int requests = 0;
  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> query, CancelToken token) async {
    requests++;
    final offset = query['offset'] as int? ?? 0;
    final count = offset == 0 ? 500 : 100;
    return {
      'columns': ['code', 'title', 'release_date', 'source_url'],
      'rows': [for (var i = 100 + offset; i < 100 + offset + count; i++) ['TEST-$i', 'Video $i', '2026-01-01', 'https://example.com/$i']],
      if (query['operation'] == 'search_titles') 'search_terms': ['rain'],
      'page_offset': offset, 'has_more': offset == 0,
      'covers': {}, 'sources': ['fixture.db'], 'elapsed_ms': 1, 'truncated': false,
    };
  }
}

class _Tab extends PageDownloadSearchTab {
  _Tab(super.id);
  @override
  Future<Set<String>> loadExistingVideoCodes() async => {'TEST-100'};
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Database batches advance by 500 and keep their snapshot on save failure', () async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final controller = Get.put(PageChatController(api: ChatService(knowledge: _Knowledge())));
    await controller.reload();
    controller.input.text = 'show my favorites';
    await controller.send();
    final message = controller.messages.last;
    message.titleSearch = {'operation': 'search_titles', 'terms': ['rain'], 'source': 'r18', 'limit': 500, 'offset': 0, 'has_more': true};
    await DBChat.saveAssistant(message);
    await controller.loadTitleSearchPage(message, 1);
    expect(message.titleSearch?['offset'], 500);
    expect(message.downloadRows, hasLength(100));
    expect(message.downloadRows.first['video_code'], 'TEST-600');
    expect(message.content, contains('Rows 501–600'));
    database.failWrites = true;
    await controller.loadTitleSearchPage(message, -1);
    expect(message.titleSearch?['offset'], 500);
    expect(message.downloadRows, hasLength(100));
    database.failWrites = false;
    await controller.reload();
    expect(controller.messages.last.downloadRows, hasLength(100));
    await controller.loadTitleSearchPage(controller.messages.last, -1);
    expect(controller.messages.last.titleSearch?['offset'], 0);
    expect(controller.messages.last.downloadRows, hasLength(500));
  });

  test('Opening results keeps the chat when saving its draft fails and can retry', () async {
    addTearDown(Get.reset);
    Get.testMode = true;
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final home = Get.put<HomeController>(_Home())..currentMenuSelected.value = kMenuChat;
    final download = Get.put<PageDownloadController>(_Download());
    final controller = Get.put(PageChatController(api: ChatService(knowledge: _Knowledge())));
    await controller.reload();
    controller.input.text = 'show my favorites';
    await controller.send();
    final message = controller.messages.last;
    controller.input.text = 'Keep my unsaved draft';
    database.failWrites = true;
    await controller.openResultsInDownload(message);
    expect(home.currentMenuSelected.value, kMenuChat);
    expect(download.tabs, hasLength(1));
    expect(controller.busy.value, isFalse);
    expect(controller.error.value, isNotEmpty);
    database.failWrites = false;
    await controller.openResultsInDownload(message);
    expect(home.currentMenuSelected.value, kMenuDownload);
    expect(download.activeTab.videos, hasLength(500));
    expect((await DBChat.getConversations()).single.draft, 'Keep my unsaved draft');
  });

  testWidgets('Chat keeps 500 results after reload and opens the exact snapshot in Download', (tester) async {
    addTearDown(Get.reset);
    Get.testMode = true;
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final home = Get.put<HomeController>(_Home())..currentMenuSelected.value = kMenuChat;
    final download = Get.put<PageDownloadController>(_Download());
    final original = download.activeTab;
    original.tecSearch.text = 'Keep this draft';
    final knowledge = _Knowledge();
    final controller = Get.put(PageChatController(api: ChatService(knowledge: knowledge)));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    controller.input.text = 'show my favorites';
    await controller.send();
    await controller.reload();
    await tester.pumpAndSettle();
    final message = controller.messages.last;
    expect(message.downloadRows, hasLength(500));
    expect(find.text('1–25 of 500 · Page 1/20'), findsOneWidget);
    final next = find.byTooltip('Next results');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('26–50 of 500 · Page 2/20'), findsOneWidget);
    final open = find.byTooltip('Open results in Download');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    controller.input.text = 'Unsent chat draft';
    await tester.tap(open);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(home.currentMenuSelected.value, kMenuDownload);
    expect(controller.busy.value, isFalse);
    expect((await DBChat.getConversations()).single.draft, 'Unsent chat draft');
    expect(download.tabs, hasLength(2));
    expect(original.tecSearch.text, 'Keep this draft');
    final tab = download.activeTab;
    expect(tab.videos, hasLength(500));
    expect(tab.videos.first.videoCode, 'TEST-100');
    expect(tab.videos.last.videoCode, 'TEST-599');
    expect(tab.videos.first.sourceUrl, 'https://example.com/100');
    expect(tab.havingVideos.value, 1);
    expect(knowledge.requests, 1);
    final restored = _Tab(999)..restorePreferences(tab.toPreferences());
    addTearDown(restored.dispose);
    await restored.restoreSearch();
    expect(restored.videos, hasLength(500));
    await DBChat.resetAssistant(message, provider: 'local', model: null);
    expect(message.downloadRows, isEmpty);
    expect((await DBChat.getMessages(message.conversationId)).last.downloadRows, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
