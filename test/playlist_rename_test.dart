import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/_update_db.dart';
import 'package:javit/app/data/database/db_playlist.dart';
import 'package:javit/app/data/models/playlist_entity.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_playlist.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database, Transaction {
  bool duplicate = false;
  bool missing = false;
  bool hasPlaylistId = false;
  bool inTransaction = false;
  final statements = <String>[];
  String? playlistQuery;
  final queries = <({String? where, List<Object?>? args})>[];
  final updates = <({Map<String, Object?> values, String? where, List<Object?>? args})>[];
  final inserts = <Map<String, Object?>>[];
  final deletes = <({String? where, List<Object?>? args})>[];

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    inTransaction = true;
    try { return await action(this); } finally { inTransaction = false; }
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async { statements.add(sql); }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    queries.add((where: where, args: whereArgs));
    if (where == 'id = ?') return missing ? [] : [{'id': whereArgs![0]}];
    return duplicate ? [{'name': 'New name'}] : [];
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.startsWith('SELECT id FROM collection')) return [];
    if (sql == 'PRAGMA table_info(collection)') return hasPlaylistId ? [{'name': 'playlist_id'}] : [];
    playlistQuery = sql;
    return [];
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(inTransaction, isTrue);
    updates.add((values: values, where: where, args: whereArgs));
    return missing ? 0 : 1;
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(inTransaction, isTrue);
    inserts.add(values);
    return 1;
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    expect(inTransaction, isTrue);
    expect(sql, contains('ON CONFLICT(playlist_id, video_id) DO NOTHING'));
    inserts.add({'playlist_id': arguments![0], 'video_id': arguments[1], 'created_at': arguments[2]});
    return 1;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    deletes.add((where: where, args: whereArgs));
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Database database;
  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
  });
  tearDown(Get.reset);

  testWidgets('Edit Playlist allows changing the name', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await tester.pumpAndSettle();
    await HomePanelPlaylist.showDialogAddOrEditPlaylist(playlist: Playlist(id: 'playlist-1', name: 'Old name', cover: 'cover'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate((widget) => widget is CupertinoTextField && widget.placeholder == 'Name');
    expect(tester.widget<CupertinoTextField>(field).readOnly, isFalse);
    await tester.enterText(field, 'New name');
    expect(tester.widget<CupertinoTextField>(field).controller!.text, 'New name');
    Get.back();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('rename changes only the header by ID and preserves item links', () async {
    final edited = Playlist(id: 'playlist-1', name: '  New name  ', cover: 'new-cover');
    expect(await DBPlaylist.updatePlaylist(edited), isTrue);
    expect(database.queries.single.where, 'name = ? COLLATE NOCASE AND id != ?');
    expect(database.queries.single.args, ['New name', 'playlist-1']);
    expect(database.updates.single.where, 'id = ?');
    expect(database.updates.single.args, ['playlist-1']);
    expect(database.updates.single.values['name'], 'New name');
    expect(database.updates.single.values['cover'], 'new-cover');
    expect(database.updates.single.values.containsKey('video_id'), isFalse);
    expect(database.updates.single.values.containsKey('playlist_id'), isFalse);
  });

  test('duplicate, missing and invalid names do not rename a playlist', () async {
    database.duplicate = true;
    expect(await DBPlaylist.updatePlaylist(Playlist(id: 'playlist-1', name: 'New name')), isFalse);
    expect(database.updates, isEmpty);
    for (final name in ['  ', 'Favorite', 'favorite']) {
      expect(await DBPlaylist.updatePlaylist(Playlist(id: 'playlist-1', name: name)), isFalse);
    }
    expect(await DBPlaylist.updatePlaylist(Playlist(name: 'New name')), isFalse);
    expect(database.updates, isEmpty);
    database.duplicate = false;
    database.missing = true;
    expect(await DBPlaylist.updatePlaylist(Playlist(id: 'playlist-1', name: 'New name')), isFalse);
  });

  test('playlist creation, membership and deletion use stable IDs', () async {
    final playlist = Playlist(name: 'New name');
    expect(await DBPlaylist.addPlaylist(playlist), isTrue);
    expect(playlist.id, isNotEmpty);
    expect(database.inserts.single['playlist_id'], isNull);
    await DBPlaylist.addPlaylistItemBulk(playlist.id!, [Videos(id: 'video-1')]);
    expect(database.inserts.last['playlist_id'], playlist.id);
    expect(database.inserts.last['name'], isNull);
    expect(database.inserts.last['video_id'], 'video-1');
    await DBPlaylist.getPlaylist(playlist.id!);
    expect(database.playlistQuery, contains('JOIN videos'));
    expect(database.playlistQuery, contains('ORDER BY item.created_at ASC, item.video_id ASC'));
    await DBPlaylist.deletePlaylistItems(playlist.id!, 'video-1');
    expect(database.deletes.last.where, 'playlist_id = ? AND video_id = ?');
    expect(database.deletes.last.args, [playlist.id, 'video-1']);
    await DBPlaylist.deletePlaylist(playlist);
    expect(database.deletes.last.where, 'id = ?');
    expect(database.deletes.last.args, [playlist.id]);
    final restored = Playlist.fromJson(database.inserts.first);
    expect(restored.id, playlist.id);
    expect(restored.total, 0);
  });

  test('Playlist queries count only videos and return stable membership order', () async {
    await DBUpdate.onUpgrade(database, 10, 11);
    await DBUpdate.onUpgrade(database, 15, 16);
    await DBPlaylist.getAllPlaylist();
    final headers = database.playlistQuery!;
    await DBPlaylist.getPlaylist('p1');
    final result = await Process.run('python3', ['-c', r'''
import json, sqlite3, sys
schema, headers, items = json.loads(sys.argv[1])
db = sqlite3.connect(':memory:')
db.execute('PRAGMA foreign_keys=ON')
db.execute('CREATE TABLE videos (id TEXT PRIMARY KEY, title TEXT)')
db.execute('CREATE TABLE collection (id TEXT, type TEXT, name TEXT, cover TEXT, video_id TEXT, playlist_id TEXT, created_at TEXT, updated_at TEXT)')
for sql in schema: db.execute(sql)
db.execute("INSERT INTO playlist(id,name) VALUES ('p1','List'),('p2','Empty')")
db.execute("INSERT INTO videos(id,title) VALUES ('v1','First'),('v2','Second')")
db.execute("INSERT INTO playlist_item VALUES ('p1','v2','2026'),('p1','v1','2026')")
assert {row[0]: row[-1] for row in db.execute(headers)} == {'p1': 2, 'p2': 0}
assert db.execute(items, ['p1']).fetchall() == [('v1','First',0),('v2','Second',0)]
db.execute("DELETE FROM videos WHERE id='v1'")
assert {row[0]: row[-1] for row in db.execute(headers)} == {'p1': 1, 'p2': 0}
assert db.execute(items, ['p1']).fetchall() == [('v2','Second',0)]
''', jsonEncode([database.statements, headers, database.playlistQuery])]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('legacy migration preserves rows, recovers orphan groups and cascades by ID in SQLite', () async {
    await DBUpdate.onUpgrade(database, 5, 6);
    final initialMigration = database.statements.toList();
    database.statements.clear();
    database.hasPlaylistId = true;
    await DBUpdate.onUpgrade(database, 5, 6);
    expect(database.statements.any((sql) => sql.startsWith('ALTER TABLE')), isFalse);
    final result = await Process.run('python3', ['-c', r'''
import json, sqlite3, sys
conn = sqlite3.connect(':memory:')
conn.execute('PRAGMA foreign_keys = ON')
conn.execute('CREATE TABLE collection (id TEXT PRIMARY KEY, type TEXT, name TEXT, cover TEXT, video_id TEXT, created_at TEXT, updated_at TEXT)')
rows = [
    ('p1', 'playlist', 'Old name', 'cover', None, 'created', 'updated'),
    ('i1', 'playlist', 'Old name', None, 'video-1', 'created', 'updated'),
    ('i2', 'playlist', 'Old name', None, 'video-2', 'created', 'updated'),
    ('p2', 'playlist', 'Empty', 'empty-cover', None, 'created', 'updated'),
    ('orphan', 'playlist', "Name with ' quotes", 'old-cover', 'video-3', 'created', 'updated'),
    ('null-name', 'playlist', None, None, 'video-4', 'created', 'updated'),
    ('other', 'actress_favorite', 'Old name', None, 'video-1', 'created', 'updated'),
]
conn.executemany('INSERT INTO collection VALUES (?,?,?,?,?,?,?)', rows)
with conn:
    for sql in json.loads(sys.argv[1]):
        conn.execute(sql)
for row in rows:
    assert conn.execute('SELECT id,type,name,cover,video_id,created_at,updated_at FROM collection WHERE id=?', (row[0],)).fetchone() == row
assert conn.execute('SELECT playlist_id FROM collection WHERE id IN ("i1","i2")').fetchall() == [('p1',), ('p1',)]
assert conn.execute('SELECT playlist_id FROM collection WHERE id="other"').fetchone() == (None,)
for item in ['orphan', 'null-name']:
    parent = conn.execute('SELECT playlist_id FROM collection WHERE id=?', (item,)).fetchone()[0]
    assert parent is not None
    assert conn.execute('SELECT video_id FROM collection WHERE id=?', (parent,)).fetchone() == (None,)
assert conn.execute('SELECT count(*) FROM collection WHERE video_id IS NULL').fetchone()[0] == 4
conn.execute('UPDATE collection SET name=? WHERE id=?', ('Renamed', 'p1'))
before_retry = conn.execute('SELECT * FROM collection ORDER BY id').fetchall()
for sql in json.loads(sys.argv[2]):
    conn.execute(sql)
assert conn.execute('SELECT * FROM collection ORDER BY id').fetchall() == before_retry
assert conn.execute('SELECT video_id FROM collection WHERE playlist_id="p1" ORDER BY video_id').fetchall() == [('video-1',), ('video-2',)]
conn.execute('DELETE FROM collection WHERE id="p1"')
assert conn.execute('SELECT count(*) FROM collection WHERE id IN ("p1","i1","i2")').fetchone()[0] == 0
assert conn.execute('SELECT count(*) FROM collection WHERE id IN ("p2","orphan","null-name","other")').fetchone()[0] == 4
assert conn.execute('PRAGMA foreign_key_check').fetchall() == []
''', jsonEncode(initialMigration), jsonEncode(database.statements)]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
