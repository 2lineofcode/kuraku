import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_r18.dart';
import 'package:javit/app/modules/home/page_explore/page_explore_controller.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  int counts = 0;
  int pages = 0;
  bool failCount = false;
  Completer<List<Map<String, Object?>>>? pendingCount;
  final sizes = <Object?>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('COUNT(DISTINCT v.video_code) AS total')) {
      counts++;
      if (failCount) throw StateError('Count failed');
      return pendingCount?.future ?? [{'total': 1001}];
    }
    if (sql.contains('WITH page AS')) {
      pages++;
      sizes.add(arguments![arguments.length - 2]);
      return List.generate(500, (i) => {'video_code': 'ABC-${i + 100}', 'release_date': '2026-01-01'});
    }
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;
  late PageExploreTab tab;
  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbR18 = database..dbMain = database);
    tab = PageExploreTab(0, pins: <String>{}.obs);
    tab.currentMenuSelected.value = kCategory;
    tab.leftListSelected.value = LeftListModel(name: 'Drama');
  });
  tearDown(() {
    tab.dispose();
    Get.reset();
  });

  test('selection and repeated R18 opens share the in-flight count', () async {
    database.pendingCount = Completer();
    final selection = tab.onLeftListTap(tab.leftListSelected.value);
    final page = tab.onSectionR18Tap();
    expect(database.counts, 1);
    database.pendingCount!.complete([{'total': 1001}]);
    await Future.wait([selection, page]);
    await tab.onSectionR18Tap();
    expect(database.counts, 1);
    expect(database.pages, 2);
    expect(database.sizes, [500, 500]);
    expect(tab.rightListR18TotalVideo.value, 1001);
    expect(tab.hasNextPage.value, isTrue);
  });

  test('cast, selection refresh and database replacement invalidate the count', () async {
    await tab.onLeftListTap(tab.leftListSelected.value);
    await tab.onSectionR18Tap();
    tab.actressMode.value = ActressMode.multi;
    await tab.onSectionR18Tap();
    expect(database.counts, 2);
    await tab.onLeftListTap(tab.leftListSelected.value);
    expect(database.counts, 3);
    final replacement = _Database();
    Get.find<DBService>().dbR18 = replacement;
    await tab.onSectionR18Tap();
    expect(replacement.counts, 1);
  });

  test('failed count is retried on the next R18 open', () async {
    database.failCount = true;
    await tab.onSectionR18Tap();
    expect(database.counts, 1);
    database.failCount = false;
    await tab.onSectionR18Tap();
    expect(database.counts, 2);
    expect(tab.rightListR18TotalVideo.value, 1001);
  });
}
