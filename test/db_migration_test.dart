import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:sqflite/sqflite.dart';

class _Database implements Database {
  final statements = <String>[];
  bool hasPlaylistId = false;
  bool hasChatActivity = false;
  String? failAt;
  bool unsupportedCollection = false;
  bool unsupportedActivity = false;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (failAt != null && sql.contains(failAt!)) throw StateError('Injected migration failure');
    statements.add(sql);
    if (sql.contains('ADD COLUMN playlist_id')) hasPlaylistId = true;
    if (sql.contains('ADD COLUMN activity')) hasChatActivity = true;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.startsWith('SELECT id FROM activity')) return unsupportedActivity ? [{'id': 'unsupported'}] : [];
    if (sql.startsWith('SELECT id FROM collection')) return unsupportedCollection ? [{'id': 'unsupported'}] : [];
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
    expect(DBUpdate.version, 19);
    await DBUpdate.onUpgrade(db, 1, 3);
    expect(db.statements.where((sql) => sql.contains('CREATE TABLE IF NOT EXISTS watch_session')).length, 2);
    expect(db.statements.any((sql) => sql.contains('DROP TABLE') || sql.contains('playlist_id') || sql.contains('historical') || sql.contains('chat_')), isFalse);
    db.statements.clear();
    await DBUpdate.onUpgrade(db, 8, 8);
    expect(db.statements, isEmpty);
    for (final range in [(0, 8), (8, 7), (19, 20)]) {
      await expectLater(DBUpdate.onUpgrade(db, range.$1, range.$2), throwsStateError);
    }
    await expectLater(DBUpdate.onDowngrade(db, 9, 8), throwsStateError);
    expect(db.statements, isEmpty);
    db.failAt = 'CREATE TABLE IF NOT EXISTS historical';
    await expectLater(DBUpdate.onUpgrade(db, 5, 8), throwsStateError);
    expect(db.statements.any((sql) => sql.contains('ADD COLUMN playlist_id')), isTrue);
    expect(db.statements.any((sql) => sql.contains('chat_conversation')), isFalse);
  });

  test('Unsupported collection types stop migration before any changes', () async {
    final db = _Database()..unsupportedCollection = true;
    await expectLater(DBUpdate.onUpgrade(db, 10, 11), throwsStateError);
    expect(db.statements, isEmpty);
  });

  test('Unsupported activity types stop migration before any changes', () async {
    final db = _Database()..unsupportedActivity = true;
    await expectLater(DBUpdate.onUpgrade(db, 13, 14), throwsStateError);
    expect(db.statements, isEmpty);
  });

  test('Activity migration preserves rows, validates domains and rolls back in SQLite', () async {
    final legacy = _Database();
    await DBService.onCreate(legacy, 13);
    final migration = _Database();
    await DBUpdate.onUpgrade(migration, 13, 14);
    final result = await Process.run('python3', ['-c', r'''
import json, os, sqlite3, sys
baseline, migration = json.loads(sys.argv[1])
def apply(db, statements, version, fail=None):
    db.execute('BEGIN')
    try:
        for sql in statements:
            db.execute(sql)
            if fail and fail in sql:
                raise RuntimeError('Injected failure')
        db.execute('PRAGMA user_version = %d' % version)
        db.commit()
    except Exception:
        db.rollback()
        raise
def legacy():
    db = sqlite3.connect(':memory:')
    apply(db, baseline, 13)
    db.execute("INSERT INTO activity VALUES ('t1','todo','Watch later','created','updated')")
    db.execute("INSERT INTO activity VALUES ('d1','download',?, 'created','updated')", (json.dumps({'filename':'a.mp4','ev':'start','url':'https://example.com','dir':'/tmp','retries':3,'custom':'keep'}),))
    db.execute("INSERT INTO activity VALUES ('r1','relapse','2024-02-29','created','updated'), ('r2','relapse','2024-02-29','created','updated')")
    db.commit()
    return db
for bad in [
    "INSERT INTO activity VALUES ('bad','todo','watch LATER',NULL,NULL)",
    "INSERT INTO activity VALUES ('bad','todo','  ',NULL,NULL)",
    "INSERT INTO activity VALUES ('bad','download','not json',NULL,NULL)",
    "INSERT INTO activity VALUES ('bad','download','[]',NULL,NULL)",
    "INSERT INTO activity VALUES ('bad','relapse','2025-02-29',NULL,NULL)",
    "INSERT INTO activity VALUES ('bad','relapse','2026-13-01',NULL,NULL)",
    "INSERT INTO activity VALUES (NULL,'todo','Missing ID',NULL,NULL)",
]:
    db = legacy()
    db.execute(bad)
    db.commit()
    before = db.execute('SELECT * FROM activity ORDER BY id').fetchall()
    try:
        apply(db, migration, 14)
    except (sqlite3.IntegrityError, sqlite3.OperationalError):
        pass
    else:
        raise AssertionError('Invalid legacy data accepted: ' + bad)
    assert db.execute('SELECT * FROM activity ORDER BY id').fetchall() == before
    assert db.execute('PRAGMA user_version').fetchone()[0] == 13
    assert not db.execute("SELECT name FROM sqlite_master WHERE name='todo'").fetchall()
    db.close()
db = legacy()
before = db.execute('SELECT * FROM activity ORDER BY id').fetchall()
try:
    apply(db, migration, 14, fail='DROP TABLE activity')
except RuntimeError:
    pass
else:
    raise AssertionError('Failure not injected')
assert db.execute('SELECT * FROM activity ORDER BY id').fetchall() == before
assert db.execute('PRAGMA user_version').fetchone()[0] == 13
apply(db, migration, 14)
assert db.execute('SELECT * FROM activity ORDER BY id').fetchall() == before
assert db.execute('SELECT filename,status,url,directory FROM download_log').fetchone() == ('a.mp4','start','https://example.com','/tmp')
assert json.loads(db.execute('SELECT payload FROM download_log').fetchone()[0])['custom'] == 'keep'
for sql in [
    "INSERT INTO todo (id,title) VALUES ('t2','watch LATER')",
    "INSERT INTO todo (id,title) VALUES ('t2','  ')",
    "INSERT INTO todo (id,title) VALUES ('t2',' untrimmed ')",
    "INSERT INTO download_log (id,payload) VALUES ('d2','invalid')",
    "INSERT INTO download_log (id,payload) VALUES ('d2','null')",
    "INSERT INTO relapse_event (id,occurred_on) VALUES ('r3','2025-02-29')",
]:
    try: db.execute(sql)
    except (sqlite3.IntegrityError, sqlite3.OperationalError): pass
    else: raise AssertionError('Invalid domain data accepted: ' + sql)
db.execute("UPDATE download_log SET payload=? WHERE id='d1'", (json.dumps({'filename':'renamed.mp4','ev':'finish','output_path':'/tmp/renamed.mp4'}),))
assert db.execute('SELECT filename,status,output_path FROM download_log').fetchone() == ('renamed.mp4','finish','/tmp/renamed.mp4')
assert any('idx_download_log_filename' in row[-1] for row in db.execute("EXPLAIN QUERY PLAN SELECT id FROM download_log WHERE filename LIKE 'renamed%'").fetchall())
try: db.execute("INSERT INTO activity (id,type,content) VALUES ('new','todo','blocked')")
except sqlite3.OperationalError: pass
else: raise AssertionError('Compatibility view must be read-only')
# IDs are domain-scoped; filtered deletion must not delete the same ID in another table.
db.execute("INSERT INTO todo (id,title) VALUES ('r1','Same ID')")
for kind, table in [('todo','todo'), ('download','download_log'), ('relapse','relapse_event')]:
    db.execute('DELETE FROM %s WHERE id IN (SELECT id FROM activity WHERE type = ? AND (id = ? AND type = ?))' % table, (kind,'r1','relapse'))
assert db.execute("SELECT count(*) FROM todo WHERE id='r1'").fetchone()[0] == 1
assert db.execute('SELECT count(*) FROM relapse_event').fetchone()[0] == 1
assert db.execute('PRAGMA quick_check').fetchall() == [('ok',)]
db.close()
# Optional verification uses an in-memory backup; the user's database stays read-only.
source_path = os.environ.get('KURAKU_ACTIVITY_DB')
if source_path:
    source = sqlite3.connect('file:' + source_path + '?mode=ro', uri=True)
    copy = sqlite3.connect(':memory:')
    source.backup(copy)
    source.close()
    current = copy.execute('PRAGMA user_version').fetchone()[0]
    assert current in (13, 14)
    before = copy.execute('SELECT * FROM activity ORDER BY id').fetchall()
    if current == 13: apply(copy, migration, 14)
    assert copy.execute('SELECT * FROM activity ORDER BY id').fetchall() == before
    assert copy.execute('PRAGMA quick_check').fetchall() == [('ok',)]
    assert copy.execute('PRAGMA foreign_key_check').fetchall() == []
    print('Local database copy migrated: %d activity rows preserved' % len(before))
    copy.close()
''', jsonEncode([legacy.statements, migration.statements])]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    if (result.stdout.toString().isNotEmpty) print(result.stdout);
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
    final legacy = _Database();
    await DBService.onCreate(legacy, 10);
    final playlistMigration = _Database();
    await DBUpdate.onUpgrade(playlistMigration, 10, 11);
    final retry = _Database()..hasPlaylistId = true..hasChatActivity = true;
    await DBUpdate.onUpgrade(retry, 5, DBUpdate.version);
    final worker = await Process.start('python3', ['-c', r'''
import json, sqlite3, sys
fresh, paths, retry, latest, legacy, playlist_migration = json.load(sys.stdin)
def connect():
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    return db
def apply(db, statements, version, fail=False):
    db.execute('BEGIN')
    try:
        for sql in statements:
            db.execute(sql)
            if fail and fail in sql:
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
    db.execute("INSERT INTO library (id, alias, root_folder) VALUES ('library-1', 'Keep me', '/library')")
    db.execute("INSERT INTO videos (id, root_path, video_path) VALUES ('video-1','/library','/library/video-1.mp4')")
    if path['old'] < 11:
        db.execute("INSERT INTO collection (id, type, name, cover) VALUES ('p1', 'playlist', 'My list', 'cover')")
        if path['old'] < 6:
            db.execute("INSERT INTO collection (id, type, name, video_id) VALUES ('item-1', 'playlist', 'My list', 'video-1')")
        else:
            db.execute("INSERT INTO collection (id, type, name, video_id, playlist_id) VALUES ('item-1', 'playlist', 'My list', 'video-1', 'p1')")
    else:
        db.execute("INSERT INTO playlist (id, name, cover) VALUES ('p1', 'My list', 'cover')")
        db.execute("INSERT INTO playlist_item (playlist_id, video_id) VALUES ('p1', 'video-1')")
    db.commit()
    if path['old'] < 7:
        before = schema(db)
        try:
            apply(db, path['upgrade'], latest, fail='CREATE TABLE IF NOT EXISTS historical')
        except RuntimeError:
            pass
        else:
            raise AssertionError('Failure not injected')
        assert schema(db) == before
        assert db.execute('PRAGMA user_version').fetchone()[0] == path['old']
        assert db.execute('SELECT count(*) FROM collection').fetchone()[0] == 2
    apply(db, path['upgrade'], latest)
    assert schema(db) == expected, path['old']
    assert db.execute('PRAGMA user_version').fetchone()[0] == latest
    assert db.execute('SELECT alias FROM library').fetchone() == ('Keep me',)
    assert db.execute("SELECT name, cover FROM playlist WHERE id = 'p1'").fetchone() == ('My list', 'cover')
    assert db.execute("SELECT playlist_id, video_id FROM playlist_item").fetchall() == [('p1', 'video-1')]
    assert db.execute('PRAGMA foreign_key_check').fetchall() == []
    db.close()
# Stale user_version with an already-added playlist_id must still be recoverable.
db = connect()
apply(db, legacy, 10)
db.execute('PRAGMA user_version = 5')
apply(db, retry, latest)
assert schema(db) == expected
assert db.execute('PRAGMA foreign_key_check').fetchall() == []
db.close()
# Reject malformed legacy rows atomically instead of dropping data.
for bad in [
    "INSERT INTO collection (id,type,name) VALUES ('bad','playlist','my LIST')",
    "INSERT INTO collection (id,type,name) VALUES ('bad','playlist','  ')",
    "INSERT INTO collection (id,type,name) VALUES ('bad','playlist','Favorite')",
    "INSERT INTO collection (id,type,playlist_id,video_id) VALUES ('bad','playlist','p1','missing')",
    "INSERT INTO collection (id,type,video_id) VALUES ('bad','playlist','v1')",
]:
    db = connect()
    apply(db, legacy, 10)
    db.execute("INSERT INTO videos (id) VALUES ('v1')")
    db.execute("INSERT INTO collection (id,type,name) VALUES ('p1','playlist','My list')")
    db.execute(bad)
    db.commit()
    before = db.execute('SELECT * FROM collection').fetchall()
    try:
        apply(db, playlist_migration, 11)
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError('Invalid legacy data accepted: ' + bad)
    assert db.execute('SELECT * FROM collection').fetchall() == before
    assert db.execute('PRAGMA user_version').fetchone()[0] == 10
    assert not db.execute("SELECT name FROM sqlite_master WHERE name='playlist'").fetchall()
    db.close()
# Membership deduplication, timestamp preservation, constraints and both cascades.
db = connect()
apply(db, legacy, 10)
db.execute("INSERT INTO videos (id) VALUES ('v1'), ('v2')")
db.execute("INSERT INTO collection (id,type,name,cover,created_at,updated_at) VALUES ('p1','playlist',' My list ','cover','created','updated'), ('p2','playlist','Empty',NULL,NULL,NULL)")
db.execute("INSERT INTO collection (id,type,playlist_id,video_id,created_at) VALUES ('i1','playlist','p1','v1','2020'), ('i2','playlist','p1','v1','2021'), ('i3','playlist','p1','v2','2022')")
db.commit()
before = db.execute('SELECT * FROM collection').fetchall()
try:
    apply(db, playlist_migration, 11, fail='DROP TABLE collection')
except RuntimeError:
    pass
else:
    raise AssertionError('Migration failure not injected')
assert db.execute('SELECT * FROM collection').fetchall() == before
assert db.execute('PRAGMA user_version').fetchone()[0] == 10
apply(db, playlist_migration, 11)
assert db.execute('SELECT * FROM playlist WHERE id="p1"').fetchone() == ('p1','My list','cover','created','updated')
assert db.execute('SELECT * FROM playlist_item ORDER BY video_id').fetchall() == [('p1','v1','2020'), ('p1','v2','2022')]
assert db.execute('SELECT count(*) FROM playlist WHERE id="p2"').fetchone()[0] == 1
for sql in [
    "INSERT INTO playlist (id,name) VALUES ('new','my LIST')",
    "INSERT INTO playlist (id,name) VALUES ('new','Favorite')",
    "INSERT INTO playlist_item (playlist_id,video_id) VALUES ('p1','v1')",
    "INSERT INTO playlist_item (playlist_id,video_id) VALUES ('p1','missing')",
    "INSERT INTO playlist_item (playlist_id,video_id) VALUES ('missing','v1')",
]:
    try: db.execute(sql)
    except sqlite3.IntegrityError: pass
    else: raise AssertionError('Invalid data accepted: ' + sql)
db.execute("UPDATE playlist SET name='Renamed' WHERE id='p1'")
assert db.execute('SELECT count(*) FROM playlist_item').fetchone()[0] == 2
db.execute("DELETE FROM videos WHERE id='v1'")
assert db.execute('SELECT video_id FROM playlist_item').fetchall() == [('v2',)]
db.execute("DELETE FROM playlist WHERE id='p1'")
assert db.execute('SELECT count(*) FROM playlist_item').fetchone()[0] == 0
assert db.execute('SELECT count(*) FROM videos').fetchone()[0] == 1
assert db.execute('PRAGMA foreign_key_check').fetchall() == []
db.close()
reference.close()
''']);
    addTearDown(() { worker.kill(); });
    final output = worker.stdout.transform(utf8.decoder).join();
    final errors = worker.stderr.transform(utf8.decoder).join();
    worker.stdin.write(jsonEncode([fresh.statements, paths, retry.statements, DBUpdate.version, legacy.statements, playlistMigration.statements]));
    await worker.stdin.close();
    expect(await worker.exitCode, 0, reason: '${await output}\n${await errors}');
  });
}
