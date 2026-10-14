import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/const.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_activity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_relapse.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  void writeInMemory(String key, dynamic value) => values[key] = value;

  @override
  Future<void> write(String key, dynamic value) async => writeInMemory(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  void onClose() {
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
  }
}

class _Settings extends PageSettingsController {
  int refreshes = 0;

  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  Future<void> onRefresh() async {}

  @override
  Future<void> refreshRelapse() async => refreshes++;
}

class _Database implements Database, Transaction {
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) => action(this);

  final rows = <Map<String, Object?>>[];
  final deleted = <List<Object?>>[];
  Completer<void>? insertGate;
  bool failInsert = false;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expectSync(table, 'activity');
    final found = rows.where((row) => row['type'] == whereArgs!.first && (whereArgs.length < 2 || row['content'] == whereArgs[1])).toList()
      ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    return found.take(limit ?? found.length).map(Map<String, Object?>.from).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    if (failInsert) throw StateError('Insert failed');
    if (insertGate != null) await insertGate!.future;
    rows.add({
      'id': values['id'], 'type': kActivityTypeRelapse, 'content': values['occurred_on'],
      'created_at': values['created_at'], 'updated_at': values['updated_at'],
    });
    return rows.length;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    deleted.add(whereArgs!);
    final before = rows.length;
    rows.removeWhere((row) => row['id'] == whereArgs[0] && row['type'] == kActivityTypeRelapse);
    return before - rows.length;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final args = arguments ?? const [];
    if (sql.contains('COUNT(*) AS times')) {
      return [{'times': rows.where((row) => row['type'] == kActivityTypeRelapse && '${row['content']}'.compareTo('${args[0]}') >= 0 && '${row['content']}'.compareTo('${args[1]}') <= 0).length}];
    }
    if (sql.contains('COUNT(*) AS cnt')) {
      return [{'cnt': rows.where((row) => row['type'] == args[0]).length}];
    }
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows.where((row) => row['type'] == args[0])) {
      grouped.putIfAbsent('${row['content']}', () => []).add(row);
    }
    final contents = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return contents
        .map((content) => {
              'id': grouped[content]!.last['id'],
              'type': kActivityTypeRelapse,
              'content': content,
              'times': grouped[content]!.length,
              'created_at': grouped[content]!.map((row) => '${row['created_at']}').reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
              'updated_at': grouped[content]!.last['updated_at'],
            })
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;
  late _Home home;
  late _Settings settings;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayText = today.toStringEx(format: kYMd);
  final oldDayText = today.subtract(const Duration(days: 60)).toStringEx(format: kYMd);

  var rowSequence = 0;
  Map<String, Object?> row(String content, String createdAt) => {
        'id': '${DateTime.now().microsecondsSinceEpoch}-${rowSequence++}',
        'type': kActivityTypeRelapse,
        'content': content,
        'created_at': createdAt,
        'updated_at': createdAt,
      };

  setUp(() {
    database = _Database();
    Get.put(AppSettingService()..pref = _Preferences());
    Get.put<DBService>(_Service()..dbMain = database);
    home = _Home();
    Get.put<HomeController>(home);
    settings = _Settings();
    Get.put<PageSettingsController>(settings);
  });
  tearDown(Get.reset);

  void panelTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        while (Overlayment.count > 0) {
          unawaited(Overlayment.dismissLast());
          await tester.pumpAndSettle();
        }
      }
    });
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();
  }

  panelTest('shows a compact summary, neutral badges and valid date totals', (tester) async {
    database.rows.addAll([
      row(todayText, now.toStringEx()), row(todayText, now.toStringEx()),
      row(oldDayText, '$oldDayText 09:00:00'),
      row('invalid', now.toStringEx()), row('2099-01-01', now.toStringEx()),
    ]);
    await pump(tester);
    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Daily limit reached'), findsOneWidget);
    expect(find.text('Invalid date'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('2×'), 80, scrollable: find.byType(Scrollable));
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('Last recorded Just now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  panelTest('logging saves and refreshes state before closing the panel', (tester) async {
    await pump(tester);
    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    expect(find.text('0 / 2'), findsOneWidget);
    expect(find.text('No records yet'), findsWidgets);
    await tester.tap(find.text('Log relapse'));
    await tester.pumpAndSettle();
    expect(database.rows, hasLength(1));
    expect(find.text('Log relapse'), findsNothing);
    expect(Overlayment.count, 0);
    expect(settings.refreshes, 2);
    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
  });

  panelTest('opening the panel again closes it', (tester) async {
    await pump(tester);
    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
  });

  panelTest('remove and undo preserve the record and update the daily limit', (tester) async {
    final earlier = row(todayText, '$todayText 01:00:00');
    final latest = row(todayText, '$todayText 02:00:00');
    database.rows.addAll([earlier, latest]);
    await pump(tester);
    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    expect(home.isDangerMode.value, isTrue);
    await tester.tap(find.byTooltip('Entry actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove latest entry'));
    await tester.pumpAndSettle();
    expect(database.rows, [earlier]);
    expect(home.isDangerMode.value, isFalse);
    expect(Overlayment.count, 1);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(database.rows, [earlier, latest]);
    expect(home.isDangerMode.value, isTrue);
    expect(find.text('Undo'), findsNothing);
  });
  panelTest('busy state prevents duplicate logs and insert failures stay recoverable', (tester) async {
    await pump(tester);
    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    database.failInsert = true;
    await tester.tap(find.text('Log relapse'));
    await tester.pumpAndSettle();
    expect(database.rows, isEmpty);
    expect(Overlayment.count, 1);
    expect(find.text('Could not complete the request. Please retry.'), findsOneWidget);
    database.failInsert = false;
    database.insertGate = Completer<void>();
    await tester.tap(find.text('Log relapse'));
    await tester.pump();
    expect(Overlayment.count, 1);
    await tester.tap(find.text('Log relapse'));
    database.insertGate!.complete();
    await tester.pumpAndSettle();
    expect(database.rows, hasLength(1));
    expect(Overlayment.count, 0);
    expect(settings.refreshes, 2);
  });

  panelTest('compact panel fits short windows and handles a zero daily limit in both themes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 480);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    settings.tecAppMaxColi.text = '0';
    await settings.saveRelapseLimit();
    addTearDown(() async {
      settings.tecAppMaxColi.text = '2';
      await settings.saveRelapseLimit();
    });
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(GetMaterialApp(theme: ThemeData(brightness: brightness), home: const Scaffold(body: Text('Home'))));
      await tester.pumpAndSettle();
      unawaited(HomePanelRelapse.open());
      await tester.pumpAndSettle();
      expect(find.text('0 / 0'), findsOneWidget);
      expect(find.text('Daily limit reached'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 1);
      expect(tester.takeException(), isNull);
      unawaited(Overlayment.dismissLast());
      await tester.pumpAndSettle();
    }
  });

  test('daily limit changes only on save and zero blocks playback', () async {
    settings.tecAppMaxColi.text = '';
    expect(AppPref.getAppMaxColi(), 2);
    settings.tecAppMaxColi.text = '0';
    await settings.saveRelapseLimit();
    expect(AppPref.getAppMaxColi(), 0);
    expect(home.isDangerMode.value, isTrue);
    settings.tecAppMaxColi.text = '2';
    await settings.saveRelapseLimit();
    expect(home.isDangerMode.value, isFalse);
  });

}
