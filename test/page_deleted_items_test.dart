import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/page_tools/page_deleted_items_view.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_view.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Tools extends PageToolsController {
  @override
  Future<void> onRefresh() async {}
}

class _Database implements Database {
  final rows = [
    {'id': 'a', 'video_code': 'ABC-001', 'title': 'First title', 'video_path': '/offline/a.mp4', 'is_deleted': 1},
    {'id': 'b', 'video_code': 'XYZ-002', 'title': 'Second title', 'video_path': '/missing/b.mp4', 'is_deleted': 1},
    {'id': 'c', 'video_code': 'ACTIVE-003', 'video_path': '/local/c.mp4', 'is_deleted': 0},
  ];
  bool failLoad = false;
  bool failRestore = false;
  bool failDelete = false;
  Completer<void>? restoring;
  int writes = 0;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where,
      List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    if (failLoad) throw StateError('Read failed');
    expect(where, 'is_deleted = 1');
    return rows.where((row) => row['is_deleted'] == 1).take(limit ?? rows.length)
      .map((row) => Map<String, Object?>.from(row)).toList();
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs,
      ConflictAlgorithm? conflictAlgorithm}) async {
    writes++;
    await restoring?.future;
    if (failRestore) throw StateError('Write failed');
    final row = rows.singleWhere((row) => row['id'] == whereArgs!.single);
    row['is_deleted'] = 0;
    return 1;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    expect(where, 'id = ? AND is_deleted = 1');
    writes++;
    await restoring?.future;
    if (failDelete) throw StateError('Delete failed');
    final count = rows.length;
    rows.removeWhere((row) => row['id'] == whereArgs!.single && row['is_deleted'] == 1);
    return count - rows.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() { Get.reset(); Get.clearTranslations(); Get.locale = null; });

  Future<void> open(WidgetTester tester, _Database db, {String locale = 'en'}) async {
    Get.put<DBService>(_Service()..dbMain = db);
    await tester.pumpWidget(GetMaterialApp(
      translations: AppTranslations(), locale: Locale(locale),
      theme: AppStyle.theme(Brightness.light),
      home: const Scaffold(body: PageDeletedItemsView()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Deleted Items menu appears only with deleted records and leaves the empty page', (tester) async {
    final db = _Database();
    Get.put<DBService>(_Service()..dbMain = db);
    final controller = Get.put<PageToolsController>(_Tools());
    await tester.pumpWidget(GetMaterialApp(
      translations: AppTranslations(), locale: const Locale('en'),
      theme: AppStyle.theme(Brightness.light), home: const Scaffold(body: PageToolsView()),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Deleted Items'), findsNothing);
    await controller.refreshDeletedItemsMenu();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Deleted Items'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Deleted Items'));
    await tester.pumpAndSettle();
    await DBVideos.restore(Videos(id: 'a'));
    await controller.refreshDeletedItemsMenu();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Deleted Items'), findsOneWidget);
    db.failLoad = true;
    await controller.refreshDeletedItemsMenu();
    expect(controller.currentMenuSelected.value, kDeletedItems);
    expect(controller.menus, contains(kDeletedItems));
    db.failLoad = false;
    await DBVideos.restore(Videos(id: 'b'));
    await controller.refreshDeletedItemsMenu();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Deleted Items'), findsNothing);
    expect(find.byType(PageDeletedItemsView), findsNothing);
    expect(controller.currentMenuSelected.value, kTopLargeFile);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['en', 'id']) {
    testWidgets('deleted items can be searched and restored in $locale', (tester) async {
      final db = _Database();
      await open(tester, db, locale: locale);
      expect(find.text('ABC-001'), findsOneWidget);
      expect(find.text('ACTIVE-003'), findsNothing);
      expect(find.textContaining(locale == 'en' ? 'does not recover a file' : 'tidak dipulihkan'), findsOneWidget);
      for (final query in ['second title', 'xyz-002', '/missing/b.mp4']) {
        await tester.enterText(find.byType(CupertinoTextField), query);
        await tester.pumpAndSettle();
        expect(find.text('XYZ-002'), findsOneWidget);
        expect(find.text('ABC-001'), findsNothing);
      }
      await tester.tap(find.widgetWithText(AppButton, 'Restore record'));
      await tester.pumpAndSettle();
      expect(db.rows[1]['is_deleted'], 0);
      expect(find.text('XYZ-002'), findsNothing);
      await tester.enterText(find.byType(CupertinoTextField), '');
      await tester.pumpAndSettle();
      expect(find.text('ABC-001'), findsOneWidget);
      expect(find.text('/offline/a.mp4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('permanent delete requires confirmation, allows retry and disables conflicting actions', (tester) async {
    final db = _Database();
    await open(tester, db);
    await tester.enterText(find.byType(CupertinoTextField), 'ABC-001');
    await tester.pumpAndSettle();
    Future<void> confirm() async {
      await tester.tap(find.widgetWithText(AppButton, 'Delete permanently'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Files still on disk'), findsOneWidget);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Delete permanently'));
    }
    await tester.tap(find.widgetWithText(AppButton, 'Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Cancel'));
    await tester.pumpAndSettle();
    expect(db.writes, 0);
    db.failDelete = true;
    await confirm();
    await tester.pumpAndSettle();
    expect(find.text('Could not delete the record permanently. Try again.'), findsOneWidget);
    expect(db.rows.any((row) => row['id'] == 'a'), isTrue);
    db.failDelete = false;
    db.restoring = Completer<void>();
    await confirm();
    await tester.pump();
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'Restore record')).onPressed, isNull);
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'Refresh')).onPressed, isNull);
    db.restoring!.complete();
    await tester.pumpAndSettle();
    expect(db.rows.any((row) => row['id'] == 'a'), isFalse);
    expect(find.text('First title'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed load and restore allow retry, pending restore disables buttons', (tester) async {
    final db = _Database()..failLoad = true;
    await open(tester, db);
    expect(find.text('Could not load deleted items. Try again.'), findsOneWidget);
    db.failLoad = false;
    await tester.tap(find.widgetWithText(AppButton, 'Refresh'));
    await tester.pumpAndSettle();
    db.failRestore = true;
    await tester.enterText(find.byType(CupertinoTextField), 'ABC-001');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Restore record'));
    await tester.pumpAndSettle();
    expect(find.text('Could not restore the record. Try again.'), findsOneWidget);
    expect(db.rows[0]['is_deleted'], 1);
    db.failRestore = false;
    db.restoring = Completer<void>();
    await tester.tap(find.widgetWithText(AppButton, 'Restore record'));
    await tester.pump();
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'Restoring…')).onPressed, isNull);
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'Refresh')).onPressed, isNull);
    db.restoring!.complete();
    await tester.pumpAndSettle();
    expect(find.text('First title'), findsNothing);
    expect(db.writes, 2);
    await tester.enterText(find.byType(CupertinoTextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Restore record'));
    await tester.pumpAndSettle();
    expect(find.text('No deleted items.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
