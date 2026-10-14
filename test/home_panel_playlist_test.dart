import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_playlist.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => (key == '_kFavoriteCoverURL' ? '' : null) as T?;

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

class _Database implements Database {
  final name = 'A very long playlist name that should wrap without overflowing the panel';
  Completer<List<Map<String, Object?>>>? detail;
  Completer<List<Map<String, Object?>>>? favorites;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('SELECT video.*')) return detail?.future ?? [];
    return [{'id': 'p1', 'name': name, 'total': 0}];
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async =>
      where == 'is_deleted = 0 AND (is_favorite = 1)' ? favorites?.future ?? [] : [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('compact playlist navigation handles empty, loading, error and retry states', (tester) async {
    final database = _Database();
    Get.put(AppSettingService()..pref = _Preferences());
    Get.put<DBService>(_Service()..dbMain = database);
    Get.put<HomeController>(_Home());
    try {
      await tester.pumpWidget(GetMaterialApp(theme: AppStyle.theme(Brightness.dark), home: const Scaffold()));
      await tester.pumpAndSettle();
      unawaited(HomePanelPlaylist.open());
      await tester.pumpAndSettle();
      expect(find.text(database.name), findsOneWidget);
      expect(find.text('0 Videos'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Favorite'));
      await tester.pumpAndSettle();
      expect(find.text('Playlist still empty'), findsOneWidget);
      final play = find.byWidgetPredicate((widget) => widget is AppButton && widget.label == 'Play This Playlist');
      expect(tester.widget<AppButton>(play).onPressed, isNull);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      database.favorites = Completer();
      unawaited(HomePanelPlaylist.open());
      await tester.pumpAndSettle();
      expect(find.text('0 Videos'), findsNWidgets(2));
      database.favorites!.complete([{'is_favorite': 1}, {'is_favorite': 1}]);
      await tester.pumpAndSettle();
      expect(find.text('2 Videos'), findsOneWidget);
      expect(find.text('0 Videos'), findsOneWidget);
      await tester.tap(find.text('Favorite'));
      await tester.pumpAndSettle();
      expect(find.text('2 Videos'), findsOneWidget);
      expect(find.text('Video not found'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('2 Videos'), findsOneWidget);

      database.detail = Completer();
      await tester.tap(find.text(database.name));
      await tester.pump();
      expect(tester.widget<AppButton>(play).onPressed, isNull);
      database.detail!.completeError(StateError('Database unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to load playlist.'), findsOneWidget);
      database.detail = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Playlist still empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(Overlayment.count, 0);
    } finally {
      while (Overlayment.count > 0) {
        unawaited(Overlayment.dismissLast());
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
    }
  });
}
