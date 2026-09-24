import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_chat.dart';
import 'package:javit/app/data/models/chat_entity.dart';
import 'package:javit/app/modules/home/page_chat/page_chat_controller.dart';
import 'package:javit/app/modules/home/page_chat/page_chat_view.dart';
import 'package:javit/app/utils/agnes_chat_service.dart';
import 'package:javit/app/utils/chat_knowledge.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'chat_test_database.dart';

class _Agnes extends AgnesChatService {
  _Agnes({String apiKey = 'test-key', super.knowledge}) : super(apiKey: apiKey);
  int translations = 0;
  bool translationFails = false;
  @override
  Future<String> translateTitle(String title, CancelToken token) async {
    translations++;
    if (translationFails) throw const AgnesChatException('Translation unavailable.');
    return 'Berjalan di tengah hujan';
  }
  Completer<void>? wait;
  final requests = <List<Map<String, String>>>[];
  @override
  Stream<String> reply(List<Map<String, String>> messages, CancelToken cancelToken) async* {
    requests.add(messages);
    onActivity?.call('Checking your library');
    if (wait != null) await wait!.future;
    yield 'Test answer';
  }
}

class _PagedKnowledge extends ChatKnowledge {
  _PagedKnowledge() : super(mainPath: '/fixture/javit.db');
  final offsets = <int>[];
  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> query, CancelToken token) async {
    final offset = query['offset'] as int? ?? 0;
    offsets.add(offset);
    return {
      'columns': ['code', 'title'],
      'rows': List.generate(offset >= 50 ? 4 : 25, (i) => ['TEST-${offset + i + 1}', 'Sample title']),
      'page_offset': offset, 'search_terms': ['rain', '雨'], 'has_more': offset < 50,
      'sources': ['fixture.db'], 'elapsed_ms': 1, 'truncated': offset < 50,
    };
  }
}

void main() {
  testWidgets('Image preview supports arrow navigation, bounds and close without changing the draft', (tester) async {
    addTearDown(Get.reset);
    Get.put<DBService>(ChatTestService()..dbMain = ChatTestDatabase());
    final folder = Directory.systemTemp.createTempSync('javit-preview-test-');
    addTearDown(() => folder.deleteSync(recursive: true));
    Get.put(AppSettingService()..pref = ChatTestPreferences()..appPath = folder.path);
    final controller = Get.put(PageChatController(api: _Agnes()));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Show images');
    final answer = await DBChat.addAssistant(chat, 'fixture');
    answer..status = 'completed'..content = ChatKnowledge.render({
      'columns': ['code', 'title'], 'rows': [['TEST-001', 'One'], ['TEST-002', 'Missing'], ['TEST-003', 'Three']],
      'covers': {'TEST-001': 'https://example.com/one.jpg', 'TEST-003': 'https://example.com/three.jpg'},
      'sources': ['fixture'], 'elapsed_ms': 1, 'truncated': false,
    });
    await DBChat.saveAssistant(answer);
    await controller.selectChat(chat);
    controller.usePrompt('Keep my draft');
    await tester.pump(const Duration(milliseconds: 400));
    final cover = find.byTooltip('Preview image').first;
    await tester.ensureVisible(cover);
    await tester.tap(cover);
    await tester.pump(const Duration(milliseconds: 400));
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
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.descendant(of: dialog, matching: find.text('TEST-003')), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text('TEST-003')));
    await tester.pump();
    expect(copied, 'TEST-003');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous image (←)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('1 / 2'), findsOneWidget);
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
    final api = _Agnes()..translationFails = true;
    final controller = Get.put(PageChatController(api: api));
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageChatView())));
    await tester.pumpAndSettle();
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Search rain');
    final answer = await DBChat.addAssistant(chat, 'fixture');
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
    expect(controller.input.text, contains('Cari video mirip TEST-001'));
    await controller.flushDraft();
    expect(tester.takeException(), isNull);
  });

  testWidgets('R18 template selects the topic and database pages persist without model calls', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final knowledge = _PagedKnowledge();
    final api = _Agnes(knowledge: knowledge);
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
    await tester.ensureVisible(find.text('Cari judul Jepang di R18'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cari judul Jepang di R18'));
    await tester.pump();
    expect(controller.input.selection.textInside(controller.input.text), '[topik]');
    expect(controller.input.text, contains('Jangan batasi total hasil'));
    controller.usePrompt('/r18');
    await controller.send();
    expect(controller.input.selection.textInside(controller.input.text), '[topik]');
    controller.input.clear();
    await controller.flushDraft();
    final chat = controller.activeChat.value;
    await DBChat.send(chat, 'Search rain');
    final answer = await DBChat.addAssistant(chat, 'fixture');
    final query = <String, dynamic>{'operation': 'search_titles', 'source': 'r18', 'terms': ['rain', '雨'], 'limit': 25, 'offset': 0};
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
    await controller.reload();
    await tester.pumpAndSettle();
    expect(controller.messages.last.titleSearch?['offset'], 25);
    final before = controller.messages.last.content;
    database.failWrites = true;
    await controller.loadTitleSearchPage(controller.messages.last, 1);
    expect(controller.messages.last.content, before);
    expect(controller.messages.last.titleSearch?['offset'], 25);
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
    expect(controller.messages.last.titleSearch?['offset'], 25);
    expect(api.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Slash commands filter, navigate and run locally; clear persists only for the active chat', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _Agnes(apiKey: '');
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
    expect(find.text('/status'), findsOneWidget);
    expect(find.text('/clear'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.commandIndex.value, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.input.text, '/new');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.matchingCommands, isEmpty);
    controller.usePrompt('/sta');
    await tester.pump();
    expect(find.text('/clear'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.commandNotice.value, contains('API: not configured'));
    expect(controller.messages.length, 1);
    expect(api.requests, isEmpty);
    controller.usePrompt('/unknown');
    await controller.send();
    expect(controller.input.text, '/unknown');
    expect(controller.commandNotice.value, contains('Unknown command'));
    controller.usePrompt('/help');
    await controller.send();
    expect(controller.commandNotice.value, contains('/clear'));
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
    final api = _Agnes()..wait = Completer<void>();
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
    final controller = Get.put(PageChatController(api: _Agnes()));
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
    final response = await DBChat.addAssistant(chat, 'test');
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
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNWidgets(25));
    expect(find.text('TEST-200', findRichText: true), findsNothing);
    final next = find.byTooltip('Next results');
    for (var i = 0; i < 7; i++) {
      await Scrollable.ensureVisible(tester.element(next), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(find.text('176–200 of 200 · Page 8/8'), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNWidgets(25));
    expect(find.text('TEST-200', findRichText: true), findsOneWidget);
    final copy = find.byTooltip('Copy message').first;
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, response.content);
    await controller.reload();
    await tester.pumpAndSettle();
    expect(controller.messages.last.content, contains('| TEST-200 |'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity expands while working, collapses on completion, persists and legacy output retries cleanly', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _Agnes()..wait = Completer<void>();
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
    final controller = Get.put(PageChatController(api: _Agnes()));
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

  testWidgets('Chat history preserves drafts and supports search, rename and deletion', (tester) async {
    addTearDown(Get.reset);
    final database = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = database);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final controller = Get.put(PageChatController(api: _Agnes()));
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.light(), darkTheme: ThemeData.dark(), themeMode: ThemeMode.dark,
      home: const Scaffold(body: PageChatView()),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Berapa jumlah video saya?'));
    await tester.tap(find.text('Berapa jumlah video saya?'));
    await tester.pump();
    expect(controller.input.text, 'Berapa jumlah video saya?');
    controller.input.value = controller.input.value.copyWith(composing: const TextRange(start: 0, end: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(controller.messages, isEmpty);
    controller.input.value = controller.input.value.copyWith(composing: TextRange.empty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.messages.map((message) => message.content), ['Berapa jumlah video saya?', 'Test answer']);
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
    expect(controller.messages.first.content, 'Berapa jumlah video saya?');
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
