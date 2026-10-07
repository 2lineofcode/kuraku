import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/modules/home/page_sqleditor/page_sqleditor_tab.dart';
import 'package:javit/app/modules/home/page_sqleditor/page_sqleditor_view.dart';
import 'package:javit/app/modules/widgets/widgets.dart';
import 'package:javit/app/utils/chat_service.dart';

import 'icon_finder.dart';

class _SqlApi extends ChatService {
  String sql = 'SELECT title FROM videos LIMIT 1;';
  Completer<String>? pending;
  @override
  Future<String> generateSql(String prompt, Map<String, List<String>> schema, CancelToken token) async => pending == null ? sql : await pending!.future;
}

void main() {
  testWidgets('SQL editor completes at cursor, keeps source drafts, and has no execution', (tester) async {
    final controller = Get.put(PageSqleditorTab(sources: {
      'javit.db': '/documents/JavIt/javit.db',
      'r18*.db': null,
    }));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    final editor = find.byType(AppTextField);
    await tester.tap(editor);
    await tester.enterText(editor, 'SELECT *\nFRom videos;');
    controller.input.selection = const TextSelection.collapsed(offset: 11);
    await tester.pump();
    expect(controller.suggestions, contains('FROM'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.input.text, 'SELECT *\nFROM videos;');
    expect(controller.input.selection.extentOffset, 13);

    await tester.enterText(editor, 'SEL');
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT', findRichText: true).last);
    await tester.pump();
    expect(controller.input.text, 'SELECT');

    await tester.tap(find.byType(AppDropdownFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('r18*.db').last);
    await tester.pumpAndSettle();
    expect(controller.source.value, 'r18*.db');
    expect(controller.input.text, isEmpty);
    expect(find.byTooltip('No R18 database is loaded'), findsOneWidget);
    await tester.enterText(editor, 'PR');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.suggestions, isEmpty);
    controller.selectSource('javit.db');
    await tester.pump();
    expect(controller.input.text, 'SELECT');
    controller.selectSource('r18*.db');
    await tester.pump();
    expect(controller.input.text, 'PR');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.binding.setSurfaceSize(const Size(420, 520));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Clear query'));
    await tester.pump();
    expect(controller.input.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    Get.reset();
  });

  testWidgets('SQL autocomplete refreshes cursor and schema context and supports keyboard dismissal', (tester) async {
    addTearDown(Get.reset);
    var schema = {'videos': ['id', 'title', 'video_code']};
    final controller = Get.put(PageSqleditorTab(sources: {'javit.db': '/javit.db'}, loadSchema: (_) async => schema));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    await tester.pumpAndSettle();
    final source = tester.getRect(find.byType(AppDropdownFormField<String>));
    final refresh = tester.getRect(find.byTooltip('Refresh table and column suggestions'));
    expect(refresh.size, const Size(32, 32));
    expect(refresh.left - source.right, 8);
    final editor = find.byType(AppTextField);
    await tester.enterText(editor, 'SELECT v.t FROM videos v;');
    controller.input.selection = const TextSelection.collapsed(offset: 10);
    await tester.pumpAndSettle();
    expect(find.byType(TypeAheadField<String>), findsOneWidget);
    expect(find.text('title', findRichText: true), findsOneWidget);
    final popup = tester.getRect(find.byKey(const ValueKey('sql-completion-popup')));
    final editable = tester.state<EditableTextState>(find.descendant(of: editor, matching: find.byType(EditableText)));
    final caret = editable.renderEditable.getLocalRectForCaret(controller.input.selection.extent);
    final caretPosition = editable.renderEditable.localToGlobal(caret.bottomLeft);
    expect(popup.top, closeTo(caretPosition.dy + 2, 1));
    expect(popup.left, closeTo(caretPosition.dx, 1));
    expect(popup.width, lessThanOrEqualTo(360));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.input.text, 'SELECT v.title FROM videos v;');
    expect(controller.focusNode.hasFocus, isTrue);
    expect(controller.completionPopup.isOpen, isFalse);

    await tester.enterText(editor, 'SELECT * FROM ');
    await tester.pumpAndSettle();
    expect(find.text('videos', findRichText: true), findsOneWidget);
    schema = {'derived_video': ['dvd_id']};
    await controller.refreshSchema();
    await tester.pumpAndSettle();
    expect(find.text('videos', findRichText: true), findsNothing);
    expect(find.text('derived_video', findRichText: true), findsOneWidget);

    await tester.enterText(editor, '');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.suggestions, contains('SELECT'));
    expect(controller.completionPopup.isOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.completionPopup.isOpen, isFalse);
    expect(controller.focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.input.text, isEmpty);

    await tester.enterText(editor, "SELECT 'ti");
    await tester.pumpAndSettle();
    expect(controller.completionPopup.isOpen, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
  });

  testWidgets('SQL popup follows multiline caret and scroll and stays inside a narrow editor', (tester) async {
    addTearDown(Get.reset);
    final controller = Get.put(PageSqleditorTab(sources: {'javit.db': '/javit.db'},
      loadSchema: (_) async => {'videos': ['id', 'title'], 'derived_video': ['dvd_id']}));
    await tester.binding.setSurfaceSize(const Size(420, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    await tester.pumpAndSettle();
    final editor = find.byType(AppTextField);
    final popupFinder = find.byKey(const ValueKey('sql-completion-popup'));
    await tester.enterText(editor, 'SELECT * FROM videos v;\nSELECT v.t FROM videos v;');
    controller.input.selection = const TextSelection.collapsed(offset: 33);
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.descendant(of: editor, matching: find.byType(EditableText)));
    final caret = editable.renderEditable.getLocalRectForCaret(controller.input.selection.extent);
    final caretPosition = editable.renderEditable.localToGlobal(caret.bottomLeft);
    expect(tester.getRect(popupFinder).top, closeTo(caretPosition.dy + 2, 1));
    expect(tester.getRect(popupFinder).right, lessThanOrEqualTo(tester.getRect(editor).right + 1));

    await tester.enterText(editor, '${'-- comment\n' * 40}SELECT * FROM de');
    await tester.pumpAndSettle();
    expect(find.text('derived_video', findRichText: true), findsOneWidget);
    final scroll = tester.widget<AppTextField>(editor).scrollController!;
    expect(scroll.offset, greaterThan(0));
    final bottom = scroll.offset;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(popupFinder, findsNothing);
    scroll.jumpTo(bottom);
    await tester.pumpAndSettle();
    expect(popupFinder, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('CRUD snippets append and AI prompt stays in the frontend session', (tester) async {
    final controller = Get.put(PageSqleditorTab(
      sources: {'javit.db': '/javit.db', 'r18*.db': null},
      loadSchema: (_) async => {'videos': ['id', 'title', 'video_code']},
    ));
    await tester.binding.setSurfaceSize(const Size(420, 520));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    await tester.pumpAndSettle();
    controller.input.text = 'SELECT 1;';
    await tester.tap(find.text('Snippets'));
    await tester.pumpAndSettle();
    expect(find.text('SQL snippets'), findsOneWidget);
    expect(find.text('SELECT *\nFROM "videos"\nLIMIT 100;'), findsOneWidget);
    for (final action in ['INSERT', 'UPDATE']) {
      await tester.tap(find.byKey(const ValueKey('snippet-operation')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action).last);
      await tester.pumpAndSettle();
      expect(find.text(controller.buildSnippet(action, 'videos')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('DELETE'), findsNothing);
    final snippet = controller.buildSnippet('UPDATE', 'videos');
    expect(snippet, contains('WHERE /* replace with your condition */ 1 = 0'));
    await tester.tap(find.text('Add to editor'));
    await tester.pumpAndSettle();
    expect(controller.input.text, 'SELECT 1;\n\n$snippet');
    expect(controller.input.selection.textInside(controller.input.text), snippet);
    expect(controller.buildSnippet('SELECT', 'odd"name'), contains('"odd""name"'));
    expect(controller.buildSnippet('INSERT', 'videos'), contains('("title")\nVALUES (:value)'));
    expect(controller.buildSnippet('SELECT', 'table_name'), contains('"table_name"'));

    await tester.tap(find.text('Snippets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.input.text, 'SELECT 1;\n\n$snippet');
    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    expect(find.text('Generate SQL with AI'), findsOneWidget);
    final prompt = find.descendant(of: find.byType(AppDialog), matching: find.byType(AppTextField));
    await tester.enterText(prompt, 'Show the newest videos');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate')).onPressed, isNotNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Insert SQL')).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    expect(find.text('Show the newest videos'), findsOneWidget);
    expect(controller.input.text, 'SELECT 1;\n\n$snippet');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    Get.reset();
  });

  testWidgets('AI validates before insert; run renders rows; writes require confirmation', (tester) async {
    final api = _SqlApi();
    final requests = <Map<String, dynamic>>[];
    final controller = Get.put(PageSqleditorTab(
      sources: {'javit.db': '/javit.db'}, api: api,
      loadSchema: (_) async => {'videos': ['id', 'title']},
      query: (source, request, token) async {
        requests.add(Map.of(request));
        final sql = request['sql'] as String;
        if (sql.startsWith('DELETE')) throw StateError('DELETE is blocked.');
        if (request['operation'] == 'validate') return {'requires_confirmation': false};
        if (sql.startsWith('UPDATE')) return request['confirm_write'] == true
            ? {'write': true, 'affected_rows': 1, 'columns': [], 'rows': [], 'elapsed_ms': 1}
            : {'requires_confirmation': true};
        return {'write': false, 'columns': ['title'], 'rows': [['Example title']], 'elapsed_ms': 1};
      },
    ));
    await tester.binding.setSurfaceSize(const Size(420, 520));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    final prompt = find.descendant(of: find.byType(AppDialog), matching: find.byType(AppTextField));
    await tester.enterText(prompt, 'Read one video');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.text(api.sql), findsOneWidget);
    expect(requests.single['operation'], 'validate');
    await tester.tap(find.text('Insert SQL'));
    await tester.pumpAndSettle();
    expect(controller.input.text, api.sql);
    expect(requests.length, 1);
    await tester.tap(find.text('Run selection'));
    await tester.pumpAndSettle();
    expect(find.text('Example title'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.input.text = 'UPDATE videos SET title=:value WHERE id=1';
    controller.parameters.text = '{"value":"Updated"}';
    await tester.pump();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm database change'), findsOneWidget);
    expect(requests.last['confirm_write'], isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests.where((request) => request['confirm_write'] == true), isEmpty);
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply changes'));
    await tester.pumpAndSettle();
    expect(requests.last['confirm_write'], isTrue);
    expect(requests.last['args'], {'value': 'Updated'});
    expect(find.text('1 row(s) changed.'), findsOneWidget);

    controller.input.text = 'DELETE FROM videos';
    await tester.pump();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.text('DELETE is blocked.'), findsOneWidget);
    api.sql = 'DELETE FROM videos';
    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(controller.aiSql.value, isEmpty);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Insert SQL')).onPressed, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    Get.reset();
  });

  test('Stopped queries and stale AI generations cannot overwrite another source', () async {
    final queryResponse = Completer<Map<String, dynamic>>();
    final api = _SqlApi()..pending = Completer<String>();
    final controller = PageSqleditorTab(sources: {'javit.db': '/javit.db', 'r18*.db': '/r18.db'}, api: api,
      loadSchema: (_) async => {'videos': ['id']}, query: (_, request, token) => queryResponse.future);
    controller.onInit();
    await controller.refreshSchema();
    controller.input.text = 'SELECT id FROM videos';
    controller.parameters.text = 'invalid json';
    await controller.runQuery((_, source, parameters) async => false);
    expect(controller.queryError.value, contains('JSON'));
    controller.parameters.text = '{}';
    final run = controller.runQuery((_, source, parameters) async => false);
    controller.stopQuery();
    queryResponse.complete({'rows': [[1]], 'columns': ['id']});
    await run;
    expect(controller.result.value, isNull);
    controller.aiPrompt.text = 'Read';
    final generating = controller.generateSql();
    controller.selectSource('r18*.db');
    api.pending!.complete('SELECT id FROM videos');
    await generating;
    expect(controller.aiSql.value, isEmpty);
    expect(controller.generating.value, isFalse);
    controller.onClose();
  });

  testWidgets('Cmd+Enter runs selection or full query without newline or duplicate requests', (tester) async {
    final requests = <String>[];
    final pending = Completer<Map<String, dynamic>>();
    final controller = Get.put(PageSqleditorTab(sources: {'javit.db': '/javit.db'}, query: (_, request, token) {
      requests.add(request['sql'] as String);
      return pending.future;
    }));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    await tester.tap(find.byType(AppTextField));
    await tester.enterText(find.byType(AppTextField), 'SELECT 1;\nSELECT 2;');
    controller.input.selection = const TextSelection(baseOffset: 10, extentOffset: 19);
    await tester.pump();
    expect(find.text('Run selection'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(requests, ['SELECT 2;']);
    expect(controller.input.text, 'SELECT 1;\nSELECT 2;');
    pending.complete({'rows': [], 'columns': [], 'elapsed_ms': 1});
    await tester.pumpAndSettle();
    controller.input.selection = const TextSelection.collapsed(offset: 19);
    await tester.pump();
    expect(find.text('Run'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(requests.last, 'SELECT 1;\nSELECT 2;');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(requests.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
  });

  testWidgets('Format action and dvd_id and video_code links keep the compact result layout', (tester) async {
    final opened = <dynamic>[];
    final controller = Get.put(PageSqleditorTab(sources: {'javit.db': '/javit.db'}));
    await tester.binding.setSurfaceSize(const Size(420, 520));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller, openVideoInfo: (item) async { opened.add(item); }))));
    await tester.enterText(find.byType(AppTextField), 'select dvd_id from derived_video');
    await tester.tap(find.byTooltip('Format SQL (selection or entire query)'));
    await tester.pump();
    expect(controller.input.text, contains('SELECT\n'));
    controller.result.value = {'columns': ['dvd_id', 'release_date'], 'rows': [
      ['KC90AE-309', '2026-05-26'], [null, '2026-05-12'], ['', '2026-05-12'],
    ], 'elapsed_ms': 1};
    await tester.pump();
    expect(find.widgetWithText(TextButton, 'KC90AE-309'), findsOneWidget);
    expect(find.byTooltip('Open video info: KC90AE-309'), findsNothing);
    expect(find.byTooltip('2026-05-26'), findsNothing);
    expect(find.byTooltip('dvd_id'), findsNothing);
    expect(find.widgetWithText(TextButton, '2026-05-26'), findsNothing);
    await tester.tap(find.text('KC90AE-309'));
    await tester.pump();
    expect(opened, [{'video_code': 'KC90AE-309'}]);
    controller.result.value = {'columns': [' VIDEO_CODE ', 'release_date'], 'rows': [
      [' ABC-001 ', '2026-05-26'], [null, '2026-05-12'], ['', '2026-05-12'], [123, '2026-05-12'],
    ], 'elapsed_ms': 1};
    await tester.pump();
    expect(find.widgetWithText(TextButton, ' ABC-001 '), findsOneWidget);
    await tester.tap(find.text(' ABC-001 '));
    await tester.pump();
    expect(opened, [{'video_code': 'KC90AE-309'}, {'video_code': 'ABC-001'}]);
    expect(find.widgetWithText(TextButton, '123'), findsNothing);
    expect(find.widgetWithText(TextButton, 'NULL'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    Get.reset();
  });

  testWidgets('Results use one horizontal scroll even over long selectable cell values', (tester) async {
    addTearDown(Get.reset);
    final controller = Get.put(PageSqleditorTab(sources: {'javit.db': '/javit.db'}));
    const longValue = '4d06-8f52-7a5b0b2f1a76-very-long-value';
    controller.result.value = {
      'columns': ['id', 'video_id', 'video_code', 'watch_count'],
      'rows': List.generate(30, (index) => [longValue, 'video-$index', 'CODE-$index', index]),
      'elapsed_ms': 1,
    };
    await tester.binding.setSurfaceSize(const Size(420, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    await tester.pumpAndSettle();
    final table = find.byKey(const ValueKey('sql-results-table'));
    final scrollables = find.descendant(of: table, matching: find.byType(Scrollable));
    final horizontal = scrollables.evaluate().where((element) => (element.widget as Scrollable).axis == Axis.horizontal).single;
    final vertical = scrollables.evaluate().where((element) => (element.widget as Scrollable).axis == Axis.vertical).single;
    final horizontalState = (horizontal as StatefulElement).state as ScrollableState;
    final verticalState = (vertical as StatefulElement).state as ScrollableState;
    expect(find.descendant(of: table, matching: find.byType(SelectableText)), findsNothing);
    expect(tester.widget<Text>(find.text(longValue).first).overflow, TextOverflow.ellipsis);
    expect(find.byTooltip(longValue), findsWidgets);
    final point = tester.getCenter(find.text(longValue).first);
    final headerX = tester.getTopLeft(find.text('id')).dx;
    await tester.sendEventToBinding(PointerScrollEvent(position: point, scrollDelta: const Offset(100, 0)));
    await tester.pumpAndSettle();
    expect(horizontalState.position.pixels, 100);
    expect(tester.getTopLeft(find.text('id')).dx, closeTo(headerX - 100, 1));
    await tester.sendEventToBinding(PointerScrollEvent(position: point, scrollDelta: const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(verticalState.position.pixels, 60);
    expect(horizontalState.position.pixels, 100);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Jacket thumbnail previews lead results and handle empty and invalid URLs', (tester) async {
    addTearDown(Get.reset);
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = Get.put(PageSqleditorTab(sources: {'javit.db': '/javit.db'}));
    controller.result.value = {
      'columns': ['dvd_id', 'jacket_thumb_url'],
      'rows': [['CODE-1', null], ['CODE-2', ''], ['CODE-3', 'not-a-url']],
      'elapsed_ms': 1,
    };
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    await tester.pumpAndSettle();
    expect(find.text('Thumbnail'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Thumbnail')).dx, lessThan(tester.getTopLeft(find.text('dvd_id')).dx));
    expect(findHugeIcon(HugeIcons.strokeRoundedImage01), findsNWidgets(3));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.widgetWithText(TextButton, 'CODE-1'), findsOneWidget);
    final table = find.byKey(const ValueKey('sql-results-table'));
    expect(tester.widget<ListView>(find.descendant(of: table, matching: find.byType(ListView))).itemExtent, 64);
    final folder = Directory.systemTemp.createTempSync('javit-sql-thumbnail-');
    addTearDown(() => folder.deleteSync(recursive: true));
    Get.put(AppSettingService()..appPath = folder.path);
    controller.result.value = {
      'columns': ['jacket_thumb_url'],
      'rows': [['https://pics.dmm.co.jp/digital/video/test/testps.jpg'], ['digital/video/test/testps.jpg']],
      'elapsed_ms': 1,
    };
    await tester.pump();
    final thumbnails = tester.widgetList<ExThumbnail>(find.byType(ExThumbnail)).toList();
    expect(thumbnails, hasLength(2));
    expect(thumbnails.every((image) => image.imageUrl == 'digital/video/test/testps.jpg' && image.withProxy == true), isTrue);
    expect(tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).every((image) => !image.imageUrl.startsWith('https://pics.dmm.co.jp/')), isTrue);
    controller.result.value = {'columns': ['id'], 'rows': [[1]], 'elapsed_ms': 1};
    await tester.pumpAndSettle();
    expect(find.text('Thumbnail'), findsNothing);
    expect(tester.widget<ListView>(find.descendant(of: table, matching: find.byType(ListView))).itemExtent, 30);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Custom snippets save selection, reload, and preserve the editor draft', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var stored = <String, dynamic>{};
    final controller = Get.put(PageSqleditorTab(sources: {'javit.db': '/javit.db'},
      persistSnippets: (value) async { stored = value; }));
    addTearDown(() => Get.reset());
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    controller.input.text = 'SELECT 1; SELECT 2;';
    controller.input.selection = const TextSelection(baseOffset: 10, extentOffset: 19);
    await tester.tap(find.text('Snippets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved queries'));
    await tester.pumpAndSettle();
    expect(find.text('No saved queries in javit.db'), findsOneWidget);
    await tester.tap(find.text('Save current query'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextFormField), 'Second query');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(stored['javit.db'], {'Second query': 'SELECT 2;'});
    expect(find.byType(AppTextFormField), findsNothing);
    expect(find.widgetWithText(ListTile, 'Second query'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Load snippet'));
    await tester.pumpAndSettle();
    expect(controller.input.text, 'SELECT 1; SELECT 2;\n\nSELECT 2;');
    expect(controller.input.selection.textInside(controller.input.text), 'SELECT 2;');
    controller.input.text = 'SELECT 1; SELECT 2;\n\nSELECT 3;';
    await tester.tap(find.text('Snippets'));
    await tester.pumpAndSettle();
    expect(find.text('Editing: Second query'), findsOneWidget);
    await tester.tap(find.text('Update snippet'));
    await tester.pumpAndSettle();
    expect(stored['javit.db'], {'Second query': 'SELECT 3;'});
    expect(controller.input.text, 'SELECT 1; SELECT 2;\n\nSELECT 3;');
    await tester.tap(find.text('Save as new'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextFormField), 'Copy');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(stored['javit.db'], {'Second query': 'SELECT 3;', 'Copy': 'SELECT 3;'});
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final reloaded = PageSqleditorTab(sources: controller.sources, savedSnippets: stored,
      persistSnippets: (value) async { stored = value; });
    expect(reloaded.snippetsFor('javit.db'), {'Second query': 'SELECT 3;', 'Copy': 'SELECT 3;'});
    expect(reloaded.snippetsFor('r18*.db'), isEmpty);
    await expectLater(reloaded.saveSnippet('javit.db', 'Second query', 'SELECT 3;'), throwsStateError);
    await reloaded.saveSnippet('javit.db', 'Second query', null);
    expect(stored['javit.db'], {'Copy': 'SELECT 3;'});
    controller.input.text = 'Changed unrelated query; SELECT 3;';
    expect(controller.loadedSnippetName, isNull);
    reloaded.onClose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Failed snippet persistence keeps previous queries and rejects empty input', () async {
    final controller = PageSqleditorTab(sources: {'javit.db': '/javit.db'},
      savedSnippets: {'javit.db': {'Existing': 'SELECT 1;'}},
      persistSnippets: (_) async => throw StateError('Disk unavailable'));
    await expectLater(controller.saveSnippet('javit.db', '', 'SELECT 2;'), throwsStateError);
    await expectLater(controller.saveSnippet('javit.db', 'Empty', '  '), throwsStateError);
    await expectLater(controller.saveSnippet('javit.db', 'New', 'SELECT 2;'), throwsStateError);
    await expectLater(controller.saveSnippet('javit.db', 'Existing', null), throwsStateError);
    await expectLater(controller.saveSnippet('javit.db', 'Existing', 'SELECT 2;', update: true), throwsStateError);
    await expectLater(controller.saveSnippet('javit.db', 'Missing', 'SELECT 2;', update: true), throwsStateError);
    expect(controller.snippetsFor('javit.db'), {'Existing': 'SELECT 1;'});
    controller.onClose();
  });

  testWidgets('First open shows saved queries in another source without losing the draft', (tester) async {
    final controller = Get.put(PageSqleditorTab(
      sources: {'javit.db': '/javit.db', 'r18*.db': '/r18.db'},
      savedSnippets: {'r18*.db': {'First': 'SELECT 1;', 'Second': 'SELECT 2;'}}));
    addTearDown(() => Get.reset());
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: PageSqleditorTabView(controller: controller))));
    controller.input.text = 'SELECT 3;';
    await tester.tap(find.text('Snippets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved queries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View 2 saved in r18*.db'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'First'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Second'), findsOneWidget);
    expect(controller.source.value, 'r18*.db');
    await tester.tap(find.widgetWithText(ListTile, 'Second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load snippet'));
    await tester.pumpAndSettle();
    expect(controller.input.text, 'SELECT 2;');
    controller.selectSource('javit.db');
    expect(controller.input.text, 'SELECT 3;');
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
