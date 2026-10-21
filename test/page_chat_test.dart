import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_chat.dart';
import 'package:kuraku/app/data/models/chat_entity.dart';
import 'package:kuraku/app/modules/home/page_chat/page_chat_controller.dart';
import 'package:kuraku/app/modules/home/page_chat/page_chat_view.dart';
import 'package:kuraku/app/modules/widgets/widget_thumbnail.dart';
import 'package:kuraku/app/utils/chat_knowledge.dart';
import 'package:kuraku/app/utils/chat_service.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'chat_test_database.dart';

import 'icon_finder.dart';

class _ChatApi extends ChatService {
  _ChatApi({String apiKey = 'test-key', super.knowledge}) : super(apiKey: apiKey);
  int translations = 0;
  bool translationFails = false;
  @override
  Future<String> translateTitle(String title, CancelToken token) async {
    translations++;
    if (translationFails) throw const ChatException('Translation unavailable.');
    return 'Berjalan di tengah hujan';
  }
  Completer<void>? wait;
  bool cancelWait = false;
  final requests = <List<Map<String, String>>>[];
  @override
  Stream<String> reply(List<Map<String, String>> messages, CancelToken cancelToken) async* {
    requests.add(messages);
    onActivity?.call('Checking your library');
    if (wait != null) {
      if (cancelWait) { await Future.any([wait!.future, cancelToken.whenCancel]); }
      else { await wait!.future; }
    }
    yield 'Test answer';
  }
}

class _PagedKnowledge extends ChatKnowledge {
  _PagedKnowledge() : super(mainPath: '/fixture/kuraku.db');
  final offsets = <int>[];
  final queries = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> query, CancelToken token) async {
    final offset = query['offset'] as int? ?? 0;
    offsets.add(offset);
    queries.add(Map.of(query));
    return {
      'columns': ['code', 'title'],
      'rows': List.generate(offset >= 50 ? 4 : 25, (i) => ['TEST-${offset + i + 1}', 'Sample title']),
      'page_offset': offset, 'search_terms': ['rain', '雨'], 'has_more': offset < 50,
      'sources': ['fixture.db'], 'elapsed_ms': 1, 'truncated': offset < 50,
    };
  }
}

void main() {
  testWidgets('Chat shortcuts manage chats, focus, history and responses without affecting dialogs or other pages', (tester) async {
    addTearDown(Get.reset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi();
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    Future<void> shortcut(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }
    controller.input.text = 'Original question';
    await controller.send();
    final first = controller.activeChat.value;
    controller.input.text = 'Keep my draft';
    await shortcut(LogicalKeyboardKey.keyN);
    expect(controller.activeChat.value, isNot(same(first)));
    expect(controller.chats, hasLength(2));
    await shortcut(LogicalKeyboardKey.keyW);
    expect(controller.activeChat.value, same(first));
    expect(controller.chats, hasLength(1));
    expect(controller.input.text, 'Keep my draft');
    expect(find.text('Delete chat?'), findsNothing);
    database.failWrites = true;
    await shortcut(LogicalKeyboardKey.keyW);
    expect(controller.chats, hasLength(1));
    expect(controller.error.value, isNotEmpty);
    database.failWrites = false;
    await controller.retry();
    await shortcut(LogicalKeyboardKey.keyF);
    expect(controller.searchFocusNode.hasFocus, isTrue);
    await shortcut(LogicalKeyboardKey.keyL);
    expect(controller.focusNode.hasFocus, isTrue);
    await shortcut(LogicalKeyboardKey.keyS, shift: true);
    expect(controller.sidebarVisible.value, isFalse);
    await shortcut(LogicalKeyboardKey.keyF);
    expect(controller.sidebarVisible.value, isTrue);
    expect(controller.searchFocusNode.hasFocus, isTrue);
    await shortcut(LogicalKeyboardKey.keyL);
    await shortcut(LogicalKeyboardKey.keyR, shift: true);
    expect(api.requests, hasLength(2));
    expect(controller.messages, hasLength(2));
    expect(controller.input.text, 'Keep my draft');
    controller.editMessage(controller.messages.first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.editingMessageId.value, isNull);
    expect(controller.focusNode.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Chat shortcuts'));
    await tester.pumpAndSettle();
    await shortcut(LogicalKeyboardKey.keyW);
    expect(controller.chats, hasLength(1));
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    controller.focusNode.requestFocus();
    await shortcut(LogicalKeyboardKey.keyF);
    expect(controller.scaffoldKey.currentState!.isDrawerOpen, isTrue);
    expect(controller.searchFocusNode.hasFocus, isTrue);
    await shortcut(LogicalKeyboardKey.keyL);
    expect(controller.scaffoldKey.currentState!.isDrawerOpen, isFalse);
    expect(controller.focusNode.hasFocus, isTrue);
    api..wait = Completer<void>()..cancelWait = true;
    controller.input.text = 'Stop this response';
    final sending = controller.send();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.respondingChatId.value, first.id);
    await shortcut(LogicalKeyboardKey.period);
    await sending;
    expect(controller.respondingChatId.value, isNull);
    expect(controller.messages.last.status, 'cancelled');
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('Another page'))));
    await tester.pumpAndSettle();
    await shortcut(LogicalKeyboardKey.keyW);
    await shortcut(LogicalKeyboardKey.keyN);
    expect(controller.chats, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat code links open video info for each code alias and preserve the draft', (tester) async {
    addTearDown(Get.reset);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final controller = Get.put(PageChatController(api: _ChatApi()));
    final opened = <dynamic>[];
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageChatView(openVideoInfo: (item) async { opened.add(item); }))));
    await tester.pumpAndSettle();
    final chat = controller.activeChat.value;
    final question = await DBChat.send(chat, 'Show codes');
    final answer = await DBChat.addAssistant(chat, 'test', provider: 'test');
    chat.messages.addAll([question, answer]);
    controller.usePrompt('Keep this draft');
    for (final column in ['code', 'video_code', 'dvd_id']) {
      answer..status = 'completed'..content = ChatKnowledge.render({
        'columns': [column], 'rows': [[' TEST-001 '], [null], [''], [123]],
        'sources': ['fixture'], 'elapsed_ms': 1,
      });
      controller.activeChat.refresh();
      await tester.pumpAndSettle();
      final code = find.textContaining('TEST-001', findRichText: true);
      await tester.ensureVisible(code);
      await tester.tap(code);
      await tester.pump();
      expect(opened.last, {'video_code': 'TEST-001'});
      expect(controller.input.text, 'Keep this draft');
      expect(answer.content.split('kuraku-video:').length - 1, 1);
    }
    answer.content = '| dvd_id | Title |\n| --- | --- |\n| OLD-001 | Legacy title |';
    controller.activeChat.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('OLD-001', findRichText: true));
    await tester.pump();
    expect(opened.last, {'video_code': 'OLD-001'});
    expect(opened, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Background responses link to their chat and long answers can return to the latest messages', (tester) async {
    addTearDown(Get.reset);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi()..wait = Completer<void>();
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    controller.input.text = 'First question';
    final sending = controller.send();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final first = controller.activeChat.value;
    await controller.newChat();
    final background = controller.activeChat.value;
    controller.input.text = 'Background draft';
    await tester.pump();
    expect(find.text('Replying in First question'), findsOneWidget);
    expect(find.byTooltip('Stop response'), findsOneWidget);
    await tester.tap(find.text('View chat'));
    await tester.pump();
    expect(controller.activeChat.value, same(first));
    expect(find.text('Replying in First question'), findsNothing);
    expect(background.draft, 'Background draft');
    api.wait!.complete();
    await sending;
    await tester.pumpAndSettle();
    expect(find.text('Regenerate response'), findsOneWidget);
    await tester.tap(find.text('Regenerate response'));
    await tester.pumpAndSettle();
    expect(controller.messages, hasLength(2));
    expect(api.requests, hasLength(2));
    expect(api.requests.last, [{'role': 'user', 'content': 'First question'}]);
    controller.messages.last.content = List.generate(50, (index) => 'Paragraph $index with enough text to scroll.').join('\n\n');
    controller.activeChat.refresh();
    await tester.pumpAndSettle();
    controller.scrollController.jumpTo(400);
    await tester.pumpAndSettle();
    expect(find.text('Latest messages'), findsOneWidget);
    controller.messages.last.content += '\n\nA new streamed paragraph.';
    controller.activeChat.refresh();
    await tester.pump();
    expect(controller.scrollController.offset, 400);
    await tester.tap(find.text('Latest messages'));
    await tester.pumpAndSettle();
    expect(controller.scrollController.offset, 0);
    expect(find.text('Latest messages'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat images load inline and keep gallery navigation and the draft intact', (tester) async {
    addTearDown(Get.reset);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    final folder = Directory.systemTemp.createTempSync('kuraku-preview-test-');
    addTearDown(() => folder.deleteSync(recursive: true));
    Get.put(AppSettingService()..pref = ChatTestPreferences()..appPath = folder.path);
    final controller = Get.put(PageChatController(api: _ChatApi()));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Show images');
    final answer = await DBChat.addAssistant(chat, 'fixture', provider: 'Saved provider');
    answer..status = 'completed'..content = ChatKnowledge.render({
      'columns': ['code', 'title'], 'rows': [['TEST-001', 'One'], ['TEST-002', 'Missing'], ['TEST-003', 'Three']],
      'covers': {'TEST-001': 'https://example.com/one.jpg', 'TEST-003': 'https://example.com/three.jpg'},
      'sources': ['fixture'], 'elapsed_ms': 1, 'truncated': false,
    });
    answer.content += '\n\n![REMOTE](https://example.com/pixel?data=private)';
    await DBChat.saveAssistant(answer);
    await controller.selectChat(chat);
    controller.usePrompt('Keep my draft');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved provider'), findsOneWidget);
    expect(tester.widgetList<ExThumbnail>(find.byType(ExThumbnail)).map((widget) => widget.imageUrl),
      containsAll(['https://example.com/one.jpg', 'https://example.com/three.jpg', 'https://example.com/pixel?data=private']));
    final cover = find.byTooltip('Preview image').first;
    await tester.ensureVisible(cover);
    await tester.tap(cover);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<ExThumbnail>(find.descendant(of: find.byType(Dialog), matching: find.byType(ExThumbnail))).imageUrl, 'https://example.com/one.jpg');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final dialog = find.byType(Dialog);
    expect(find.descendant(of: dialog, matching: find.text('TEST-001')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.descendant(of: dialog, matching: find.text('TEST-003')), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(tester.widget<ExThumbnail>(find.descendant(of: dialog, matching: find.byType(ExThumbnail))).imageUrl, 'https://example.com/three.jpg');
    await tester.tap(find.descendant(of: dialog, matching: find.text('TEST-003')));
    await tester.pump();
    expect(copied, 'TEST-003');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<ExThumbnail>(find.descendant(of: dialog, matching: find.byType(ExThumbnail))).imageUrl, 'https://example.com/pixel?data=private');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous image (←)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(dialog, findsNothing);
    expect(controller.input.text, 'Keep my draft');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Translate and Similar actions work, retry errors and reuse persisted title translations', (tester) async {
    addTearDown(Get.reset);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi()..translationFails = true;
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Search rain');
    final answer = await DBChat.addAssistant(chat, 'fixture', provider: 'Saved provider');
    answer..status = 'completed'..content = ChatKnowledge.render({
      'columns': ['code', 'title', 'title_ja'], 'rows': [['TEST-001', 'Rainy walk', '雨の散歩']],
      'sources': ['fixture'], 'elapsed_ms': 1, 'truncated': false,
    });
    await DBChat.saveAssistant(answer);
    await controller.selectChat(chat);
    await tester.pumpAndSettle();
    Future<void> tapAction(int start, int end) async {
      final finder = find.byWidgetPredicate((widget) => widget is RichText && widget.text.toPlainText().startsWith('Translate '));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final box = paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end)).first.toRect();
      await tester.tapAt(paragraph.localToGlobal(box.center));
      await tester.pumpAndSettle();
    }
    await tapAction(0, 9);
    expect(find.text('Indonesian translation'), findsOneWidget);
    expect(find.text('Translation unavailable.'), findsOneWidget);
    api.translationFails = false;
    await tester.tap(find.text('Retry translation'));
    await tester.pumpAndSettle();
    expect(find.text('Berjalan di tengah hujan'), findsOneWidget);
    expect(api.translations, 2);
    await tester.tap(find.text('Close'));
    await controller.reload();
    await tester.pumpAndSettle();
    await tapAction(0, 9);
    expect(find.text('Berjalan di tengah hujan'), findsOneWidget);
    expect(api.translations, 2);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tapAction(13, 20);
    expect(controller.input.text, PageChatController.templates['/similar']!.prompt.replaceAll('[CODE]', 'TEST-001'));
    expect(controller.input.text, contains('secondary themes are optional for ranking, not all required'));
    expect(controller.input.text, contains('Preserve all explicitly required themes as AND filters'));
    await controller.send();
    final request = api.requests.single.last['content']!;
    expect(request, contains('Rank strongest contextual matches first by relevance'));
    expect(request, isNot(contains('Sort by newest release date')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('R18 template selects the topic and database pages persist without model calls', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final knowledge = _PagedKnowledge();
    final api = _ChatApi(knowledge: knowledge);
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    for (final entry in PageChatController.templates.entries) {
      final button = find.text(entry.value.label);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(controller.input.text, entry.value.prompt);
      expect(controller.input.selection.textInside(controller.input.text), startsWith('['));
      controller.usePrompt(entry.key);
      await controller.submitInput();
      await tester.pump();
      expect(controller.input.text, entry.value.prompt);
      expect(controller.input.selection.textInside(controller.input.text), startsWith('['));
      expect(controller.messages, isEmpty);
    }
    await tester.ensureVisible(find.text('Search R18 by topic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search R18 by topic'));
    await tester.pump();
    expect(controller.input.selection.textInside(controller.input.text), '[topic]');
    expect(controller.input.text, contains('Include videos with or without English titles'));
    expect(controller.input.text, contains('require missing English metadata only if I explicitly ask'));
    expect(controller.input.text, contains('Rank by relevance unless I request newest releases'));
    expect(controller.input.text, isNot(contains('no English title for the entire video code')));
    expect(controller.input.text, contains('Do not cap the total results'));
    await controller.send();
    expect(controller.messages, isEmpty);
    expect(controller.commandNotice.value, 'Fill in the template fields before sending.');
    controller.useTemplate('/filter');
    await tester.pump();
    expect(controller.input.text, contains('Both themes and every other mandatory filter must match'));
    expect(controller.input.text, contains('OR alternatives within that theme'));
    expect(controller.input.text, contains('Exclude compilations and videos already in my library'));
    expect(controller.input.text, contains('Rank by relevance unless I request newest releases'));
    expect(controller.input.selection.textInside(controller.input.text), '[theme 1]');
    await tester.tap(find.text('Next template field'));
    await tester.pump();
    expect(controller.input.selection.textInside(controller.input.text), '[theme 2]');
    expect(controller.templateFields('Explain [this Markdown link](https://example.com)'), isEmpty);
    expect(controller.templateFields('[topik] and [tema 1]'), hasLength(2));
    controller.input.text = controller.input.text.replaceAll('[theme 1]', 'rain').replaceAll('[theme 2]', 'outdoor');
    expect(controller.templateFields(controller.input.text), isEmpty);
    controller.usePrompt('/r18');
    await controller.send();
    expect(controller.input.selection.textInside(controller.input.text), '[topic]');
    controller.input.clear();
    await controller.flushDraft();
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Search rain');
    final answer = await DBChat.addAssistant(chat, 'fixture', provider: 'Saved provider');
    final query = <String, dynamic>{
      'operation': 'search_titles', 'source': 'r18', 'terms': ['rain', '雨'], 'limit': 25, 'offset': 0,
      'required_terms': [['outdoor', '屋外']], 'related_terms': [['walk', '散歩'], ['park', '公園']],
      'exclude_terms': ['compilation', '総集編'], 'unowned': true, 'missing_english': false,
      'similar_to': 'REF-001', 'sort': 'relevance',
    };
    answer..status = 'completed'..titleSearch = {...query, 'has_more': true}
      ..content = ChatKnowledge.render(await knowledge.request(query, CancelToken()));
    await DBChat.saveAssistant(answer);
    await controller.selectChat(chat);
    await tester.pumpAndSettle();
    final next = find.byTooltip('Next database page');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
    expect(controller.messages.last.content, contains('Rows 26–50'));
    expect(knowledge.offsets, [0, 25]);
    expect(knowledge.queries.last, {...query, 'offset': 25});
    await controller.reload();
    await tester.pumpAndSettle();
    expect(controller.messages.last.titleSearch, {...query, 'offset': 25, 'has_more': true});
    final before = controller.messages.last.content;
    database.failWrites = true;
    await controller.loadTitleSearchPage(controller.messages.last, 1);
    expect(controller.messages.last.content, before);
    expect(controller.messages.last.titleSearch, {...query, 'offset': 25, 'has_more': true});
    database.failWrites = false;
    await controller.loadTitleSearchPage(controller.messages.last, 1);
    await tester.pumpAndSettle();
    expect(controller.messages.last.content, contains('Rows 51–54'));
    expect(controller.messages.last.titleSearch?['has_more'], false);
    final requests = knowledge.offsets.length;
    await controller.loadTitleSearchPage(controller.messages.last, 1);
    expect(knowledge.offsets.length, requests);
    await controller.loadTitleSearchPage(controller.messages.last, -1);
    await tester.pumpAndSettle();
    expect(controller.messages.last.titleSearch, {...query, 'offset': 25, 'has_more': true});
    expect(knowledge.queries.last, {...query, 'offset': 25});
    expect(api.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Follow-ups carry saved search filters without pagination or private paths', (tester) async {
    addTearDown(Get.reset);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi();
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final filters = <String, dynamic>{
      'terms': ['rain', '雨'], 'source': 'r18', 'required_terms': [['outdoor', '屋外']],
      'related_terms': [['walk', '散歩'], ['park', '公園']], 'exclude_terms': ['compilation', '総集編'],
      'unowned': true, 'missing_english': false, 'similar_to': 'REF-001', 'sort': 'relevance',
    };
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Find similar videos');
    final answer = await DBChat.addAssistant(chat, 'fixture', provider: 'Saved provider');
    answer..status = 'completed'..content = 'Saved results with evidence.'..titleSearch = {
      ...filters, 'operation': 'search_titles', 'limit': 25, 'offset': 25, 'has_more': true,
      'main': '/private/kuraku.db', 'r18': '/private/r18.db', 'debug_path': '/private/debug',
      'reference': {'code': 'REF-001', 'path': '/private/library'},
    };
    await DBChat.saveAssistant(answer);
    await controller.reload();
    controller.usePrompt('Only show the strongest matches');
    await controller.send();
    expect(api.requests.single, hasLength(3));
    final saved = api.requests.single[1];
    expect(saved['role'], 'assistant');
    expect(saved['content'], 'Saved results with evidence.');
    expect(jsonDecode(saved['search_context']!), filters);
    expect(controller.messages[1].content, 'Saved results with evidence.');
    expect(api.requests.single.last, {'role': 'user', 'content': 'Only show the strongest matches'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('Indonesian search templates and command descriptions keep the same search rules', (tester) async {
    addTearDown(() { Get.reset(); Get.clearTranslations(); Get.locale = null; Get.fallbackLocale = null; });
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final controller = Get.put(PageChatController(api: _ChatApi()));
    await tester.pumpWidget(GetMaterialApp(translations: AppTranslations(), locale: const Locale('id'),
      fallbackLocale: AppTranslations.fallbackLocale, home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final topic = find.text('Cari topik di R18');
    await tester.ensureVisible(topic);
    await tester.tap(topic);
    await tester.pump();
    expect(controller.input.selection.textInside(controller.input.text), '[topik]');
    expect(controller.input.text, contains('Sertakan video dengan atau tanpa judul English'));
    expect(controller.input.text, contains('Urutkan berdasarkan relevansi kecuali gue minta rilis terbaru'));
    controller.useSimilarPrompt('TEST-001');
    expect(controller.input.text, contains('Tema utama wajib cocok; tema tambahan opsional buat peringkat'));
    expect(controller.input.text, contains('Pertahankan semua tema yang gue wajibkan sebagai filter AND'));
    expect(controller.templateFields(controller.input.text), isEmpty);
    controller.useTemplate('/filter');
    expect(controller.input.selection.textInside(controller.input.text), '[tema 1]');
    expect(controller.input.text, contains('Kedua tema dan setiap filter wajib lainnya harus cocok'));
    controller.usePrompt('/r');
    await tester.pump();
    expect(find.text('Template: cari topik R18 dengan bukti'), findsOneWidget);
    controller.usePrompt('/si');
    await tester.pump();
    expect(find.text('Template: cari tema mirip dengan bukti'), findsOneWidget);
    await controller.flushDraft();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Slash commands filter, navigate and run locally; clear persists only for the active chat', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi(apiKey: '');
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final first = controller.activeChat.value;
    await DBChat.send(first, 'Keep this conversation');
    await controller.newChat();
    final second = controller.activeChat.value;
    await DBChat.send(second, 'Clear this conversation');
    await controller.selectChat(second);
    controller.usePrompt('/');
    await tester.pump();
    expect(find.text('/status'), findsNothing);
    expect(find.text('/help'), findsNothing);
    expect(find.text('/clear'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.commandIndex.value, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.input.text, '/stop');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.matchingCommands, isEmpty);
    controller.usePrompt('/sto');
    await tester.pump();
    expect(find.text('/clear'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.commandNotice.value, 'No response is running.');
    expect(controller.messages.length, 1);
    expect(api.requests, isEmpty);
    controller.usePrompt('/unknown');
    await controller.send();
    expect(controller.input.text, '/unknown');
    expect(controller.commandNotice.value, contains('Unknown command'));
    controller.usePrompt('/help');
    await controller.send();
    expect(controller.commandNotice.value, contains('Unknown command'));
    controller.usePrompt('/clear');
    database.failWrites = true;
    await controller.send();
    expect(controller.messages.length, 1);
    expect(controller.input.text, '/clear');
    database.failWrites = false;
    await controller.send();
    await tester.pumpAndSettle();
    expect(controller.activeChat.value.id, second.id);
    expect(controller.messages, isEmpty);
    expect(controller.input.text, isEmpty);
    expect(await DBChat.getMessages(second.id), isEmpty);
    expect(await DBChat.getMessages(first.id), hasLength(1));
    await controller.reload();
    await tester.pumpAndSettle();
    expect(controller.messages, isEmpty);
    expect(controller.input.text, isEmpty);
    controller.usePrompt('/stop');
    await controller.send();
    expect(controller.commandNotice.value, 'No response is running.');
    await controller.flushDraft();
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear waits for a streaming response before deleting its messages', (tester) async {
    addTearDown(Get.reset);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi()..wait = Completer<void>();
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    controller.usePrompt('Hello');
    final sending = controller.send();
    await tester.pump();
    expect(controller.respondingChatId.value, isNotNull);
    controller.usePrompt('/clear');
    final clearing = controller.send();
    await tester.pump();
    api.wait!.complete();
    await Future.wait([sending, clearing]);
    await tester.pumpAndSettle();
    expect(controller.respondingChatId.value, isNull);
    expect(controller.messages, isEmpty);
    expect(await DBChat.getMessages(controller.activeChat.value.id), isEmpty);
    expect(controller.input.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A 200 row result paginates while copy and reload preserve all rows', (tester) async {
    addTearDown(Get.reset);
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final controller = Get.put(PageChatController(api: _ChatApi()));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Show 200 records');
    final response = await DBChat.addAssistant(chat, 'test', provider: 'Saved provider');
    response.content = ChatKnowledge.render({
      'columns': ['dvd_id', 'title_en'], 'rows': List.generate(200, (i) => ['TEST-${i + 1}', 'Sample title ${i + 1}']),
      'sources': ['fixture.db'], 'elapsed_ms': 1, 'truncated': false,
    });
    response.status = 'completed';
    await DBChat.saveAssistant(response);
    await controller.selectChat(chat);
    await tester.pumpAndSettle();
    final beforeScroll = controller.scrollController.offset;
    await tester.sendEventToBinding(const PointerScrollEvent(position: Offset(200, 250), scrollDelta: Offset(0, -180)));
    await tester.pumpAndSettle();
    expect(controller.scrollController.offset, greaterThan(beforeScroll));
    expect(find.text('1–25 of 200 · Page 1/8'), findsOneWidget);
    expect(find.text('Image', findRichText: true), findsOneWidget);
    expect(findHugeIcon(HugeIcons.strokeRoundedImage01), findsNWidgets(25));
    expect(find.textContaining('TEST-200', findRichText: true), findsNothing);
    final next = find.byTooltip('Next results');
    for (var i = 0; i < 7; i++) {
      await Scrollable.ensureVisible(tester.element(next), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(find.text('176–200 of 200 · Page 8/8'), findsOneWidget);
    expect(findHugeIcon(HugeIcons.strokeRoundedImage01), findsNWidgets(25));
    expect(find.textContaining('TEST-200', findRichText: true), findsOneWidget);
    final copy = find.byTooltip('Copy message').first;
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, response.content);
    await controller.reload();
    await tester.pumpAndSettle();
    expect(controller.messages.last.content, contains('| [TEST-200](kuraku-video:TEST-200) |'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity expands while working, collapses on completion, persists and legacy output retries cleanly', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi()..wait = Completer<void>();
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    controller.input.text = 'Hello';
    final sending = controller.send();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thinking...'), findsOneWidget);
    expect(find.text('• Checking your library'), findsOneWidget);
    await tester.tap(find.text('Thinking...'));
    await tester.pump();
    expect(find.text('• Checking your library'), findsNothing);
    await tester.tap(find.text('Thinking...'));
    await tester.pump();
    expect(find.text('• Checking your library'), findsOneWidget);
    api.wait!.complete();
    await sending;
    await tester.pumpAndSettle();
    expect(find.text('Thinking...'), findsNothing);
    expect(find.text('• Checking your library'), findsNothing);
    final bubble = find.byKey(ValueKey('bubble-${controller.messages.first.id}'));
    expect(tester.getSize(bubble).width, lessThan(300));
    await tester.tap(find.textContaining('Activity ·'));
    await tester.pump();
    expect(find.text('• Checking your library'), findsOneWidget);
    await controller.reload();
    await tester.pumpAndSettle();
    expect(controller.messages.last.activity, contains('Checking your library'));
    final answer = controller.messages.last;
    answer.content = '<tool_call>\n<function=web_search>\nSELECT * FROM main.videos\n</tool_call>';
    controller.activeChat.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('<tool_call>', findRichText: true), findsNothing);
    expect(find.text('Retry response'), findsOneWidget);
    await tester.tap(find.text('Retry response'));
    await tester.pumpAndSettle();
    expect(controller.messages.length, 2);
    expect(controller.messages.last.id, answer.id);
    expect(controller.messages.last.content, 'Test answer');
    expect(api.requests.last, [{'role': 'user', 'content': 'Hello'}]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Markdown messages render and copy across themes, widths and partial streams', (tester) async {
    addTearDown(Get.reset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final controller = Get.put(PageChatController(api: _ChatApi()));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.light(), darkTheme: ThemeData.dark(),
      home: const Scaffold(body: PageChatView()),
    ));
    await tester.pumpAndSettle();
    final content = '## Heading\n\n**Bold** and `inline`\n\n- First\n- Second\n\n'
        '| Name | Description |\n| --- | --- |\n| Item | ${'wide content ' * 12} |\n\n'
        '```dart\nfinal message = "${'long code ' * 15}";\n```';
    for (final role in ['user', 'assistant']) {
      controller.messages.add(ChatMessage.fromJson({
        'id': role, 'conversation_id': controller.activeChat.value.id, 'position': controller.messages.length,
        'role': role, 'content': content, 'status': 'completed', 'created_at': '', 'updated_at': '',
      }));
    }
    controller.activeChat.refresh();
    for (final width in [1100.0, 400.0]) {
      tester.view.physicalSize = Size(width, 1200);
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        Get.changeThemeMode(mode);
        await tester.pumpAndSettle();
        expect(find.byType(MarkdownBlock), findsWidgets);
        expect(find.byType(Table), findsWidgets);
        expect(find.textContaining('**Bold**', findRichText: true), findsNothing);
        expect(tester.takeException(), isNull);
        final copy = find.byTooltip('Copy message').last;
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(copied, content);
      }
    }
    final copyCode = find.byTooltip('Copy code').last;
    await tester.ensureVisible(copyCode);
    await tester.tap(copyCode);
    await tester.pumpAndSettle();
    expect(copied, contains('final message ='));
    expect(copied, isNot(contains('```')));
    controller.messages.last.status = 'streaming';
    controller.messages.last.content = '**Partial\n\n```dart\nfinal value =';
    controller.activeChat.refresh();
    controller.scrollController.jumpTo(0);
    await tester.pump();
    expect(find.text('Responding...'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.messages.last.status = 'cancelled';
    controller.activeChat.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Response stopped.'), findsOneWidget);
    expect(find.text('Retry response'), findsOneWidget);
  });

  testWidgets('Messages edit inline, preserve drafts and regenerate; pinned chats survive reload', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi();
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hybrid ·'), findsNothing);
    controller.usePrompt('Original question');
    await controller.send();
    controller.usePrompt('Follow-up');
    await controller.send();
    final first = controller.messages.first;
    controller.usePrompt('Unsent draft');
    await controller.flushDraft();
    await tester.pumpAndSettle();
    final edit = find.byTooltip('Edit message').last;
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('edit-message-input'));
    await tester.enterText(field, 'Changed question');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(controller.messages.first.content, 'Original question');
    expect(controller.input.text, 'Unsent draft');
    controller.editMessage(first);
    await tester.pumpAndSettle();
    await tester.enterText(field, '  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save & resend')).onPressed, isNull);
    await tester.enterText(field, 'Changed question');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save & resend'));
    await tester.pumpAndSettle();
    database.failWrites = true;
    await tester.tap(find.text('Save & resend'));
    await tester.pumpAndSettle();
    expect(controller.messages, hasLength(4));
    expect(controller.editInput.text, 'Changed question');
    expect(controller.error.value, isNotEmpty);
    database.failWrites = false;
    await tester.ensureVisible(find.text('Save & resend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & resend'));
    await tester.pumpAndSettle();
    expect(controller.messages.map((m) => m.content), ['Changed question', 'Test answer']);
    expect(controller.messages.first.id, first.id);
    expect(controller.input.text, 'Unsent draft');
    expect(api.requests.last, [{'role': 'user', 'content': 'Changed question'}]);
    final pinned = controller.activeChat.value;
    await tester.tap(find.descendant(of: find.widgetWithText(ListTile, pinned.title), matching: find.byTooltip('Chat options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin chat'));
    await tester.pumpAndSettle();
    expect(pinned.isPinned, isTrue);
    await controller.newChat();
    controller.usePrompt('Newer conversation');
    await controller.send();
    expect(controller.chats.first.id, pinned.id);
    await controller.reload();
    expect(controller.chats.first.id, pinned.id);
    expect(controller.chats.first.isPinned, isTrue);
    await controller.selectChat(controller.chats.first);
    expect(controller.messages.first.content, 'Changed question');
    expect(controller.input.text, 'Unsent draft');
    await controller.togglePin(controller.activeChat.value);
    expect(controller.chats.first.title, 'Newer conversation');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat history preserves drafts and supports search, rename and deletion', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final controller = Get.put(PageChatController(api: _ChatApi()));
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.light(), darkTheme: ThemeData.dark(), themeMode: ThemeMode.dark,
      home: const Scaffold(body: PageChatView()),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('How many videos do I have?'));
    await tester.tap(find.text('How many videos do I have?'));
    await tester.pump();
    expect(controller.input.text, 'How many videos do I have?');
    controller.input.value = controller.input.value.copyWith(composing: const TextRange(start: 0, end: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(controller.messages, isEmpty);
    controller.input.value = controller.input.value.copyWith(composing: TextRange.empty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.messages.map((message) => message.content), ['How many videos do I have?', 'Test answer']);
    expect(controller.input.text, isEmpty);
    await tester.enterText(find.widgetWithText(CupertinoTextField, 'Ask anything...'), '   ');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(controller.messages.length, 2);
    await tester.enterText(find.widgetWithText(CupertinoTextField, 'Ask anything...'), 'Draft');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.messages.length, 2);
    tester.testTextInput.enterText('Draft\nSecond line');
    await tester.pump();
    expect(controller.input.text, contains('\n'));
    database.failWrites = true;
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(controller.input.text, 'Draft\nSecond line');
    expect(controller.messages.length, 2);
    expect(controller.error.value, isNotEmpty);
    database.failWrites = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(controller.error.value, isEmpty);
    await controller.reload();
    await tester.pumpAndSettle();
    expect(controller.messages.first.content, 'How many videos do I have?');
    expect(controller.input.text, 'Draft\nSecond line');
    final first = controller.activeChat.value;
    await tester.tap(find.widgetWithText(OutlinedButton, 'New chat'));
    await tester.pumpAndSettle();
    expect(controller.messages, isEmpty);
    expect(controller.input.text, isEmpty);
    expect(controller.chats.length, 2);
    await tester.tap(find.widgetWithText(ListTile, first.title));
    await tester.pumpAndSettle();
    expect(controller.messages.length, 2);
    expect(controller.input.text, 'Draft\nSecond line');
    await tester.tap(find.descendant(of: find.widgetWithText(ListTile, first.title), matching: find.byTooltip('Chat options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextFormFieldRow), 'My library');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(first.title, 'My library');
    await tester.enterText(find.widgetWithText(CupertinoTextField, 'Search chats'), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No chats found'), findsOneWidget);
    await tester.enterText(find.widgetWithText(CupertinoTextField, 'Search chats'), 'library');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'My library'), findsOneWidget);
    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.chats.contains(first), isTrue);
    expect(tester.getCenter(find.byTooltip('Delete chat')).dx, lessThan(tester.getCenter(find.byTooltip('New chat')).dx));
    await tester.tap(find.byTooltip('Delete chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Delete'));
    await tester.pumpAndSettle();
    expect(controller.chats.contains(first), isFalse);
    expect(controller.messages, isEmpty);
    expect(controller.input.text, isEmpty);
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      Get.changeThemeMode(mode);
      await tester.pumpAndSettle();
      expect(find.text('What would you like to explore?'), findsOneWidget);
      await tester.tap(find.byTooltip('Toggle chat history'));
      await tester.pumpAndSettle();
      expect(find.text('Your chats'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'New chat'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
