import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_r18.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Sqlite implements Database {
  _Sqlite(this.process) : output = StreamIterator(process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
  final Process process;
  final StreamIterator<String> output;
  final calls = <Map<String, dynamic>>[];
  String name = '';

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final args = arguments ?? [];
    process.stdin.writeln(jsonEncode({'sql': sql, 'args': args, 'runs': int.parse(Platform.environment['R18_BENCHMARK_RUNS'] ?? '1')}));
    if (!await output.moveNext()) throw StateError('SQLite worker stopped');
    final response = jsonDecode(output.current) as Map<String, dynamic>;
    calls.add({'name': name, 'sql': sql, 'args': args, ...response}..remove('rows'));
    if (response['error'] != null) throw StateError('${response['error']}');
    final rows = response['rows'] as List;
    calls.last['row_count'] = rows.length;
    return rows.map((row) => Map<String, Object?>.from(row as Map)).toList();
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) => rawQuery(
    'SELECT ${distinct == true ? 'DISTINCT ' : ''}${columns?.join(', ') ?? '*'} FROM $table'
    '${where == null ? '' : ' WHERE $where'}${groupBy == null ? '' : ' GROUP BY $groupBy'}'
    '${having == null ? '' : ' HAVING $having'}${orderBy == null ? '' : ' ORDER BY $orderBy'}'
    '${limit == null ? '' : ' LIMIT $limit'}${offset == null ? '' : ' OFFSET $offset'}', whereArgs,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('every public R18 query executes against SQLite with matching list/count results', () async {
    final path = Platform.environment['R18_BENCHMARK_DB'] ?? ':memory:';
    final worker = await Process.start('python3', ['-B', '-u', 'tool/r18_sql_worker.py', path]);
    final errors = worker.stderr.transform(utf8.decoder).join();
    final db = _Sqlite(worker);
    Get.put<DBService>(_Service()..dbR18 = db);
    final results = <Map<String, dynamic>>[];
    final failures = <String>[];
    Future<void> save() async {
      final report = Platform.environment['R18_BENCHMARK_REPORT'];
      if (report != null) await File(report).writeAsString(const JsonEncoder.withIndent('  ').convert({'database': path, 'results': results, 'queries': db.calls}));
    }
    Future<dynamic> run(String name, Future<dynamic> Function() action) async {
      db.name = name;
      final start = Stopwatch()..start();
      try {
        final result = await action();
        results.add({'name': name, 'elapsed_ms': start.elapsedMilliseconds, 'result_count': result is List || result is Map ? result.length : result});
        print('$name: ${start.elapsedMilliseconds} ms');
        await save();
        return result;
      } catch (error) {
        failures.add('$name: $error');
        results.add({'name': name, 'error': '$error'});
        await save();
        return null;
      }
    }
    try {
      final sample = (await db.rawQuery('''
        SELECT v.video_code, a.actress_id, c.name_en AS category, s.name_en AS series,
          l.name_en AS label, coalesce(m.name_en,m.name_ja) AS studio,
          d.name_romaji AS director, substr(v.release_date,1,4) AS year
        FROM derived_video v
        JOIN derived_video_actress a ON a.content_id=v.content_id
        JOIN derived_video_category vc ON vc.content_id=v.content_id JOIN derived_category c ON c.id=vc.category_id
        JOIN derived_series s ON s.id=v.series_id JOIN derived_label l ON l.id=v.label_id JOIN derived_maker m ON m.id=v.maker_id
        JOIN derived_video_director vd ON vd.content_id=v.content_id JOIN derived_director d ON d.id=vd.director_id
        WHERE v.video_code = ? AND v.release_date IS NOT NULL AND d.name_romaji IS NOT NULL
        LIMIT 1
      ''', [Platform.environment['R18_BENCHMARK_CODE'] ?? (path == ':memory:' ? 'ABC-123' : 'ABP-099')])).single;
      db.calls.clear();
      final code = sample['video_code'] as String;
      final actress = sample['actress_id'] as int;
      final category = sample['category'] as String;
      final series = sample['series'] as String;
      final year = sample['year'] as String;
      await run('getCountAllVideos', DBR18.getCountAllVideos);
      await run('getVideo', () => DBR18.getVideo(code));
      await run('getPosterByCodes', () => DBR18.getPosterByCodes([code, code, '']));
      final manyCodes = [code, ...List.generate(1000, (i) => 'ZZZZ-${i.toString().padLeft(5, '0')}')];
      await run('getPosterByCodes.large', () => DBR18.getPosterByCodes(manyCodes));
      await run('getActress', () => DBR18.getActress(code));
      await run('getCategory', () => DBR18.getCategory(code));
      await run('getCategoriesByVideoCodes', () => DBR18.getCategoriesByVideoCodes([code]));
      await run('getCategoriesByVideoCodes.large', () => DBR18.getCategoriesByVideoCodes(manyCodes));
      await run('getDirector', () => DBR18.getDirector(code));
      await run('getAllActress', () => DBR18.getAllActress());
      await run('getAllActress.search', () => DBR18.getAllActress(q: 'a'));
      await run('getAllCategories', () => DBR18.getAllCategories());
      await run('getAllCategories.search', () => DBR18.getAllCategories(q: 'a'));
      await run('getAllSeries', () => DBR18.getAllSeries());
      await run('getAllSeries.search', () => DBR18.getAllSeries(q: 'a'));
      for (final query in [code, code.replaceAll('-', ''), 'Old', '']) {
        final list = await run('search.$query', () => DBR18.search(query, perPage: 50));
        final count = await run('getSearchCount.$query', () => DBR18.getSearchCount(query));
        if (list != null && count != null) expect(list.length, lessThanOrEqualTo(count));
      }
      for (final filtered in [false, true]) {
        final list = await run('getByFilter.$filtered', () => DBR18.getByFilter(categories: filtered ? [category] : null, perPage: 50));
        final count = await run('getByFilterCount.$filtered', () => DBR18.getByFilterCount(categories: filtered ? [category] : null));
        if (list != null && count != null) expect(list.length, lessThanOrEqualTo(count));
      }
      final actressRows = await run('getByFilter.actress', () => DBR18.getByFilter(actressName: 'a', perPage: 50));
      final actressCount = await run('getByFilterCount.actress', () => DBR18.getByFilterCount(actressName: 'a'));
      if (actressRows != null && actressCount != null) expect(actressRows.length, lessThanOrEqualTo(actressCount));
      final combined = await run('getByFilter.combined', () => DBR18.getByFilter(videoCode: code, actressName: 'a', categories: [category, category], matchAllCategories: true, yearStart: int.parse(year), yearEnd: int.parse(year), durationMin: 1, durationMax: 300));
      final combinedCount = await run('getByFilterCount.combined', () => DBR18.getByFilterCount(videoCode: code, actressName: 'a', categories: [category, category], matchAllCategories: true, yearStart: int.parse(year), yearEnd: int.parse(year), durationMin: 1, durationMax: 300));
      if (combined != null && combinedCount != null) expect(combined.length, combinedCount);
      final releases = await run('getNewRelease', () => DBR18.getNewRelease());
      if (path == ':memory:') expect(releases.single['video_code'], 'DEF-789');
      for (final kind in ['Series', 'Category', 'Actress', 'Year']) {
        final groups = await run('getAdvancedSearchGroups.$kind', () => DBR18.getAdvancedSearchGroups(kind));
        await run('getAdvancedSearchGroups.$kind.cachedSearch', () => DBR18.getAdvancedSearchGroups(kind, q: 'a'));
        if (groups != null && groups.isNotEmpty) {
          final group = groups.first as Map;
          final videos = await run('getAdvancedSearchVideos.$kind', () => DBR18.getAdvancedSearchVideos(kind, group['id']));
          if (videos != null) expect(videos.length, group['video_count'], reason: kind);
        }
        final missing = await run('getAdvancedSearchVideos.$kind.missing', () => DBR18.getAdvancedSearchVideos(kind, kind == 'Year' ? '9999' : -1));
        if (missing != null) expect(missing, isEmpty);
      }
      await expectLater(DBR18.getAdvancedSearchGroups('Unknown'), throwsArgumentError);
      await expectLater(DBR18.getAdvancedSearchVideos('Unknown', 1), throwsArgumentError);
      for (final mode in ActressMode.values) {
        for (final (name, list, count) in [
          ('Actress', () => DBR18.getAllVideosByActress(actress, actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosByActress(actress, actressMode: mode)),
          ('Category', () => DBR18.getAllVideosByCategory(category, actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosByCategory(category, actressMode: mode)),
          ('Series', () => DBR18.getAllVideosBySeries(series, actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosBySeries(series, actressMode: mode)),
          ('SeriesWildcard', () => DBR18.getAllVideosBySeries('%', actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosBySeries('%', actressMode: mode)),
          ('Label', () => DBR18.getAllVideosByLabel(sample['label'] as String, actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosByLabel(sample['label'] as String, actressMode: mode)),
          ('Studio', () => DBR18.getAllVideosByStudio(sample['studio'] as String, actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosByStudio(sample['studio'] as String, actressMode: mode)),
          ('Director', () => DBR18.getAllVideosByDirector(sample['director'] as String, actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosByDirector(sample['director'] as String, actressMode: mode)),
          ('Year', () => DBR18.getAllVideosByYear(year, actressMode: mode, perPage: 50), () => DBR18.getCountAllVideosByYear(year, actressMode: mode)),
        ]) {
          final rows = await run('getAllVideosBy$name.${mode.name}', list);
          final total = await run('getCountAllVideosBy$name.${mode.name}', count);
          if (rows != null && total != null) expect(rows.length, lessThanOrEqualTo(total));
        }
      }
      final methods = RegExp(r'^  static Future[^\n]*?>\s+(\w+)(?:<[^>]+>)?\(', multiLine: true).allMatches(File('lib/app/data/database/db_r18.dart').readAsStringSync()).map((match) => match[1]!).where((name) => !name.startsWith('_')).toSet();
      final covered = results.map((row) => '${row['name']}'.split('.').first).toSet();
      expect(covered, containsAll(methods));
      await save();
      if (Platform.environment['R18_BENCHMARK_ALLOW_FAILURES'] != '1') expect(failures, isEmpty);
    } finally {
      await worker.stdin.close();
      await db.output.cancel();
      worker.kill();
      await worker.exitCode;
      expect(await errors, isEmpty);
      Get.reset();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
