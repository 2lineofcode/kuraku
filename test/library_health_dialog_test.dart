import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/library_health_check.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_library_health.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  bool removed = false;
  List<Object?>? selectedPath;

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where,
      List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expect(table, 'videos');
    expect(where, 'video_path = ? AND is_deleted = 0');
    selectedPath = whereArgs;
    return removed ? [] : [{'id': 'local-video', 'video_path': whereArgs!.single, 'video_code': 'ABC-001'}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(Get.reset);

  for (final locale in ['en', 'id']) {
    testWidgets('health report shows loading, category counts and paths in $locale', (tester) async {
      tester.view.physicalSize = const Size(340, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Get.locale = Locale(locale);
      final check = Completer<List<LibraryHealthIssue>>();
      await tester.pumpWidget(GetMaterialApp(
        translations: AppTranslations(), locale: Locale(locale),
        theme: AppStyle.theme(locale == 'en' ? Brightness.light : Brightness.dark),
        home: Scaffold(body: LibraryHealthDialog(check: check.future)),
      ));
      expect(find.text(locale == 'en' ? 'Checking library…' : 'Memeriksa Library…'), findsOneWidget);
      check.complete([
        (status: LibraryHealthStatus.offlineDrive, path: '/Volumes/Offline', details: []),
        (status: LibraryHealthStatus.incompleteMetadata, path: '/Volumes/Offline/movie.mp4', details: ['title', 'poster']),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(locale == 'en' ? 'Missing files' : 'File hilang'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, locale == 'en' ? 'Incomplete metadata' : 'Metadata belum lengkap'));
      await tester.pumpAndSettle();
      expect(find.text('movie.mp4'), findsOneWidget);
      expect(find.byTooltip('/Volumes/Offline/movie.mp4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('category filters, search and copy path work with a large report', (tester) async {
    Get.locale = const Locale('en');
    final issues = <LibraryHealthIssue>[
      (status: LibraryHealthStatus.offlineDrive, path: '/Volumes/Offline', details: []),
      for (var i = 0; i < 141; i++)
        (status: LibraryHealthStatus.incompleteMetadata, path: '/Volumes/Offline/movie-$i.mp4', details: ['actress']),
      (status: LibraryHealthStatus.missingFile, path: '/local/gone.mp4', details: []),
    ];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(GetMaterialApp(translations: AppTranslations(), locale: const Locale('en'),
      theme: AppStyle.theme(Brightness.dark),
      home: Scaffold(body: LibraryHealthDialog(check: Future.value(issues)))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Offline drives'));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('movie-0.mp4'), findsNothing);
    await tester.tap(find.widgetWithText(AppButton, 'Incomplete metadata'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'movie-140');
    await tester.pumpAndSettle();
    expect(find.text('movie-140.mp4'), findsOneWidget);
    expect(find.text('movie-0.mp4'), findsNothing);
    await tester.tap(find.byTooltip('Copy path'));
    await tester.pumpAndSettle();
    expect(copied, '/Volumes/Offline/movie-140.mp4');
    expect(find.byTooltip('Copied'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), 'nothing-matches');
    await tester.pumpAndSettle();
    expect(find.text('No matching issues.'), findsOneWidget);
    await tester.tap(find.text('Show all'));
    await tester.enterText(find.byType(CupertinoTextField), 'gone.mp4');
    await tester.pumpAndSettle();
    expect(find.byTooltip('/local/gone.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final removed in [false, true]) {
    testWidgets('metadata tap resolves the exact local path, removed=$removed', (tester) async {
      final database = _Database()..removed = removed;
      Get.put<DBService>(_Service()..dbMain = database);
      Videos? opened;
      await tester.pumpWidget(GetMaterialApp(
        theme: AppStyle.theme(Brightness.light), home: Builder(builder: (context) => Scaffold(
          body: TextButton(child: const Text('Check'), onPressed: () => showDialog<void>(context: context,
            builder: (_) => LibraryHealthDialog(
              check: Future.value([
                (status: LibraryHealthStatus.incompleteMetadata, path: '/offline/ABC-001.mp4', details: ['actress']),
              ]),
              openVideoInfo: (video) async => opened = video as Videos,
            ))),
        )),
      ));
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Incomplete metadata'));
      await tester.enterText(find.byType(CupertinoTextField), 'ABC-001');
      await tester.pumpAndSettle();
      await tester.tap(find.text('ABC-001.mp4'));
      await tester.pumpAndSettle();
      expect(database.selectedPath, ['/offline/ABC-001.mp4']);
      if (removed) {
        expect(opened, isNull);
        expect(find.byType(LibraryHealthDialog), findsOneWidget);
        expect(find.text('Video is no longer in the library.'), findsOneWidget);
      } else {
        expect(opened?.id, 'local-video');
        expect(opened?.videoPath, '/offline/ABC-001.mp4');
        expect(find.byType(LibraryHealthDialog), findsOneWidget);
        expect(find.text('Show all'), findsOneWidget);
        expect(find.text('ABC-001'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed checks show an error instead of a healthy report', (tester) async {
    final check = Completer<List<LibraryHealthIssue>>();
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: LibraryHealthDialog(check: check.future))));
    check.completeError(StateError('Database unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Health check failed. Check folder permissions and try again.'), findsOneWidget);
    expect(find.text('No library issues found.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
