import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_dependencies.dart';
import 'package:kuraku/app/core/app_startup.dart';
import 'package:kuraku/app/data/database/_init_db.dart';

void main() {
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
