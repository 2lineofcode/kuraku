import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

class SqliteTestException extends DatabaseException {
  SqliteTestException(super.message);
  @override
  int? getResultCode() => 19;
  @override
  Object? get result => null;
}

// Exercise the real SQLite engine without adding a test-only native dependency.
class SqliteTestDatabase implements Database, Transaction {
  SqliteTestDatabase._(this._process) : _responses = StreamIterator(_process.stdout.transform(utf8.decoder).transform(const LineSplitter()));

  final Process _process;
  final StreamIterator<String> _responses;
  Future<void> _requests = Future.value();
  Future<void> _transactions = Future.value();

  static Future<SqliteTestDatabase> open({String? sourcePath}) async => SqliteTestDatabase._(await Process.start('python3', ['-u', '-c', r'''
import json, sqlite3, sys
db = sqlite3.connect(':memory:', isolation_level=None)
if len(sys.argv) > 1:
    source = sqlite3.connect('file:' + sys.argv[1] + '?mode=ro', uri=True)
    source.backup(db)
    source.close()
db.row_factory = sqlite3.Row
db.execute('PRAGMA foreign_keys=ON')
def encode(value):
    return {'__blob__': list(value)} if isinstance(value, bytes) else value
def decode(value):
    return bytes(value['__blob__']) if isinstance(value, dict) and '__blob__' in value else value
for line in sys.stdin:
    try:
        request = json.loads(line)
        cursor = db.execute(request['sql'], [decode(v) for v in request.get('args', [])])
        result = {'rows': [{k: encode(row[k]) for k in row.keys()} for row in cursor.fetchall()] if cursor.description else [],
                  'count': cursor.rowcount, 'id': cursor.lastrowid}
    except Exception as error:
        result = {'error': str(error)}
    print(json.dumps(result), flush=True)
db.close()
''', ?sourcePath]));

  Future<Map<String, dynamic>> _run(String sql, [List<Object?>? args]) {
    final result = _requests.then((_) async {
      _process.stdin.writeln(jsonEncode({'sql': sql, 'args': args?.map((value) => value is Uint8List ? {'__blob__': value.toList()} : value).toList() ?? []}));
      if (!await _responses.moveNext()) throw StateError('SQLite worker exited');
      final reply = jsonDecode(_responses.current) as Map<String, dynamic>;
      if (reply['error'] != null) throw SqliteTestException(reply['error'] as String);
      return reply;
    });
    _requests = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async { await _run(sql, arguments); }
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final result = await _run(sql, arguments);
    return (result['rows'] as List).map((row) => (row as Map).map<String, Object?>((key, value) => MapEntry(key as String,
      value is Map && value.containsKey('__blob__') ? Uint8List.fromList(List<int>.from(value['__blob__'])) : value))).toList();
  }
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async => (await _run(sql, arguments))['id'] as int;
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => (await _run(sql, arguments))['count'] as int;
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) => rawUpdate(sql, arguments);
  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) => rawInsert(
    'INSERT ${conflictAlgorithm == ConflictAlgorithm.ignore ? 'OR IGNORE ' : conflictAlgorithm == ConflictAlgorithm.replace ? 'OR REPLACE ' : ''}INTO $table (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})', values.values.toList());
  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) => rawUpdate(
    'UPDATE $table SET ${values.keys.map((key) => '$key = ?').join(',')} ${where == null ? '' : 'WHERE $where'}', [...values.values, ...?whereArgs]);
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) => rawDelete('DELETE FROM $table ${where == null ? '' : 'WHERE $where'}', whereArgs);
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) => rawQuery(
    'SELECT ${distinct == true ? 'DISTINCT ' : ''}${columns?.join(',') ?? '*'} FROM $table'
    '${where == null ? '' : ' WHERE $where'}${groupBy == null ? '' : ' GROUP BY $groupBy'}${having == null ? '' : ' HAVING $having'}'
    '${orderBy == null ? '' : ' ORDER BY $orderBy'}${limit == null ? '' : ' LIMIT $limit'}${offset == null ? '' : ' OFFSET $offset'}', whereArgs);
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) {
    final result = _transactions.then((_) async {
      await execute('BEGIN');
      try {
        final value = await action(this);
        await execute('COMMIT');
        return value;
      } catch (_) {
        await execute('ROLLBACK');
        rethrow;
      }
    });
    _transactions = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
  Future<int> getVersion() async => (await rawQuery('PRAGMA user_version')).single['user_version'] as int;
  Future<void> setVersion(int version) => execute('PRAGMA user_version = $version');
  @override
  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode;
    await _responses.cancel();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
