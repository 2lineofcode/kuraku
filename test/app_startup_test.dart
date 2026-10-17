import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_dependencies.dart';
import 'package:kuraku/app/core/app_startup.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/modules/home/page_sqleditor/page_sqleditor_controller.dart';
import 'package:kuraku/main.dart';

void main() {
  testWidgets('Exit waits for the latest SQL draft and blocks failed saves until retry succeeds', (tester) async {
    addTearDown(Get.reset);
    final pending = Completer<void>();
    var fail = false;
    Map<String, dynamic>? stored;
    final sql = Get.put(PageSqleditorController(sources: {'kuraku.db': '/kuraku.db'}, persistTabs: (value) async {
      await pending.future;
      if (fail) throw StateError('Disk unavailable');
      stored = value;
    }));
    sql.activeTab.input.text = 'SELECT latest_draft;';
    var finished = false;
    final exit = flushBeforeExit().then((allowed) { finished = true; return allowed; });
    await tester.pump();
    expect(finished, isFalse);
    expect(stored, isNull);
    pending.complete();
    expect(await exit, isTrue);
    expect((stored!['tabs'] as List).single['drafts']['kuraku.db'], 'SELECT latest_draft;');
    fail = true;
    sql.activeTab.input.text = 'SELECT unsaved_draft;';
    expect(await flushBeforeExit(), isFalse);
    expect(sql.saveError.value, isNotEmpty);
    fail = false;
    expect(await flushBeforeExit(), isTrue);
    expect(sql.saveError.value, isEmpty);
    expect((stored!['tabs'] as List).single['drafts']['kuraku.db'], 'SELECT unsaved_draft;');
  });

  test('Exit leaves an unopened SQL editor uninitialized', () async {
    addTearDown(Get.reset);
    var created = false;
    Get.lazyPut(() { created = true; return PageSqleditorController(sources: {}); });
    expect(await flushBeforeExit(), isTrue);
    expect(created, isFalse);
  });

  testWidgets('Startup paints while initialization is pending and opens the app once', (tester) async {
    final ready = Completer<void>();
    var calls = 0;
    var appBuilt = false;
    await tester.pumpWidget(AppStartup(
      initialize: () { calls++; return ready.future; },
      child: Builder(builder: (_) {
        appBuilt = true;
        return const MaterialApp(home: Text('Home ready'));
      }),
    ));
    expect(find.text('Opening KuraKu, Please wait...'), findsOneWidget);
    expect(appBuilt, isFalse);
    await tester.pump();
    expect(calls, 1);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Home ready'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('Startup failure stays visible without opening dependent pages', (tester) async {
    await tester.pumpWidget(AppStartup(
      initialize: () async => throw StateError('Database unavailable'),
      child: const MaterialApp(home: Text('Home ready')),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not start KuraKu'), findsOneWidget);
    expect(find.text('Home ready'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GetX lifecycle does not reopen databases', (tester) async {
    addTearDown(Get.reset);
    Get.put(DBService());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Missing playback runtime shows installation guidance before initializing dependent pages', (tester) async {
    await tester.pumpWidget(AppStartup(
      initialize: () async => throw DependencyException(const [DependencyStatus('libmpv', 'In-app playback',
        'Reinstall KuraKu to restore its bundled media libraries.', ready: false)]),
      child: const MaterialApp(home: Text('Home ready')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Install missing dependencies'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Home ready'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
