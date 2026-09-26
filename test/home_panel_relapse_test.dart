import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/core/const.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_activity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_relapse.dart';
import 'package:javit/app/modules/home/page_settings/page_settings_controller.dart';
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
  Future<void> onRefresh() async => refreshes++;
}

class _Database implements Database {
  final rows = <Map<String, Object?>>[];
  final deleted = <List<Object?>>[];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expect(table, 'activity');
    final found = rows.where((row) => row['type'] == whereArgs!.first).toList()
      ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    return found.take(limit ?? found.length).map(Map<String, Object?>.from).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    rows.add(Map<String, Object?>.from(values));
    return rows.length;
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    deleted.add(arguments ?? const []);
    final index = rows.indexWhere((row) => row['type'] == arguments![0] && row['content'] == arguments[1]);
    if (index == -1) return 0;
    rows.removeAt(index);
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final args = arguments ?? const [];
    if (sql.contains('COUNT(*) AS times')) {
      return [{'times': rows.where((row) => row['type'] == args[0] && '${row['content']}'.compareTo('${args[1]}') >= 0 && '${row['content']}'.compareTo('${args[2]}') <= 0).length}];
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

  Map<String, Object?> row(String content, String createdAt) => {
        'id': '$content-$createdAt',
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
  tearDown(() async {
    while (Overlayment.count > 0) {
      await Overlayment.dismissLast();
    }
    await Get.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Home'))));
    await tester.pumpAndSettle();
  }

  testWidgets('summarises the week, the month and all time from the aggregated rows', (tester) async {
    database.rows.addAll([
      row(todayText, now.toStringEx()),
      row(todayText, now.toStringEx()),
      row(oldDayText, '$oldDayText 09:00:00'),
    ]);
    await pump(tester);

    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();

    expect(Overlayment.count, 1);
    expect(find.text('Relapse'), findsOneWidget);
    expect(find.text('This Week: 2'), findsOneWidget);
    expect(find.text('This Month: 2'), findsOneWidget);
    expect(find.text('All Time: 3'), findsOneWidget);
    expect(find.text('2 Times'), findsOneWidget);
    expect(find.text('1 Times'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget, reason: 'the newest entry was created right now');
    expect(find.textContaining('Last Transaction: '), findsOneWidget);
    expect(find.text('Last Transaction: -'), findsNothing);
  });

  testWidgets('shows the empty state when nothing was ever recorded', (tester) async {
    await pump(tester);

    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();

    expect(find.text('Still dont have data'), findsOneWidget);
    expect(find.text('All Time: 0'), findsOneWidget);
    expect(find.text('This Week: 0'), findsOneWidget);
    expect(find.text('Last Transaction: -'), findsOneWidget);
    expect(find.text('1 Times'), findsNothing);
  });

  testWidgets('opening the panel again closes it instead of stacking overlays', (tester) async {
    await pump(tester);

    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);

    await HomePanelRelapse.open();
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    expect(find.text('Relapse'), findsNothing);
  });

  testWidgets('the refresh action records a new relapse and refreshes the settings page', (tester) async {
    database.rows.add(row(todayText, now.toStringEx()));
    home.isDangerMode.value = false;
    await pump(tester);

    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Relapse :('));
    await tester.pumpAndSettle();

    expect(database.rows.where((entry) => entry['content'] == todayText), hasLength(2));
    expect(settings.refreshes, 1);
    expect(home.isDangerMode.value, isTrue, reason: 'two relapses today reach the default limit');
    expect(Overlayment.count, 0);
  });

  testWidgets('deleting one record removes a single row for that day and re-evaluates danger mode', (tester) async {
    database.rows.addAll([
      row(todayText, now.toStringEx()),
      row(todayText, now.toStringEx()),
    ]);
    home.isDangerMode.value = true;
    await pump(tester);

    unawaited(HomePanelRelapse.open());
    await tester.pumpAndSettle();
    expect(find.text('2 Times'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete 1 Record'));
    await tester.pumpAndSettle();

    expect(database.rows, hasLength(1));
    expect(database.deleted.single, [kActivityTypeRelapse, todayText]);
    expect(home.isDangerMode.value, isFalse);
    expect(Overlayment.count, 0);
  });
}
