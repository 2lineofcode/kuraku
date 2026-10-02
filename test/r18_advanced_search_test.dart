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
  _Database({this.includeFallback = false});

  final bool includeFallback;
  Future<List<Map<String, Object?>>> Function(String, List<Object?>)? run;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (run != null) return run!(sql, arguments ?? []);
    final result = await Process.run('python3', ['-c', r'''
import sqlite3, json, sys, runpy
c = sqlite3.connect(':memory:')
c.row_factory = sqlite3.Row
c.executescript("""
CREATE TABLE derived_video(content_id TEXT, dvd_id TEXT, series_id INTEGER, release_date TEXT, title_en TEXT, title_ja TEXT, runtime_mins INTEGER, sample_url TEXT, jacket_full_url TEXT, jacket_thumb_url TEXT, service_code TEXT DEFAULT 'digital', maker_id INTEGER DEFAULT 1, label_id INTEGER DEFAULT 1, site_id INTEGER DEFAULT 1, gallery_full_first TEXT, gallery_full_last TEXT);
CREATE TABLE derived_maker(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_label(id INTEGER, name_en TEXT);
CREATE TABLE derived_site(id INTEGER, name TEXT);
CREATE TABLE derived_director(id INTEGER, name_romaji TEXT, name_kana TEXT);
CREATE TABLE derived_video_director(content_id TEXT, director_id INTEGER);
INSERT INTO derived_maker VALUES (1,'Studio',NULL);
INSERT INTO derived_label VALUES (1,'Label');
INSERT INTO derived_site VALUES (1,'FANZA');
INSERT INTO derived_director VALUES (1,'Director',NULL);
CREATE TABLE derived_series(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_category(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_actress(id INTEGER, name_romaji TEXT, name_kanji TEXT, name_kana TEXT);
CREATE TABLE derived_video_category(content_id TEXT, category_id INTEGER);
CREATE TABLE derived_video_actress(content_id TEXT, actress_id INTEGER);
CREATE TABLE machine_translation(source_ja TEXT, target_en TEXT);
INSERT INTO derived_series VALUES (1, NULL, '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_category VALUES (1, '', '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_actress VALUES (1, '', '日本語', 'かな'), (2, 'Same name', NULL, NULL), (3, 'Same name', NULL, NULL), (4, 'Empty', NULL, NULL);
INSERT INTO derived_video(content_id,dvd_id,series_id,release_date,title_en,title_ja,runtime_mins,sample_url,jacket_full_url,jacket_thumb_url) VALUES
 ('a', 'ABC-123', 1, '2026-01-01', '', '日本語', 120, '', '', ''),
 ('b', 'ABC-124', 2, '2020-01-01', 'Old', '', 60, '', '', ''),
 ('c', 'ABC-125', 1, NULL, 'Unknown date', '', 30, '', '', ''),
 ('d', 'TK-123', 3, '2030-01-01', 'Blocked', '', 30, '', '', ''),
 ('e', 'INVALID', 3, '2030-01-01', 'Invalid', '', 30, '', '', '');
INSERT INTO derived_video_category VALUES ('a',1),('b',2),('c',1),('d',3),('e',3);
INSERT INTO derived_video_actress VALUES ('a',1),('a',2),('b',3),('c',1),('d',4),('e',4);
INSERT INTO machine_translation VALUES ('日本語','Translated title');
""")
if sys.argv[2] == 'true':
    c.executescript("""
    INSERT INTO derived_video(content_id,dvd_id,series_id,release_date,title_en,runtime_mins,jacket_thumb_url,service_code) VALUES
      ('n_1541naac066',NULL,1,'2026-05-28','Recovered',120,'naac.jpg','mono'),
      ('n_1541naac066b',NULL,1,'2026-05-28','Variant b',120,'variant.jpg','mono'),
      ('n_1541naac066tk',NULL,1,'2026-05-28','Variant tk',120,'variant.jpg','mono'),
      ('n_1541naac066btk',NULL,1,'2026-05-28','Variant btk',120,'variant.jpg','mono'),
      ('118abp00001','',1,'2025-01-01','Padded',90,'abp.jpg','digital'),
      ('eyan00181',NULL,1,'2026-01-01','Fallback',120,'fallback.jpg','digital'),
      ('eyan181','EYAN-181',1,'2022-05-17','Original',120,'original.jpg','mono'),
      ('h_090cns00003','CNS-03',1,'2026-01-01','Two digits',120,'cns.jpg','digital'),
      ('h_090cns00004',NULL,1,'2026-01-01','Two digits fallback',120,'cns.jpg','digital'),
      ('ebook001',NULL,1,'2026-01-01','Book',120,'book.jpg','ebook'),
      ('tk00001',NULL,1,'2026-01-01','Blocked fallback',120,'blocked.jpg','digital');
    INSERT INTO derived_video_actress VALUES ('n_1541naac066',1),('118abp00001',1);
    INSERT INTO derived_video_category VALUES ('n_1541naac066',2),('118abp00001',2);
    INSERT INTO derived_video_director VALUES ('n_1541naac066',1);
    """)
before = c.execute('SELECT count(*) FROM derived_video').fetchone()[0]
indexer = runpy.run_path('assets/r18_to_javit.py')['create_catalog_indexes']
indexer(c)
indexer(c)
assert c.execute('SELECT count(*) FROM derived_video').fetchone()[0] == before
q, args = json.loads(sys.argv[1])
if 'summary AS' in q:
    plan = c.execute('EXPLAIN QUERY PLAN ' + q, args).fetchall()
    assert any('idx_dv_advanced_codes' in row[3] for row in plan), [tuple(row) for row in plan]
print(json.dumps([dict(r) for r in c.execute(q,args)]))
''', jsonEncode([sql, arguments ?? []]), '$includeFallback']);
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

  test('content IDs recover metadata, compact search, filters and matching catalog counts', () async {
    Get.find<DBService>().dbR18 = _Database(includeFallback: true);
    final video = await DBR18.getVideo(' naac066 ');
    expect(video!['video_code'], 'NAAC-066');
    expect(video['id'], 'n_1541naac066');
    expect((await DBR18.getVideo('EYAN-181'))!['title'], 'Original');
    expect((await DBR18.getVideo('ABP-001'))!['title'], 'Padded');
    expect((await DBR18.getVideo('CNS-04'))!['title'], 'Two digits fallback');
    expect(await DBR18.getVideo('EBOOK-001'), isNull);
    expect(await DBR18.getVideo('NAAC-066B'), isNull);
    expect(await DBR18.getActress('NAAC-066'), hasLength(1));
    expect((await DBR18.getCategory('NAAC-066')).single['category'], 'Older');
    expect((await DBR18.getDirector('NAAC-066'))!['name_romaji'], 'Director');
    expect(await DBR18.getPosterByCodes(['naac066', 'EYAN-181']), {'NAAC-066': 'naac.jpg', 'EYAN-181': 'original.jpg'});
    expect(await DBR18.getCategoriesByVideoCodes(['naac066']), {'NAAC-066': ['Older']});
    for (final query in ['NAAC-066', 'naac066', 'Recovered']) {
      expect((await DBR18.search(query)).single['video_code'], 'NAAC-066');
      expect(await DBR18.getSearchCount(query), 1);
    }
    for (final code in ['NAAC-066', 'naac066']) {
      expect((await DBR18.getByFilter(videoCode: code)).single['video_code'], 'NAAC-066');
      expect(await DBR18.getByFilterCount(videoCode: code), 1);
    }
    expect((await DBR18.search('EYAN-181')).single['video_code'], 'EYAN-181');
    expect(await DBR18.getSearchCount('EYAN-181'), 1);
    expect(await DBR18.search('Blocked fallback'), isEmpty);
    expect(await DBR18.search('Book'), isEmpty);
    for (final kind in ['Series', 'Category', 'Actress', 'Year']) {
      for (final group in await DBR18.getAdvancedSearchGroups(kind)) {
        final videos = await DBR18.getAdvancedSearchVideos(kind, group['id']);
        expect(videos.length, group['video_count']);
      }
    }
    expect(await DBR18.getCountAllVideosByCategory('Older'), (await DBR18.getAllVideosByCategory('Older')).length);
    expect(await DBR18.getCountAllVideosByStudio('Studio'), (await DBR18.getAllVideosByStudio('Studio')).length);
    expect(await DBR18.getCountAllVideosByLabel('Label'), (await DBR18.getAllVideosByLabel('Label')).length);
    expect(await DBR18.getCountAllVideosByActress(1, singleActressMode: false), (await DBR18.getAllVideosByActress(1, singleActressMode: false)).length);
    expect(await DBR18.getCountAllVideosBySeries('%'), (await DBR18.getAllVideosBySeries('%')).length);
    expect(await DBR18.getCountAllVideosBySeries('日本語'), (await DBR18.getAllVideosBySeries('日本語')).length);
    expect(await DBR18.getCountAllVideosByDirector('Director'), (await DBR18.getAllVideosByDirector('Director')).length);
    expect(await DBR18.getCountAllVideosByYear('2026'), (await DBR18.getAllVideosByYear('2026')).length);
    expect(await DBR18.getCountAllVideosByActress(1), (await DBR18.getAllVideosByActress(1)).length);
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
