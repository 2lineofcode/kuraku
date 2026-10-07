import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:javit/app/modules/home/page_sqleditor/page_sqleditor_controller.dart';
import 'package:javit/app/modules/home/page_sqleditor/page_sqleditor_view.dart';
import 'package:javit/app/modules/widgets/widgets.dart';

void main() {
  testWidgets('Results expand to fill the page and restore the query and tabs', (tester) async {
    addTearDown(Get.reset);
    final controller = Get.put(PageSqleditorController(sources: {'javit.db': '/javit.db'}));
    final tab = controller.activeTab;
    tab.input.text = 'SELECT 1;';
    tab.result.value = {'columns': ['value'], 'rows': [[1]], 'elapsed_ms': 1};
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: PageSqleditorView())));
    await tester.pumpAndSettle();
    final normalHeight = tester.getSize(find.byKey(const ValueKey('sql-results-table'))).height;
    expect(find.byTooltip('New SQL tab'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand results'));
    await tester.pumpAndSettle();
    expect(find.byType(AppTextField), findsNothing);
    expect(find.byTooltip('New SQL tab'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('sql-results-table'))).height, greaterThan(normalHeight));
    expect(find.text('value'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore query editor'));
    await tester.pumpAndSettle();
    expect(find.byType(AppTextField), findsOneWidget);
    expect(find.byTooltip('New SQL tab'), findsOneWidget);
    expect(tab.input.text, 'SELECT 1;');
    expect(find.text('value'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('SQL tabs isolate late results and restore drafts without executing SQL', (tester) async {
    var stored = <String, dynamic>{};
    var requests = 0;
    final pending = Completer<Map<String, dynamic>>();
    final controller = Get.put(PageSqleditorController(
      sources: {'javit.db': '/javit.db', 'r18*.db': '/r18.db'},
      savedSnippets: {'javit.db': {'Example': 'SELECT :value;'}},
      query: (_, request, token) { requests++; return pending.future; },
      persistTabs: (value) async { stored = jsonDecode(jsonEncode(value)) as Map<String, dynamic>; },
    ));
    addTearDown(() => Get.reset());
    await tester.binding.setSurfaceSize(const Size(420, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: PageSqleditorView())));
    final first = controller.activeTab;
    first.appendSnippet('SELECT :value;', name: 'Example');
    first.parameters.text = '{"value":1}';
    final running = first.runQuery((sql, source, parameters) async => false);
    await tester.pump();
    await tester.tap(find.byTooltip('New SQL tab'));
    await tester.pump();
    expect(controller.tabs.length, 2);
    final second = controller.activeTab;
    second.selectSource('r18*.db');
    second.input.text = 'SELECT dvd_id FROM derived_video;';
    second.parameters.text = '{"value":2}';
    pending.complete({'columns': ['value'], 'rows': [[1]], 'elapsed_ms': 1});
    await running;
    await tester.pumpAndSettle();
    expect(first.result.value?['rows'], [[1]]);
    expect(second.result.value, isNull);
    expect(tester.takeException(), isNull);
    controller.selectTab(0);
    await tester.pumpAndSettle();
    expect(controller.activeTab.input.text, 'SELECT :value;');
    expect(controller.activeTab.parameters.text, '{"value":1}');
    expect(controller.activeTab.loadedSnippetName, 'Example');
    controller.selectTab(1);
    await controller.saveTabs();
    final restored = PageSqleditorController(sources: controller.sources, savedTabs: stored,
      savedSnippets: {'javit.db': {'Example': 'SELECT :value;'}},
      query: (_, request, token) async { requests++; return {}; });
    restored.onStart();
    expect(restored.tabs.length, 2);
    expect(restored.activeTabIndex.value, 1);
    expect(restored.activeTab.source.value, 'r18*.db');
    expect(restored.activeTab.input.text, second.input.text);
    expect(restored.activeTab.parameters.text, '{"value":2}');
    expect(restored.tabs.first.loadedSnippetName, 'Example');
    expect(restored.tabs.first.result.value, isNull);
    expect(requests, 1);
    restored.onDelete();
    controller.closeTab(0);
    await tester.pumpAndSettle();
    expect(first.isClosed, isTrue);
    expect(controller.activeTab, same(second));
    controller.closeTab(0);
    await tester.pumpAndSettle();
    expect(second.isClosed, isTrue);
    expect(controller.tabs.length, 1);
    expect(controller.activeTab.input.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Shared snippets serialize saves and tab persistence can retry', (tester) async {
    var fail = true;
    var stored = <String, dynamic>{};
    final controller = Get.put(PageSqleditorController(sources: {'javit.db': '/javit.db'},
      persistSnippets: (value) async { stored = jsonDecode(jsonEncode(value)) as Map<String, dynamic>; },
      persistTabs: (_) async { if (fail) throw StateError('Disk unavailable'); }));
    addTearDown(() => Get.reset());
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: PageSqleditorView())));
    final first = controller.activeTab;
    controller.addTab();
    final second = controller.activeTab;
    await Future.wait([
      first.saveSnippet('javit.db', 'First', 'SELECT 1;'),
      second.saveSnippet('javit.db', 'Second', 'SELECT 2;'),
    ]);
    expect(stored['javit.db'], {'First': 'SELECT 1;', 'Second': 'SELECT 2;'});
    expect(first.snippetsFor('javit.db'), second.snippetsFor('javit.db'));
    await controller.saveTabs();
    expect(controller.saveError.value, isNotEmpty);
    fail = false;
    await controller.saveTabs();
    expect(controller.saveError.value, isEmpty);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('A tab cannot close while a write is committing', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final controller = Get.put(PageSqleditorController(sources: {'javit.db': '/javit.db'},
      query: (_, request, token) {
        if (request['confirm_write'] == true) return pending.future;
        return Future.value({'requires_confirmation': true});
      }));
    addTearDown(() => Get.reset());
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: PageSqleditorView())));
    final first = controller.activeTab;
    first.input.text = 'UPDATE videos SET title = :value WHERE id = 1;';
    final running = first.runQuery((sql, source, parameters) async => true);
    await tester.pump();
    expect(first.committing.value, isTrue);
    controller.addTab();
    controller.closeTab(0);
    expect(controller.tabs.length, 2);
    pending.complete({'write': true, 'affected_rows': 1, 'rows': [], 'columns': []});
    await running;
    expect(first.result.value?['affected_rows'], 1);
    expect(controller.activeTab.result.value, isNull);
    controller.closeTab(0);
    await tester.pumpAndSettle();
    expect(first.isClosed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Closing a running tab cancels its request and ignores late completion', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    CancelToken? requestToken;
    final controller = Get.put(PageSqleditorController(sources: {'javit.db': '/javit.db'},
      query: (_, request, token) { requestToken = token; return pending.future; }));
    addTearDown(() => Get.reset());
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: PageSqleditorView())));
    final first = controller.activeTab;
    first.input.text = 'SELECT 1;';
    final running = first.runQuery((sql, source, parameters) async => false);
    controller.closeTab(0);
    await tester.pump();
    expect(requestToken!.isCancelled, isTrue);
    expect(first.isClosed, isTrue);
    pending.complete({'rows': [[1]], 'columns': ['value']});
    await running;
    await tester.pumpAndSettle();
    expect(controller.activeTab.result.value, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
