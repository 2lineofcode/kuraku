import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_translations.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_library.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_library_relocation.dart';
import 'package:javit/app/modules/widgets/widget_controls.dart';
import 'package:javit/app/modules/widgets/widget_style.dart';
import 'package:javit/app/modules/widgets/widget_surfaces.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  List<Map<String, Object?>> libraries = [];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async => libraries;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [{'total': 123456789}];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;

  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
  });
  tearDown(() async {
    while (Overlayment.count > 0) {
      await Overlayment.dismissLast();
    }
    Get.reset();
  });

  Future<void> pump(WidgetTester tester, {bool dark = false, bool narrow = false}) async {
    tester.view.resetPhysicalSize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(narrow ? 300 : 800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GetMaterialApp(
      theme: AppStyle.theme(dark ? Brightness.dark : Brightness.light),
      translations: AppTranslations(), locale: const Locale('en'),
      home: const Scaffold(body: Text('Home')),
    ));
    await tester.pumpAndSettle();
    unawaited(HomePanelLibrary.open());
    await tester.pumpAndSettle();
  }

  testWidgets('empty library has an add action and disables maintenance', (tester) async {
    await pump(tester);
    expect(find.text('No Data'), findsOneWidget);
    expect(find.text('Add New Library'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byWidgetPredicate((widget) => widget is AppButton && widget.label == 'Library Health Check')).onPressed, isNull);
    for (final tooltip in ['Rescan All Folders', 'Repair Metadata from R18']) {
      expect(tester.widget<AppIconButton>(find.byWidgetPredicate((widget) => widget is AppIconButton && widget.tooltip == tooltip)).onPressed, isNull);
    }
    await tester.tap(find.text('Add New Library'));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    expect(find.byType(AppTextField), findsNWidgets(2));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('compact rows handle long names, missing paths and large counts in both themes', (tester) async {
    database.libraries = [
      {'id': 'one', 'alias': 'A very long library name that should truncate cleanly', 'root_folder': '/Volumes/Movies/a/very/long/folder/path', 'total_video': 123456789},
      {'id': 'two', 'alias': 'Missing path', 'root_folder': null, 'total_video': null},
    ];
    for (final dark in [false, true]) {
      await pump(tester, dark: dark, narrow: true);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('/Volumes/Movies/a/very/long/folder/path'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Total Folder: 2'), findsOneWidget);
      expect(find.text('Total Video: 123456789'), findsOneWidget);
      expect(tester.widget<AppIconButton>(find.byWidgetPredicate((widget) => widget is AppIconButton && widget.tooltip == 'Open Folder `Missing path`')).onPressed, isNull);
      await tester.tap(find.text('A very long library name that should truncate cleanly'));
      await tester.pumpAndSettle();
      expect(find.byType(AppTextField), findsNWidgets(2));
      expect(find.text('Total Video: 123456789'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('maintenance actions ask for confirmation and No cancels without running', (tester) async {
    database.libraries = [{'id': 'one', 'alias': 'Movies', 'root_folder': '/movies', 'total_video': 1}];
    for (final action in ['Rescan All Folders', 'Repair Metadata from R18']) {
      await pump(tester);
      await tester.tap(find.byTooltip(action));
      await tester.pumpAndSettle();
      expect(find.byType(AppConfirmDialog), findsOneWidget);
      expect(find.text(action), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(Overlayment.count, 0);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.byType(AppConfirmDialog), findsNothing);
      expect(Overlayment.count, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('editing a library exposes relocation with Apply disabled until a preview exists', (tester) async {
    database.libraries = [{'id': 'one', 'alias': 'Movies', 'root_folder': '/movies', 'total_video': 1}];
    await pump(tester);
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relocate Library'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryRelocationDialog), findsOneWidget);
    expect(tester.widget<AppButton>(find.byWidgetPredicate((widget) => widget is AppButton && widget.label == 'Apply')).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryRelocationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close action dismisses the library panel', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
  });
}
