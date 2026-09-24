import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/_update_db.dart';
import 'package:sqflite/sqflite.dart';

class _Database implements Database {
  final statements = <String>[];
  bool hasPlaylistId = false;
  bool hasChatActivity = false;
  String? failAt;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (failAt != null && sql.contains(failAt!)) throw StateError('Injected migration failure');
    statements.add(sql);
    if (sql.contains('ADD COLUMN playlist_id')) hasPlaylistId = true;
    if (sql.contains('ADD COLUMN activity')) hasChatActivity = true;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql == 'PRAGMA table_info(chat_message)') return hasChatActivity ? [{'name': 'activity'}] : [];
    expect(sql, 'PRAGMA table_info(collection)');
    return hasPlaylistId ? [{'name': 'playlist_id'}] : [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Migration runner respects target versions, rejects downgrade and stops on failure', () async {
    final db = _Database();
    expect(DBUpdate.version, 10);
    await DBUpdate.onUpgrade(db, 1, 3);
    expect(db.statements.where((sql) => sql.contains('CREATE TABLE IF NOT EXISTS watch_session')).length, 2);
    expect(db.statements.any((sql) => sql.contains('DROP TABLE') || sql.contains('playlist_id') || sql.contains('historical') || sql.contains('chat_')), isFalse);
    db.statements.clear();
    await DBUpdate.onUpgrade(db, 8, 8);
    expect(db.statements, isEmpty);
    for (final range in [(0, 8), (8, 7), (10, 11)]) {
      await expectLater(DBUpdate.onUpgrade(db, range.$1, range.$2), throwsStateError);
    }
    await expectLater(DBUpdate.onDowngrade(db, 9, 8), throwsStateError);
    expect(db.statements, isEmpty);
    db.failAt = 'CREATE TABLE IF NOT EXISTS historical';
    await expectLater(DBUpdate.onUpgrade(db, 5, 8), throwsStateError);
    expect(db.statements.any((sql) => sql.contains('ADD COLUMN playlist_id')), isTrue);
    expect(db.statements.any((sql) => sql.contains('chat_conversation')), isFalse);
  });

  test('Fresh database and every supported upgrade converge, preserve data and roll back in SQLite', () async {
    final fresh = _Database();
    await DBService.onCreate(fresh, DBUpdate.version);
    final paths = <Map<String, Object>>[];
    for (var oldVersion = 1; oldVersion <= DBUpdate.version; oldVersion++) {
      final db = _Database();
      await DBService.onCreate(db, oldVersion);
      final baseline = List<String>.from(db.statements);
      db.statements.clear();
      await DBUpdate.onUpgrade(db, oldVersion, DBUpdate.version);
      paths.add({'old': oldVersion, 'baseline': baseline, 'upgrade': List<String>.from(db.statements)});
    }
    final retry = _Database()..hasPlaylistId = true..hasChatActivity = true;
    await DBUpdate.onUpgrade(retry, 5, DBUpdate.version);
    final result = await Process.run('python3', ['-c', r'''
import json, sqlite3, sys
fresh, paths, retry, latest = json.loads(sys.argv[1])
def connect():
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    return db
def apply(db, statements, version, fail=False):
    db.execute('BEGIN')
    try:
        for sql in statements:
            db.execute(sql)
            if fail and 'CREATE TABLE IF NOT EXISTS historical' in sql:
                raise RuntimeError('Injected failure')
        db.execute('PRAGMA user_version = %d' % version)
        db.commit()
    except Exception:
        db.rollback()
        raise
def schema(db):
    return db.execute("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name").fetchall()
reference = connect()
apply(reference, fresh, latest)
expected = schema(reference)
for path in paths:
    db = connect()
    apply(db, path['baseline'], path['old'])
    db.execute("INSERT INTO library (id, alias) VALUES ('library-1', 'Keep me')")
    db.execute("INSERT INTO collection (id, type, name, video_id) VALUES ('item-1', 'playlist', 'My list', 'video-1')")
    db.commit()
    if path['old'] < 7:
        before = schema(db)
        try:
            apply(db, path['upgrade'], latest, fail=True)
        except RuntimeError:
            pass
        else:
            raise AssertionError('Failure not injected')
        assert schema(db) == before
        assert db.execute('PRAGMA user_version').fetchone()[0] == path['old']
        assert db.execute('SELECT count(*) FROM collection').fetchone()[0] == 1
    apply(db, path['upgrade'], latest)
    assert schema(db) == expected, path['old']
    assert db.execute('PRAGMA user_version').fetchone()[0] == latest
    assert db.execute('SELECT alias FROM library').fetchone() == ('Keep me',)
    assert db.execute("SELECT name, video_id FROM collection WHERE id = 'item-1'").fetchone() == ('My list', 'video-1')
    assert db.execute('PRAGMA foreign_key_check').fetchall() == []
    db.close()
# Stale user_version with an already-added playlist_id must still be recoverable.
db = connect()
apply(db, fresh, latest)
db.execute('PRAGMA user_version = 5')
apply(db, retry, latest)
assert schema(db) == expected
assert db.execute('PRAGMA foreign_key_check').fetchall() == []
db.close()
reference.close()
''', jsonEncode([fresh.statements, paths, retry.statements, DBUpdate.version])]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
