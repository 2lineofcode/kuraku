import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_r18.dart';
import 'package:javit/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:javit/app/modules/home/page_tools/page_tools_view.dart';
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
  Future<List<Map<String, Object?>>> Function(String, List<Object?>)? run;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (run != null) return run!(sql, arguments ?? []);
    final result = await Process.run('python3', ['-c', r'''
import sqlite3, json, sys, runpy
c = sqlite3.connect(':memory:')
c.row_factory = sqlite3.Row
c.executescript("""
CREATE TABLE derived_video(content_id TEXT, dvd_id TEXT, series_id INTEGER, release_date TEXT, title_en TEXT, title_ja TEXT, runtime_mins INTEGER, sample_url TEXT, jacket_full_url TEXT, jacket_thumb_url TEXT);
CREATE TABLE derived_series(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_category(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_actress(id INTEGER, name_romaji TEXT, name_kanji TEXT, name_kana TEXT);
CREATE TABLE derived_video_category(content_id TEXT, category_id INTEGER);
CREATE TABLE derived_video_actress(content_id TEXT, actress_id INTEGER);
CREATE TABLE machine_translation(source_ja TEXT, target_en TEXT);
INSERT INTO derived_series VALUES (1, NULL, '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_category VALUES (1, '', '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_actress VALUES (1, '', '日本語', 'かな'), (2, 'Same name', NULL, NULL), (3, 'Same name', NULL, NULL), (4, 'Empty', NULL, NULL);
INSERT INTO derived_video VALUES
 ('a', 'ABC-123', 1, '2026-01-01', '', '日本語', 120, '', '', ''),
 ('b', 'ABC-124', 2, '2020-01-01', 'Old', '', 60, '', '', ''),
 ('c', 'ABC-125', 1, NULL, 'Unknown date', '', 30, '', '', ''),
 ('d', 'TK-123', 3, '2030-01-01', 'Blocked', '', 30, '', '', ''),
 ('e', 'INVALID', 3, '2030-01-01', 'Invalid', '', 30, '', '', '');
INSERT INTO derived_video_category VALUES ('a',1),('b',2),('c',1),('d',3),('e',3);
INSERT INTO derived_video_actress VALUES ('a',1),('a',2),('b',3),('c',1),('d',4),('e',4);
INSERT INTO machine_translation VALUES ('日本語','Translated title');
""")
before = c.execute('SELECT count(*) FROM derived_video').fetchone()[0]
indexer = runpy.run_path('assets/r18_to_javit.py')['create_catalog_indexes']
indexer(c)
indexer(c)
assert c.execute('SELECT count(*) FROM derived_video').fetchone()[0] == before
q, args = json.loads(sys.argv[1])
if 'summary AS' in q:
    plan = c.execute('EXPLAIN QUERY PLAN ' + q, args).fetchall()
    assert any('idx_dv_advanced_catalog' in row[3] for row in plan), [tuple(row) for row in plan]
print(json.dumps([dict(r) for r in c.execute(q,args)]))
''', jsonEncode([sql, arguments ?? []])]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return (jsonDecode('${result.stdout}') as List).map((row) => Map<String, Object?>.from(row as Map)).toList();
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;
  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbR18 = database..dbMain = database);
  });
  tearDown(Get.reset);

  test('bilingual groups use matching eligibility, dates, IDs and include ensemble videos', () async {
    for (final kind in ['Series', 'Category', 'Actress', 'Year']) {
      final groups = await DBR18.getAdvancedSearchGroups(kind);
      expect(groups.where((row) => row['name_en'] == 'Empty'), isEmpty);
      expect(groups.first['max_release_date'], '2026-01-01');
      for (final group in groups) {
        final videos = await DBR18.getAdvancedSearchVideos(kind, group['id']);
        expect(videos.length, group['video_count']);
      }
      if (kind != 'Year') {
        final jp = await DBR18.getAdvancedSearchGroups(kind, q: '日本語');
        expect(jp.single['id'], 1);
        final videos = await DBR18.getAdvancedSearchVideos(kind, 1);
        expect(videos.first['title'], 'Translated title');
        expect(videos.last['release_date'], isNull);
      }
    }
    final sameName = await DBR18.getAdvancedSearchGroups('Actress', q: 'Same name');
    expect(sameName.map((row) => row['id']), [2, 3]);
    expect(await DBR18.getAdvancedSearchGroups('Year', q: '2020'), hasLength(1));
  });

  testWidgets('catalog rows show bilingual names, counts and latest dates without overflow', (tester) async {
    final controller = Get.put<PageToolsController>(_Tools());
    controller.currentMenuSelected.value = kAdvanceSearch;
    controller.leftList.assignAll([
      {'id': 1, 'name_en': 'English name', 'name_ja': '日本語', 'video_count': 12, 'max_release_date': '2026-01-01'},
    ]);
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: const PageToolsView())));
    await tester.pumpAndSettle();
    expect(find.text('English name', findRichText: true), findsOneWidget);
    expect(find.text('日本語', findRichText: true), findsOneWidget);
    expect(find.text('12 videos · 2026-01-01', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('latest group and selection requests win and active filters apply to new selections', () async {
    final controller = PageToolsController();
    addTearDown(controller.onClose);
    final pending = <Completer<List<Map<String, Object?>>>>[];
    database.run = (sql, args) {
      final task = Completer<List<Map<String, Object?>>>();
      pending.add(task);
      return task.future;
    };
    final first = controller.filterBySeries();
    final second = controller.filterByCategories();
    pending[1].complete([{'id': 2, 'name_en': 'Current'}]);
    await second;
    pending[0].complete([{'id': 1, 'name_en': 'Stale'}]);
    await first;
    expect(controller.leftList.single['name_en'], 'Current');
    final oldSelection = controller.onLeftListTap({'id': 1, 'name_en': 'Old'}, 0);
    final newSelection = controller.onLeftListTap({'id': 2, 'name_en': 'Current'}, 1);
    controller.filter.durationMin.value = 60;
    controller.filter.isFiltered.value = true;
    pending[3].complete([
      {'video_code': 'ABC-123', 'duration': 120, 'release_date': null},
      {'video_code': 'ABC-124', 'duration': 30, 'release_date': ''},
    ]);
    await newSelection;
    pending[2].complete([{'video_code': 'OLD-123'}]);
    await oldSelection;
    expect(controller.rightListFiltered.single['video_code'], 'ABC-123');
    expect(controller.rightListFiltered.single['is_released'], isNull);
    expect(controller.leftListSelectedId.value, '2');
  });
}
