import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_r18.dart';
import 'package:kuraku/app/modules/home/page_download/page_download_search_tab.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_controller.dart';
import 'package:kuraku/app/modules/home/page_tools/page_tools_view.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/modules/widgets/widget_title_translation.dart';
import 'package:kuraku/app/utils/helper_decensor.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Tools extends PageToolsController {
  @override
  Future<void> onRefresh() async {}
}

class _DownloadTab extends PageDownloadSearchTab {
  _DownloadTab(super.id);
  @override
  Future<Set<String>> loadExistingVideoCodes() async => {'ABC-00001'};
  @override
  Future<void> saveHistory(String query) async {}
}

class _Database implements Database {
  _Database({this.includeFallback = false, this.includeBrowseDuplicates = false, this.includePagination = false, this.includeSeriesGaps = false, this.includeNameFallback = false}) {
    addTearDown(_close);
  }

  final bool includeFallback;
  final bool includeBrowseDuplicates;
  final bool includePagination;
  final bool includeSeriesGaps;
  final bool includeNameFallback;
  Future<List<Map<String, Object?>>> Function(String, List<Object?>)? run;

  Future<Process>? _worker;
  late StreamIterator<String> _output;
  late Future<String> _errors;
  Future<void> _pending = Future.value();

  Future<Process> _startWorker() async {
    final worker = await Process.start('python3', ['-B', '-u', '-c', r'''
import sqlite3, json, sys, runpy
c = sqlite3.connect(':memory:')
c.row_factory = sqlite3.Row
c.executescript("""
CREATE TABLE derived_video(content_id TEXT, dvd_id TEXT, series_id INTEGER, release_date TEXT, title_en TEXT, title_ja TEXT, runtime_mins INTEGER, sample_url TEXT, jacket_full_url TEXT, jacket_thumb_url TEXT, service_code TEXT DEFAULT 'digital', maker_id INTEGER DEFAULT 1, label_id INTEGER DEFAULT 1, site_id INTEGER DEFAULT 1, gallery_full_first TEXT, gallery_full_last TEXT);
CREATE TABLE derived_maker(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_label(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_site(id INTEGER, name TEXT);
CREATE TABLE derived_director(id INTEGER, name_romaji TEXT, name_kana TEXT, name_kanji TEXT);
CREATE TABLE derived_video_director(content_id TEXT, director_id INTEGER);
INSERT INTO derived_maker VALUES (1,'Studio',NULL);
INSERT INTO derived_label VALUES (1,'Label',NULL);
INSERT INTO derived_site VALUES (1,'FANZA');
INSERT INTO derived_director VALUES (1,'Director',NULL,NULL);
CREATE TABLE derived_series(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_category(id INTEGER, name_en TEXT, name_ja TEXT);
CREATE TABLE derived_actress(id INTEGER, name_romaji TEXT, name_kanji TEXT, name_kana TEXT);
CREATE TABLE derived_video_category(content_id TEXT, category_id INTEGER);
CREATE TABLE derived_video_actress(content_id TEXT, actress_id INTEGER);
CREATE TABLE machine_translation(source_ja TEXT, target_en TEXT);
INSERT INTO derived_series VALUES (1, 'Cast', '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_category VALUES (1, 'Cast', '日本語'), (2, 'Older', NULL), (3, 'Empty', NULL);
INSERT INTO derived_actress VALUES (1, '', '日本語', 'かな'), (2, 'Same name', NULL, NULL), (3, 'Same name', NULL, NULL), (4, 'Empty', NULL, NULL);
INSERT INTO derived_video(content_id,dvd_id,series_id,release_date,title_en,title_ja,runtime_mins,sample_url,jacket_full_url,jacket_thumb_url) VALUES
 ('a', 'ABC-123', 1, '2026-01-01', '', '日本語', 120, '', '', ''),
 ('b', 'ABC-124', 2, '2020-01-01', 'Old', '', 60, '', '', ''),
 ('c', 'ABC-125', 1, NULL, 'Unknown date', '', 30, '', '', ''),
 ('d', 'TK-123', 3, '2030-01-01', 'Blocked', '', 30, '', '', ''),
 ('e', 'INVALID', 3, '2030-01-01', 'Invalid', '', 30, '', '', ''),
 ('f', '4ABC123', 1, '2026-01-01', 'Invalid rental code', '', 30, '', '', '');
INSERT INTO derived_video_category VALUES ('a',1),('b',2),('c',1),('d',3),('e',3);
INSERT INTO derived_video_actress VALUES ('a',1),('a',2),('b',3),('c',1),('c',1),('d',4),('e',4);
INSERT INTO derived_video_director VALUES ('a',1),('b',1),('c',1);
INSERT INTO machine_translation VALUES ('日本語','Translated title');
""")
if sys.argv[1] == 'true':
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
if sys.argv[3] == 'true':
    c.executescript("""
    INSERT INTO derived_category VALUES (99,'Pagination',NULL);
    WITH RECURSIVE numbers(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM numbers WHERE n<1001)
    INSERT INTO derived_video(content_id,dvd_id,release_date,title_en)
      SELECT 'page-'||n,printf('ABC-%05d',n),'2026-03-01','Page' FROM numbers;
    INSERT INTO derived_video_category SELECT content_id,99 FROM derived_video WHERE content_id LIKE 'page-%';
    """)
    before = c.execute('SELECT count(*) FROM derived_video').fetchone()[0]
if sys.argv[2] == 'true':
    c.executescript("""
    INSERT INTO derived_video(content_id,dvd_id,series_id,release_date,title_en,title_ja,runtime_mins,sample_url,jacket_full_url,jacket_thumb_url)
      VALUES ('new-a','ABC-123',1,'2026-02-01','New original','新しい',180,'trailer','fan','poster');
    INSERT INTO derived_video_category VALUES ('new-a',1),('new-a',1);
    INSERT INTO derived_video_category VALUES ('new-a',2);
    INSERT INTO derived_video_actress VALUES ('new-a',1),('new-a',1);
    INSERT INTO machine_translation VALUES ('新しい','New translated'),('新しい','Another translated');
    INSERT INTO derived_series VALUES (4,'Cast',NULL),(5,'CAST',NULL);
    INSERT INTO derived_video(content_id,dvd_id,series_id,release_date,title_en)
      VALUES ('other-series','ABC-126',4,'2026-04-01','Duplicate series'),
        ('case-series','ABC-127',5,'2026-03-01','Case variant');
    """)
    before = c.execute('SELECT count(*) FROM derived_video').fetchone()[0]
indexer = runpy.run_path('assets/python/r18_importer.py')['create_catalog_indexes']
indexer(c)
indexer(c)
if sys.argv[4] == 'true':
    c.execute("UPDATE derived_video SET series_id=NULL WHERE content_id='b'")
if sys.argv[5] == 'true':
    c.execute("UPDATE derived_series SET name_en='   ' WHERE id=1")
    c.execute("UPDATE derived_series SET name_en=NULL, name_ja='日本語シリーズ' WHERE id=2")
    c.executescript("""
    UPDATE derived_maker SET name_en=NULL, name_ja='スタジオ' WHERE id=1;
    UPDATE derived_label SET name_en='   ', name_ja='レーベル' WHERE id=1;
    UPDATE derived_director SET name_romaji=NULL, name_kanji='監督', name_kana='かんとく' WHERE id=1;
    INSERT INTO derived_maker VALUES (2,'   ','別スタジオ'), (3,NULL,NULL);
    INSERT INTO derived_label VALUES (2,NULL,'別レーベル'), (3,'   ','   ');
    INSERT INTO derived_director VALUES (2,'   ','かな','   '), (3,NULL,NULL,NULL);
    UPDATE derived_video SET maker_id=2, label_id=2 WHERE content_id='b';
    UPDATE derived_video SET maker_id=3, label_id=3 WHERE content_id='c';
    UPDATE derived_video_director SET director_id=2 WHERE content_id='b';
    UPDATE derived_video_director SET director_id=3 WHERE content_id='c';
    """)
assert c.execute('SELECT count(*) FROM derived_video').fetchone()[0] == before
for line in sys.stdin:
    try:
        q, args = json.loads(line)
        if 'summary AS' in q:
            plan = c.execute('EXPLAIN QUERY PLAN ' + q, args).fetchall()
            assert any('idx_dv_advanced_codes' in row[3] for row in plan), [tuple(row) for row in plan]
        print(json.dumps({'rows': [dict(r) for r in c.execute(q,args)]}), flush=True)
    except Exception as error:
        print(json.dumps({'error': str(error)}), flush=True)
c.close()
''', '$includeFallback', '$includeBrowseDuplicates', '$includePagination', '$includeSeriesGaps', '$includeNameFallback']);
    _output = StreamIterator(worker.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    _errors = worker.stderr.transform(utf8.decoder).join();
    return worker;
  }

  Future<void> _close() async {
    if (_worker == null) return;
    await _pending;
    final worker = await _worker!;
    await worker.stdin.close();
    final code = await worker.exitCode.timeout(const Duration(seconds: 5), onTimeout: () async {
      worker.kill();
      return worker.exitCode;
    });
    await _output.cancel();
    expect(code, 0, reason: await _errors);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (run != null) return run!(sql, arguments ?? []);
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    await previous;
    try {
      final worker = await (_worker ??= _startWorker());
      worker.stdin.writeln(jsonEncode([sql, arguments ?? []]));
      if (!await _output.moveNext()) throw StateError('SQLite worker stopped: ${await _errors}');
      final response = jsonDecode(_output.current) as Map<String, dynamic>;
      if (response['error'] != null) throw StateError('${response['error']}');
      return (response['rows'] as List).map((row) => Map<String, Object?>.from(row as Map)).toList();
    } finally {
      done.complete();
    }
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

  final nameBrowsers = [
    ('Series', 'derived_series', ['name_en', 'name_ja'], DBR18.getAllVideosBySeries, DBR18.getCountAllVideosBySeries, ['ABC-123', 'ABC-125']),
    ('Category', 'derived_category', ['name_en', 'name_ja'], DBR18.getAllVideosByCategory, DBR18.getCountAllVideosByCategory, ['ABC-123', 'ABC-125']),
    ('Label', 'derived_label', ['name_en', 'name_ja'], DBR18.getAllVideosByLabel, DBR18.getCountAllVideosByLabel, ['ABC-123', 'ABC-124', 'ABC-125']),
    ('Studio', 'derived_maker', ['name_en', 'name_ja'], DBR18.getAllVideosByStudio, DBR18.getCountAllVideosByStudio, ['ABC-123', 'ABC-124', 'ABC-125']),
    ('Director', 'derived_director', ['name_romaji', 'name_kana', 'name_kanji'], DBR18.getAllVideosByDirector, DBR18.getCountAllVideosByDirector, ['ABC-123', 'ABC-124', 'ABC-125']),
  ];

  test('catalog cards prefer the original DVD over later reissues before sorting and pagination', () async {
    for (final (id, dvd, date, title) in [
      ('gvh00502', null, '2023-01-21', 'Digital'),
      ('gvh502', 'GVH-502', '2023-01-24', 'Original DVD'),
      ('7gvh502', null, '2026-04-20', 'Outlet reissue'),
    ]) {
      await database.rawQuery('''
        INSERT INTO derived_video(content_id, dvd_id, video_code, series_id, release_date, title_en, runtime_mins, jacket_thumb_url)
        VALUES (?, ?, 'GVH-502', 1, ?, ?, 120, ?)
      ''', [id, dvd, date, title, '$id.jpg']);
      await database.rawQuery('INSERT INTO derived_video_actress VALUES (?, 1)', [id]);
      await database.rawQuery('INSERT INTO derived_video_category VALUES (?, 1)', [id]);
      await database.rawQuery('INSERT INTO derived_video_director VALUES (?, 1)', [id]);
    }
    void expectOriginal(Map<String, dynamic> row) {
      expect(row['id'], 'gvh502');
      expect(row['release_date'], '2023-01-24');
      expect(row['title'], 'Original DVD');
      expect(row['poster'], 'gvh502.jpg');
    }
    expectOriginal((await DBR18.getVideo('GVH-502'))!);
    expect((await DBR18.getPosterByCodes(['GVH-502']))['GVH-502'], 'gvh502.jpg');
    for (final (kind, _, _, list, count, _) in nameBrowsers) {
      final name = ['Series', 'Category'].contains(kind) ? 'Cast' : kind;
      final rows = await list(name);
      expectOriginal(rows.singleWhere((row) => row['video_code'] == 'GVH-502'));
      expect(await count(name), rows.length);
      expect(rows.first['video_code'], 'ABC-123', reason: '$kind sorts by the selected release date');
      expectOriginal((await list(name, page: 2, perPage: 1)).single);
    }
    expectOriginal((await DBR18.getAllVideosByActress(1, actressMode: ActressMode.all, page: 2, perPage: 1)).single);
    expectOriginal((await DBR18.getAllVideosByYear('202', page: 2, perPage: 1)).single);
    for (final (kind, id) in [('Series', 1), ('Category', 1), ('Actress', 1), ('Year', '2023')]) {
      final rows = await DBR18.getAdvancedSearchVideos(kind, id);
      expectOriginal(rows.singleWhere((row) => row['video_code'] == 'GVH-502'));
    }
    expectOriginal((await DBR18.search('GVH-502')).single);
    expectOriginal((await DBR18.getByFilter(videoCode: 'GVH-502')).single);
    final filtered = await DBR18.getByFilter(videoCode: 'GVH-502', yearStart: 2026, yearEnd: 2026);
    expect(filtered.single['id'], '7gvh502', reason: 'variant selection must respect active filters');
    expect(await DBR18.getByFilterCount(videoCode: 'GVH-502', yearStart: 2026, yearEnd: 2026), filtered.length);
  });

  test('every named browse type matches all language aliases, including Japanese-only names', () async {
    for (final (kind, table, columns, list, count, expected) in nameBrowsers) {
      for (final column in columns) {
        await database.rawQuery('UPDATE $table SET ${columns.map((name) => '$name = NULL').join(', ')} WHERE id = 1');
        await database.rawQuery('UPDATE $table SET $column = ? WHERE id = 1', ['日本語の名前']);
        for (final query in ['日本語の名前', ' \t日本語の名前\r\n']) {
          expect((await list(query)).map((row) => row['video_code']), expected, reason: '$kind $column');
          expect(await count(query), expected.length, reason: '$kind $column count');
        }
      }
      await database.rawQuery('UPDATE $table SET ${columns.map((name) => '$name = ?').join(', ')} WHERE id = 1', columns.map((name) => 'Alias $name').toList());
      for (final column in columns) {
        expect((await list('Alias $column')).map((row) => row['video_code']), expected, reason: '$kind keeps simultaneous aliases');
        expect(await count('Alias $column'), expected.length, reason: '$kind keeps simultaneous aliases count');
      }
    }
  });

  test('named browse count and list normalize escaped controls and outer whitespace identically', () async {
    for (final (kind, table, columns, list, count, expected) in nameBrowsers) {
      for (final (stored, query) in [
        ('Name\n\n', r'Name\n\n'),
        (r'Name\n\n', 'Name\n\n'),
        (' \t\r\nName\r\n\t ', 'Name'),
        ('Name', r' \t\r\nName\r\n\t '),
        ('\u00a0\u3000Name\u202f', 'Name'),
        ('Name', '\u3000Name\u00a0'),
        ('Part\nOne', r'Part\nOne'),
        (r'Part\rOne', 'Part\rOne'),
        ('Part\tOne', r'Part\tOne'),
        (r'Part\tOne', 'Part\tOne'),
        ('O\'Brien', 'O\'Brien'),
      ]) {
        await database.rawQuery('UPDATE $table SET ${columns.first} = ? WHERE id = 1', [stored]);
        expect((await list(query)).map((row) => row['video_code']), expected, reason: '$kind stored=$stored query=$query');
        expect(await count(query), expected.length, reason: '$kind normalized count');
      }
      await database.rawQuery('UPDATE $table SET ${columns.first} = ? WHERE id = 1', [' \tName\r\n']);
      for (final mode in ActressMode.values) {
        final filtered = mode == ActressMode.multi ? ['ABC-123'] : mode == ActressMode.single ? expected.where((code) => code != 'ABC-123').toList() : expected;
        expect((await list(r'Name\n', actressMode: mode)).map((row) => row['video_code']), filtered, reason: '$kind $mode');
        expect(await count(r'Name\n', actressMode: mode), filtered.length, reason: '$kind $mode count');
        expect((await list(r'Name\n', actressMode: mode, page: 2, perPage: 1)).map((row) => row['video_code']), filtered.skip(1).take(1), reason: '$kind $mode pagination');
      }
      await database.rawQuery('UPDATE $table SET ${columns.first} = ? WHERE id = 1', ['Part\nOne']);
      expect(await list('Part One'), isEmpty, reason: '$kind preserves internal whitespace');
      expect(await count('Part One'), 0, reason: '$kind preserves internal whitespace count');
    }
  });

  test('blank names and SQL-like input cannot accidentally select unnamed catalog groups', () async {
    for (final (kind, table, columns, list, count, _) in nameBrowsers) {
      await database.rawQuery('UPDATE $table SET ${columns.map((name) => '$name = ?').join(', ')} WHERE id = 1', columns.map((_) => ' \t\r\n').toList());
      for (final query in ['', ' \t\r\n', r' \t\r\n', '\' OR 1=1 --']) {
        expect(await list(query), isEmpty, reason: '$kind blank or SQL-like name');
        expect(await count(query), 0, reason: '$kind blank or SQL-like name count');
      }
    }
  });

  test('decensored Explore series and category names resolve the original catalog spelling', () async {
    for (final (_, table, columns, list, count, expected) in nameBrowsers.take(2)) {
      await database.rawQuery('UPDATE $table SET ${columns.first} = ? WHERE id = 1', ['S******n']);
      final displayName = HelperDecensor.decensor('S******n');
      expect(displayName, 'Shotacon');
      final query = HelperDecensor.censored(displayName);
      expect(query, 'S******n');
      expect((await list(query)).map((row) => row['video_code']), expected);
      expect(await count(query), expected.length);
    }
  });

  test('year counts and lists trim padded input before filtering and pagination', () async {
    for (final mode in ActressMode.values) {
      final expected = mode == ActressMode.multi ? ['ABC-123'] : mode == ActressMode.single ? ['ABC-124'] : ['ABC-123', 'ABC-124'];
      expect((await DBR18.getAllVideosByYear(' \t202\r\n', actressMode: mode)).map((row) => row['video_code']), expected);
      expect(await DBR18.getCountAllVideosByYear(' \t202\r\n', actressMode: mode), expected.length);
      expect((await DBR18.getAllVideosByYear(' 202 ', actressMode: mode, page: 2, perPage: 1)).map((row) => row['video_code']), expected.skip(1).take(1));
    }
  });

  test('normalized catalog lookups resolve metadata once and use indexed group matches', () async {
    final execution = _Database(includePagination: true);
    for (final sql in [
      'CREATE INDEX idx_derived_video_label_id ON derived_video(label_id)',
      'CREATE INDEX idx_derived_video_maker_id ON derived_video(maker_id)',
      'CREATE INDEX idx_dvc_category_content ON derived_video_category(category_id, content_id)',
      'CREATE INDEX idx_dvd_director_director_id ON derived_video_director(director_id)',
      "UPDATE derived_video SET label_id = 100 + rowid, maker_id = 100 + rowid WHERE content_id LIKE 'page-%'",
      "UPDATE derived_video_category SET category_id = 100 + (SELECT rowid FROM derived_video WHERE derived_video.content_id = derived_video_category.content_id) WHERE content_id LIKE 'page-%'",
      "INSERT INTO derived_video_director SELECT content_id, 100 + rowid FROM derived_video WHERE content_id LIKE 'page-%'",
      "INSERT INTO derived_label SELECT 100 + rowid, 'Distractor', NULL FROM derived_video WHERE content_id LIKE 'page-%'",
      "INSERT INTO derived_maker SELECT 100 + rowid, 'Distractor', NULL FROM derived_video WHERE content_id LIKE 'page-%'",
      "INSERT INTO derived_category SELECT 100 + rowid, 'Distractor', NULL FROM derived_video WHERE content_id LIKE 'page-%'",
      "INSERT INTO derived_director SELECT 100 + rowid, 'Distractor', NULL, NULL FROM derived_video WHERE content_id LIKE 'page-%'",
      'ANALYZE',
    ]) {
      await execution.rawQuery(sql);
    }
    for (final (kind, _, _, list, count, expected) in nameBrowsers.skip(1)) {
      final (alias, key) = switch (kind) {
        'Category' => ('c', 'category_id'),
        'Label' => ('l', 'label_id'),
        'Studio' => ('m', 'maker_id'),
        _ => ('d', 'director_id'),
      };
      var checkedQueries = 0;
      database.run = (sql, args) async {
        final plan = await execution.rawQuery('EXPLAIN QUERY PLAN $sql', args);
        final details = plan.map((row) => row['detail'] as String).toList();
        final metadata = plan.singleWhere((row) => RegExp('^(SCAN|SEARCH) $alias(?: |\$)').hasMatch(row['detail'] as String));
        var ancestor = metadata;
        while (ancestor['parent'] != 0 && !(ancestor['detail'] as String).startsWith('LIST SUBQUERY')) {
          ancestor = plan.singleWhere((row) => row['id'] == ancestor['parent']);
        }
        expect(ancestor['detail'], startsWith('LIST SUBQUERY'), reason: '$kind must normalize metadata once: $details');
        expect(details.any((detail) => detail.startsWith('SEARCH ') && detail.contains('USING ') && detail.contains('($key=?)')), isTrue,
          reason: '$kind must find matching group rows through an index: $details');
        checkedQueries++;
        return execution.rawQuery(sql, args);
      };
      final query = kind == 'Category' ? 'Cast' : kind;
      expect(await count(query), expected.length);
      expect((await list(query, perPage: 1)).single['video_code'], expected.first);
      expect(checkedQueries, 2);
    }
  });

  test('SQLite workers serialize queries, recover from errors and isolate fixtures', () async {
    await database.rawQuery('CREATE TEMP TABLE worker_state(value INTEGER)');
    await database.rawQuery('INSERT INTO worker_state VALUES (?)', [42]);
    final rows = await Future.wait([
      database.rawQuery('SELECT value FROM worker_state'),
      database.rawQuery('SELECT ? AS value', [7]),
    ]);
    expect(rows.map((result) => result.single['value']), [42, 7]);
    await expectLater(database.rawQuery('SELECT * FROM missing_table'), throwsStateError);
    expect((await database.rawQuery('SELECT value FROM worker_state')).single['value'], 42);
    final isolated = _Database();
    expect((await isolated.rawQuery('SELECT count(*) AS total FROM sqlite_temp_master')).single['total'], 0);
  });

  test('video info uses Japanese series names when English is null or blank', () async {
    expect((await DBR18.getVideo('ABC-123'))!['series'], 'Cast');
    database = _Database(includeNameFallback: true);
    Get.find<DBService>().dbR18 = database;
    expect((await DBR18.getVideo('ABC-123'))!['series'], '日本語');
    expect((await DBR18.getVideo('ABC-124'))!['series'], '日本語シリーズ');
    database = _Database(includeSeriesGaps: true);
    Get.find<DBService>().dbR18 = database;
    expect((await DBR18.getVideo('ABC-124'))!['series'], isNull);
  });

  test('metadata names prefer English or Romaji and fall back to Japanese', () async {
    final original = (await DBR18.getVideo('ABC-123'))!;
    expect(original['label'], 'Label');
    expect(original['studio'], 'Studio');
    expect((await DBR18.getDirector('ABC-123'))!['director'], 'Director');
    Get.find<DBService>().dbR18 = _Database(includeNameFallback: true);
    for (final (code, label, studio, director) in [
      ('ABC-123', 'レーベル', 'スタジオ', '監督'),
      ('ABC-124', '別レーベル', '別スタジオ', 'かな'),
      ('ABC-125', null, null, null),
    ]) {
      final video = (await DBR18.getVideo(code))!;
      expect(video['label'], label);
      expect(video['studio'], studio);
      expect((await DBR18.getDirector(code))!['director'], director);
    }
  });

  test('Advanced Search enriches read-only SQLite rows without mutating them', () async {
    final row = Map<String, Object?>.unmodifiable({'video_code': 'ABC-123', 'title': 'Selected video', 'duration': 120});
    database.run = (sql, args) async => List<Map<String, Object?>>.unmodifiable(
      sql.contains('cat.name_en AS category')
        ? [Map<String, Object?>.unmodifiable({'video_code': 'ABC-123', 'category': 'Cast'})]
        : [row]);
    final videos = await DBR18.getAdvancedSearchVideos('Series', 1);
    expect(videos.single['categories'], ['Cast']);
    expect(row.containsKey('categories'), isFalse);
    final controller = PageToolsController();
    addTearDown(controller.onClose);
    controller.currentFilterBy.value = 'Series';
    controller.filter.categoriesSelected.assignAll(['Cast']);
    await controller.onLeftListTap({'id': 1, 'name_en': 'Series'}, 0);
    expect(controller.status.isSuccess, isTrue);
    expect(controller.rightListFiltered.single['video_code'], 'ABC-123');
    expect(controller.rightListFiltered.single['categories'], ['Cast']);
  });

  test('Advanced Search carries categories into local filters and resets them', () async {
    final controller = PageToolsController();
    addTearDown(controller.onClose);
    final videos = [...await DBR18.getAdvancedSearchVideos('Series', 1), ...await DBR18.getAdvancedSearchVideos('Series', 2)];
    expect(videos.firstWhere((video) => video['video_code'] == 'ABC-123')['categories'], ['Cast']);
    expect(videos.firstWhere((video) => video['video_code'] == 'ABC-124')['categories'], ['Older']);
    controller.rightList.assignAll(videos);
    controller.filter.categoriesSelected.assignAll(['Older']);
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered.map((video) => video['video_code']), ['ABC-124']);
    controller.filter.categoriesSelected.assignAll(['Cast', 'Older']);
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered, hasLength(3));
    controller.filter.categoriesSelected.assignAll(['Unknown']);
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered, isEmpty);
    await controller.clearAdvancedFilters();
    expect(controller.filter.categoriesSelected, isEmpty);
    expect(controller.rightListFiltered, hasLength(3));
    Get.find<DBService>().dbR18 = _Database(includeBrowseDuplicates: true);
    final variants = await DBR18.getAdvancedSearchVideos('Series', 1);
    expect(variants.firstWhere((video) => video['video_code'] == 'ABC-123')['categories'], ['Cast', 'Older']);
    final uncategorized = await DBR18.getAdvancedSearchVideos('Series', 4);
    expect(uncategorized.single['categories'], isEmpty);
  });

  test('Explore and Advanced Search count the same valid series videos', () async {
    final advanced = await DBR18.getAdvancedSearchVideos('Series', 1);
    for (final mode in [ActressMode.all, ActressMode.single, ActressMode.multi]) {
      final rows = await DBR18.getAllVideosBySeries('Cast', actressMode: mode);
      expect(await DBR18.getCountAllVideosBySeries('Cast', actressMode: mode), rows.length);
      expect(rows.map((row) => row['video_code']), isNot(contains('4ABC123')));
      if (mode == ActressMode.all) expect(rows.map((row) => row['video_code']), advanced.map((row) => row['video_code']));
    }
  });

  test('series lists and counts include duplicate names and case-insensitive matches', () async {
    Get.find<DBService>().dbR18 = _Database(includeBrowseDuplicates: true);
    final rows = await DBR18.getAllVideosBySeries('cast');
    expect(rows.map((row) => row['video_code']), ['ABC-126', 'ABC-127', 'ABC-123', 'ABC-125']);
    expect(await DBR18.getCountAllVideosBySeries('cast'), rows.length);
  });

  test('paged search aggregates matching variants without leaking excluded metadata', () async {
    Get.find<DBService>().dbR18 = _Database(includeBrowseDuplicates: true);
    final rows = await DBR18.search('ABC-123');
    expect(rows, hasLength(1));
    expect(rows.single['categories'].toString().split(','), unorderedEquals(['Cast', 'Older']));
    expect(rows.single['actresses'], contains('Same name'));
    final duration = await DBR18.getByFilter(videoCode: 'ABC-123', durationMin: 180);
    expect(duration.single['actresses'], isNot(contains('Same name')));
    expect(duration.single['duration'], 180);
    final old = await DBR18.getByFilter(videoCode: 'ABC-123', durationMax: 120);
    expect(old.single['categories'], 'Cast');
    expect(old.single['id'], 'a');
    expect(await DBR18.getByFilterCount(videoCode: 'ABC-123', durationMax: 120), old.length);
  });

  test('500-row pages keep all videos when release dates are tied', () async {
    Get.find<DBService>().dbR18 = _Database(includePagination: true);
    final codes = <String>[];
    for (var page = 1; page <= 3; page++) {
      final rows = await DBR18.getAllVideosByCategory('Pagination', perPage: 500, page: page);
      expect(rows.length, page < 3 ? 500 : 1);
      codes.addAll(rows.map((row) => row['video_code'] as String));
    }
    expect(codes, List.generate(1001, (i) => 'ABC-${(i + 1).toString().padLeft(5, '0')}'));
    expect(await DBR18.getCountAllVideosByCategory('Pagination'), codes.length);
  });

  testWidgets('Download database search and filter pages keep every boundary video', (tester) async {
    Get.find<DBService>().dbR18 = _Database(includePagination: true);
    final tab = _DownloadTab(1);
    addTearDown(tab.dispose);
    await tester.pumpWidget(MaterialApp(home: ListView.builder(
      controller: tab.scrollController, itemCount: 1000, itemExtent: 50,
      itemBuilder: (_, index) => Text('$index'),
    )));
    for (final query in ['Page', '']) {
      tab.filter.categoriesSelected.assignAll(['Pagination']);
      await tester.runAsync(() => tab.onSearch(query));
      expect(tab.totalResults.value, 1001);
      expect(tab.allVideos.length, 200);
      for (var page = 2; page <= 6; page++) {
        tab.scrollController.jumpTo(0);
        await tester.runAsync(() async {
          tab.scrollController.jumpTo(tab.scrollController.position.maxScrollExtent);
          await Future<void>(() async {
            while (tab.isLoadingMore.value) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }).timeout(const Duration(seconds: 10));
        });
        expect(tab.currentPage.value, page);
      }
      expect(tab.allVideos.map((video) => video.videoCode),
        List.generate(1001, (i) => 'ABC-${(i + 1).toString().padLeft(5, '0')}'));
      expect(tab.hasNextPage.value, isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('browse pages deduplicate codes and links before reading translated metadata', () async {
    Get.find<DBService>().dbR18 = _Database(includeBrowseDuplicates: true);
    final rows = await DBR18.getAllVideosByCategory('Cast', actressMode: ActressMode.all, perPage: 1);
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'new-a');
    expect(rows.single['video_code'], 'ABC-123');
    expect(rows.single['release_date'], '2026-02-01');
    expect(rows.single['title'], isIn(['New translated', 'Another translated']));
    expect(rows.single['duration'], 180);
    expect(rows.single['trailer'], 'trailer');
    expect(rows.single['fan_art'], 'fan');
    expect(rows.single['poster'], 'poster');
    expect(rows.single.keys, unorderedEquals(['id', 'video_code', 'release_date', 'title', 'duration', 'trailer', 'fan_art', 'poster', 'actress_count', 'series']));
    expect(await DBR18.getCountAllVideosByCategory('Cast'), 2);
    expect((await DBR18.getAllVideosByCategory('Cast', page: 2, perPage: 1)).single['video_code'], 'ABC-125');
  });

  test('actress cast modes filter real SQL results with matching counts and pagination', () async {
    for (final mode in ActressMode.values) {
      final videos = await DBR18.getAllVideosByActress(1, actressMode: mode);
      final expected = switch (mode) {
        ActressMode.all => ['ABC-123', 'ABC-125'],
        ActressMode.single => ['ABC-125'],
        ActressMode.multi => ['ABC-123'],
      };
      expect(videos.map((video) => video['video_code']), expected);
      expect(await DBR18.getCountAllVideosByActress(1, actressMode: mode), expected.length);
      expect(await DBR18.getAllVideosByActress(99, actressMode: mode), isEmpty);
      expect(await DBR18.getCountAllVideosByActress(99, actressMode: mode), 0);
    }
    expect((await DBR18.getAllVideosByActress(1, actressMode: ActressMode.all, page: 2, perPage: 1)).single['video_code'], 'ABC-125');
    expect(await DBR18.getAllVideosByActress(1, actressMode: ActressMode.multi, page: 2, perPage: 1), isEmpty);
  });

  test('shared cast and series filters agree across SQL results, counts and pagination', () async {
    Get.find<DBService>().dbR18 = _Database(includeSeriesGaps: true);
    for (final mode in ActressMode.values) {
      for (final onlySeries in [false, true]) {
        final expected = switch (mode) {
          ActressMode.all => onlySeries ? ['ABC-123'] : ['ABC-123', 'ABC-124'],
          ActressMode.single => onlySeries ? <String>[] : ['ABC-124'],
          ActressMode.multi => ['ABC-123'],
        };
        final rows = await DBR18.getByFilter(actressMode: mode, onlySeries: onlySeries);
        expect(rows.map((row) => row['video_code']), expected);
        expect(await DBR18.getByFilterCount(actressMode: mode, onlySeries: onlySeries), expected.length);
        expect((await DBR18.search('ABC', actressMode: mode, onlySeries: onlySeries)).map((row) => row['video_code']), expected);
        expect(await DBR18.getSearchCount('ABC', actressMode: mode, onlySeries: onlySeries), expected.length);
        expect((await DBR18.search('', actressMode: mode, onlySeries: onlySeries)).map((row) => row['video_code']), expected);
        expect(await DBR18.getSearchCount('', actressMode: mode, onlySeries: onlySeries), expected.length);
        expect((await DBR18.getByFilter(actressMode: mode, onlySeries: onlySeries, page: 2, perPage: 1))
          .map((row) => row['video_code']), expected.skip(1));
      }
    }
    final rows = await DBR18.getByFilter();
    expect(rows.first['actress_count'], 2);
    expect(rows.first['series'], 'Cast');
    expect(rows.last['actress_count'], 1);
    expect(rows.last['series'], isNull);
  });

  test('every R18 browse type filters cast before counting and pagination', () async {
    for (final (name, list, count, all, solo) in [
      ('Category', (ActressMode mode, int page, int size) => DBR18.getAllVideosByCategory('Cast', actressMode: mode, page: page, perPage: size), (ActressMode mode) => DBR18.getCountAllVideosByCategory('Cast', actressMode: mode), ['ABC-123', 'ABC-125'], ['ABC-125']),
      ('Series', (ActressMode mode, int page, int size) => DBR18.getAllVideosBySeries('Cast', actressMode: mode, page: page, perPage: size), (ActressMode mode) => DBR18.getCountAllVideosBySeries('Cast', actressMode: mode), ['ABC-123', 'ABC-125'], ['ABC-125']),
      ('Series wildcard', (ActressMode mode, int page, int size) => DBR18.getAllVideosBySeries('C%', actressMode: mode, page: page, perPage: size), (ActressMode mode) => DBR18.getCountAllVideosBySeries('C%', actressMode: mode), ['ABC-123', 'ABC-125'], ['ABC-125']),
      ('Label', (ActressMode mode, int page, int size) => DBR18.getAllVideosByLabel('Label', actressMode: mode, page: page, perPage: size), (ActressMode mode) => DBR18.getCountAllVideosByLabel('Label', actressMode: mode), ['ABC-123', 'ABC-124', 'ABC-125'], ['ABC-124', 'ABC-125']),
      ('Studio', (ActressMode mode, int page, int size) => DBR18.getAllVideosByStudio('Studio', actressMode: mode, page: page, perPage: size), (ActressMode mode) => DBR18.getCountAllVideosByStudio('Studio', actressMode: mode), ['ABC-123', 'ABC-124', 'ABC-125'], ['ABC-124', 'ABC-125']),
      ('Director', (ActressMode mode, int page, int size) => DBR18.getAllVideosByDirector('Director', actressMode: mode, page: page, perPage: size), (ActressMode mode) => DBR18.getCountAllVideosByDirector('Director', actressMode: mode), ['ABC-123', 'ABC-124', 'ABC-125'], ['ABC-124', 'ABC-125']),
      ('Year', (ActressMode mode, int page, int size) => DBR18.getAllVideosByYear('202', actressMode: mode, page: page, perPage: size), (ActressMode mode) => DBR18.getCountAllVideosByYear('202', actressMode: mode), ['ABC-123', 'ABC-124'], ['ABC-124']),
    ]) {
      for (final mode in ActressMode.values) {
        final expected = switch (mode) {
          ActressMode.all => all,
          ActressMode.single => solo,
          ActressMode.multi => ['ABC-123'],
        };
        final videos = await list(mode, 1, 100);
        expect(videos.map((video) => video['video_code']), expected, reason: '$name $mode');
        expect(await count(mode), expected.length, reason: '$name $mode count');
        expect((await list(mode, 2, 1)).map((video) => video['video_code']), expected.skip(1).take(1), reason: '$name $mode pagination');
      }
    }
  });

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
    expect(await DBR18.getCountAllVideosByActress(1, actressMode: ActressMode.all), (await DBR18.getAllVideosByActress(1, actressMode: ActressMode.all)).length);
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
    // FlutterListView leaves debugVisitOnstageChildren empty; verify actual hit testing instead.
    expect(find.text('English name', skipOffstage: false).hitTestable(), findsOneWidget);
    expect(find.text('日本語', skipOffstage: false).hitTestable(), findsOneWidget);
    expect(find.text('12 videos · 2026-01-01', skipOffstage: false).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('large catalog scrollbar jumps build only viewport rows and keep bilingual rows visible', (tester) async {
    final controller = Get.put<PageToolsController>(_Tools());
    controller.currentMenuSelected.value = kAdvanceSearch;
    controller.leftList.assignAll(List.generate(68721, (index) => {
      'id': index, 'name_en': 'Series $index', 'name_ja': '日本語 $index',
      'video_count': 12, 'max_release_date': '2026-01-01',
    }));
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rowBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is InkWell) rowBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(body: const PageToolsView()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Series 0', skipOffstage: false).hitTestable(), findsOneWidget);
    expect(rowBuilds, lessThan(100));
    final scroll = controller.leftListScrollController.value;
    for (final fraction in [0.95, 0.1, 1.0, 0.0]) {
      rowBuilds = 0;
      scroll.jumpTo(scroll.position.maxScrollExtent * fraction);
      await tester.pumpAndSettle();
      expect(rowBuilds, lessThan(100), reason: 'A scrollbar jump must not build intervening catalog rows');
      expect(find.byType(InkWell, skipOffstage: false).evaluate().length, lessThan(100));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Series 0', skipOffstage: false).hitTestable(), findsOneWidget);
    scroll.jumpTo(1);
    await tester.pump();
    final listRect = tester.getRect(find.byWidgetPredicate((widget) => widget is ScrollView && widget.controller == scroll));
    rowBuilds = 0;
    await tester.dragFrom(Offset(listRect.right - 4, listRect.top + 10), Offset(0, listRect.height * .85), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(scroll.position.maxScrollExtent * .8));
    expect(rowBuilds, lessThan(100));
    expect(tester.takeException(), isNull);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    controller.leftList.assignAll([
      {'id': 999999, 'name_en': 'Filtered result', 'name_ja': '日本語', 'video_count': 1, 'max_release_date': null},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Filtered result', skipOffstage: false).hitTestable(), findsOneWidget);
    expect(find.text('Series 0', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('latest group and selection requests win and active filters apply to new selections', () async {
    final controller = PageToolsController();
    addTearDown(controller.onClose);
    final pending = <Completer<List<Map<String, Object?>>>>[];
    database.run = (sql, args) {
      if (sql.contains('cat.name_en AS category')) return Future.value(<Map<String, Object?>>[]);
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

  test('result search, release, library and duration filters combine and reset without losing selection', () async {
    final controller = PageToolsController();
    addTearDown(controller.onClose);
    controller.leftListSelectedId.value = '1';
    controller.rightList.assignAll([
      {'video_code': 'ABC-123', 'title': 'First title', 'release_date': '2020-01-01', 'is_released': true, 'match': true, 'duration': 120},
      {'video_code': 'ABC-124', 'title': 'Second title', 'release_date': '2021-01-01', 'is_released': true, 'match': false, 'duration': 30},
      {'video_code': 'ABC-125', 'title': 'Future title', 'release_date': '2099-01-01', 'is_released': false, 'match': false, 'duration': 90},
      {'video_code': 'ABC-126', 'title': 'Undated', 'release_date': null, 'is_released': null, 'match': false},
    ]);
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered.map((item) => item['video_code']), ['ABC-124', 'ABC-123', 'ABC-125', 'ABC-126']);
    controller.resultQuery.value = 'FIRST';
    controller.releaseFilter.value = 'released';
    controller.libraryFilter.value = 'owned';
    controller.filter.durationMin.value = 60;
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered.single['video_code'], 'ABC-123');
    expect(controller.hasAdvancedFilters, isTrue);
    controller.resultQuery.value = 'abc-123';
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered, hasLength(1));
    controller.libraryFilter.value = 'missing';
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered, isEmpty);
    await controller.clearAdvancedFilters();
    expect(controller.hasAdvancedFilters, isFalse);
    expect(controller.leftListSelectedId.value, '1');
    expect(controller.rightListFiltered, hasLength(4));
    controller.releaseFilter.value = 'upcoming';
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered.single['video_code'], 'ABC-125');
    controller.releaseFilter.value = 'all';
    controller.resultSort.value = 'oldest';
    await controller.applyAdvancedFilters();
    expect(controller.rightListFiltered.map((item) => item['video_code']), ['ABC-123', 'ABC-124', 'ABC-125', 'ABC-126']);
  });

  testWidgets('live group search waits for typing to stop and cancels pending work on a group change', (tester) async {
    final controller = PageToolsController();
    addTearDown(controller.onClose);
    var requests = 0;
    database.run = (sql, args) async {
      requests++;
      return [{'id': 1, 'name_en': 'English', 'search_text': 'English 日本語'}];
    };
    controller.searchAdvancedGroups('eng');
    await tester.pump(const Duration(milliseconds: 100));
    controller.searchAdvancedGroups('日本語');
    await tester.pump(const Duration(milliseconds: 249));
    expect(requests, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(requests, 1);
    expect(controller.leftList.single['id'], 1);
    controller.searchAdvancedGroups('missing');
    await controller.filterByCategories();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.currentFilterBy.value, 'Category');
    expect(controller.leftList.single['id'], 1);
    controller.searchAdvancedGroups('missing');
    await controller.onReset();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.leftList, isEmpty);
  });

  testWidgets('advanced results fit desktop widths in both themes and expose clear status and controls', (tester) async {
    final controller = Get.put<PageToolsController>(_Tools());
    controller.currentMenuSelected.value = kAdvanceSearch;
    controller.leftListSelected.value = 'A selected series with a long name';
    controller.leftListSelectedId.value = '1';
    controller.rightList.assignAll([
      {'video_code': 'ABC-123', 'title': 'A long title that should wrap safely in a narrow card', 'fan_art': '', 'release_date': '2020-01-01', 'is_released': true, 'match': true, 'duration': 120, 'categories': ['Cast']},
      {'video_code': 'ABC-124', 'title': 'Upcoming title', 'fan_art': '', 'release_date': '2099-01-01', 'is_released': false, 'match': false, 'duration': 90, 'categories': ['Older']},
    ]);
    controller.filter.categories.assignAll(['Cast', 'Older']);
    await controller.applyAdvancedFilters();
    controller.change(200, status: RxStatus.success());
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [700.0, 1000.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(GetMaterialApp(
        theme: ThemeData.light(), darkTheme: ThemeData.dark(),
        home: Scaffold(body: const PageToolsView()),
      ));
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        Get.changeThemeMode(theme);
        await tester.pumpAndSettle();
        expect(find.text('2 of 2 videos'), findsOneWidget);
        final translation = tester.widget<TitleTranslation>(find.byType(TitleTranslation));
        expect(translation.title, controller.leftListSelected.value);
        expect(find.descendant(of: find.byType(TitleTranslation), matching: find.text(controller.leftListSelected.value)), findsOneWidget);
        expect(find.byType(AppDropdown<String>), findsNWidgets(4));
        expect(find.byType(PopupMenuButton<String>), findsNothing);
        expect(find.text('In Library'), findsOneWidget);
        expect(find.text('Upcoming'), findsOneWidget);
        expect(find.byTooltip('Open trailer'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      }
    }
    final search = find.byWidgetPredicate((widget) => widget is EditableText && widget.controller == controller.tecResultSearch);
    await tester.enterText(search, 'upcoming');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 videos'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 videos'), findsOneWidget);
    await tester.tap(find.byTooltip('Release'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Upcoming'));
    await tester.pumpAndSettle();
    expect(controller.releaseFilter.value, 'upcoming');
    expect(find.text('1 of 2 videos'), findsOneWidget);
    await tester.tap(find.byTooltip('More filters: video code, categories, year and duration'));
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsOneWidget);
    final categoryField = find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.placeholder == 'Search and add categories...');
    await tester.enterText(categoryField, 'Older');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Older').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.filter.categoriesSelected, isEmpty);
    await tester.tap(find.byTooltip('More filters: video code, categories, year and duration'));
    await tester.pumpAndSettle();
    await tester.enterText(categoryField, 'Older');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Older').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-duration-min')), '100');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 2 videos'), findsOneWidget);
    expect(controller.filter.categoriesSelected, ['Older']);
    await tester.tap(find.byTooltip('More filters: video code, categories, year and duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(controller.releaseFilter.value, 'upcoming');
    expect(controller.filter.categoriesSelected, isEmpty);
    expect(find.text('1 of 2 videos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
