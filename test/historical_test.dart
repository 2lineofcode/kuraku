import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_historical.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final schema = <String>[];
  final writes = <List<Object?>>[];
  final reads = <List<Object?>>[];
  final deletes = <List<Object?>>[];
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async { schema.add(sql); }
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    writes.add([sql, arguments]);
    return 1;
  }
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    reads.add(['SELECT ${columns!.join(', ')} FROM $table WHERE $where ORDER BY $orderBy LIMIT $limit', whereArgs]);
    return [{'query': 'ABC'}];
  }
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    deletes.add(['DELETE FROM $table WHERE $where', whereArgs]);
    return 1;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  test('history persists, deduplicates, filters and deletes within its type in SQLite', () async {
    final database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
    await DBUpdate.onUpgrade(database, 6, 7);
    await DBHistorical.save(kHistoricalTypeDownload, '  Abc  ');
    await DBHistorical.save(kHistoricalTypeDownload, 'ABC');
    await DBHistorical.save('search', 'ABC');
    await DBHistorical.save(kHistoricalTypeDownload, 'XYZ');
    await DBHistorical.save(kHistoricalTypeDownload, '  ');
    expect(database.writes.length, 4);
    expect(await DBHistorical.search(kHistoricalTypeDownload, ' ab '), ['ABC']);
    await DBHistorical.search(kHistoricalTypeDownload, '');
    await DBHistorical.search(kHistoricalTypeDownload, '%');
    await DBHistorical.delete(kHistoricalTypeDownload, 'abc');
    await DBHistorical.clear(kHistoricalTypeDownload);
    final result = await Process.run('python3', ['-c', r'''
import json, os, sqlite3, sys, tempfile
schema, writes, reads, deletes = json.loads(sys.argv[1])
with tempfile.TemporaryDirectory() as folder:
    path = os.path.join(folder, 'history.db')
    conn = sqlite3.connect(path)
    for sql in schema:
        conn.execute(sql)
    for sql, args in writes:
        conn.execute(sql, args)
    conn.commit()
    conn.close()
    conn = sqlite3.connect(path)
    assert conn.execute('SELECT count(*) FROM historical').fetchone()[0] == 3
    assert conn.execute(*reads[0]).fetchall() == [('ABC',)]
    assert conn.execute(*reads[1]).fetchall() == [('XYZ',), ('ABC',)]
    assert conn.execute(*reads[2]).fetchall() == []
    conn.execute(*deletes[0])
    assert conn.execute('SELECT query FROM historical WHERE type="download"').fetchall() == [('XYZ',)]
    assert conn.execute('SELECT query FROM historical WHERE type="search"').fetchall() == [('ABC',)]
    for sql in schema:
        conn.execute(sql)
    assert conn.execute('SELECT count(*) FROM historical').fetchone()[0] == 2
    conn.execute(*deletes[1])
    assert conn.execute('SELECT count(*) FROM historical WHERE type="download"').fetchone()[0] == 0
    assert conn.execute('SELECT query FROM historical WHERE type="search"').fetchall() == [('ABC',)]
    conn.close()
''', jsonEncode([database.schema, database.writes, database.reads, database.deletes])]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
