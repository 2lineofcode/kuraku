import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/_update_db.dart';
import 'package:javit/app/data/database/db_library.dart';
import 'package:javit/app/data/models/library_entity.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_test_database.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final rows = <Map<String, Object?>>[];
  final queries = <Map<String, Object?>>[];
  final deletes = <Map<String, Object?>>[];
  bool countReturnsNothing = false;

  bool _matches(Map<String, Object?> row, String? where, List<Object?> args) {
    if (where == null) return true;
    if (where == 'id = ?') return row['id'] == args[0];
    if (where == 'root_folder = ?') return row['root_folder'] == args[0];
    throw UnsupportedError('Unexpected where clause: $where');
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expect(table, 'library');
    queries.add({'where': where, 'args': whereArgs});
    return rows.where((row) => _matches(row, where, whereArgs ?? const [])).map(Map<String, Object?>.from).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'library');
    if (rows.any((row) => row['root_folder'] == values['root_folder'])) throw SqliteTestException('UNIQUE constraint failed: library.root_folder');
    rows.add(Map<String, Object?>.from(values));
    return rows.length;
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'library');
    final found = rows.where((row) => _matches(row, where, whereArgs ?? const [])).toList();
    for (final row in found) {
      row.addAll(values);
    }
    return found.length;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    expect(table, 'library');
    deletes.add({'where': where, 'args': whereArgs});
    final before = rows.length;
    rows.removeWhere((row) => _matches(row, where, whereArgs ?? const []));
    return before - rows.length;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    expect(sql, 'SELECT COUNT(*) AS total FROM library');
    return countReturnsNothing ? [] : [{'total': rows.length}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;
  final dateLike = RegExp(r'^\d{4}-\d{2}-\d{2}');

  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
  });
  tearDown(Get.reset);


  test('v18 migration preserves existing libraries and validates album lists in SQLite', () async {
    final db = await SqliteTestDatabase.open();
    addTearDown(db.close);
    await DBService.onCreate(db, 17);
    await db.execute("INSERT INTO library(id, root_folder, alias, videos) VALUES ('old', '/old', 'Keep', '[]')");
    await DBUpdate.onUpgrade(db, 17, 18);
    final old = Library.fromJson((await db.query('library')).single);
    expect(old.alias, 'Keep');
    expect(old.images, isEmpty);
    await db.update('library', {'images': jsonEncode(['/old/cover.jpg'])});
    expect(Library.fromJson((await db.query('library')).single).images, ['/old/cover.jpg']);
    for (final invalid in ['invalid', '{}']) {
      await expectLater(db.update('library', {'images': invalid}), throwsA(isA<SqliteTestException>()));
    }
  });

  test('adds a library with a generated id, timestamps and encoded list columns', () async {
    final library = Library(rootFolder: '/Volumes/Movies', alias: 'Movies', totalVideo: 2, subFolder: ['/Volumes/Movies/a'], videos: ['/Volumes/Movies/a/one.mp4']);

    expect(await DBLibrary.add(library), isTrue);
    expect(library.id, hasLength(36));
    expect(library.createdAt, matches(dateLike));
    expect(library.updatedAt, matches(dateLike));

    final stored = database.rows.single;
    expect(stored['root_folder'], '/Volumes/Movies');
    expect(stored['alias'], 'Movies');
    expect(stored['total_video'], 2);
    expect(stored['sub_folder'], jsonEncode(['/Volumes/Movies/a']));
    expect(stored['videos'], jsonEncode(['/Volumes/Movies/a/one.mp4']));
    expect(database.queries, isEmpty);
  });

  test('refuses a second library pointing at the same root folder', () async {
    expect(await DBLibrary.add(Library(rootFolder: '/Volumes/Movies')), isTrue);
    expect(await DBLibrary.add(Library(rootFolder: '/Volumes/Movies', alias: 'Duplicate')), isFalse);
    expect(await DBLibrary.add(Library(rootFolder: '/Volumes/Other')), isTrue);
    expect(database.rows.map((row) => row['root_folder']), ['/Volumes/Movies', '/Volumes/Other']);

    expect(await DBLibrary.add(Library(rootFolder: '')), isFalse);
    expect(await DBLibrary.add(Library(rootFolder: '')), isFalse);
  });

  test('reads libraries back as decoded entities', () async {
    await DBLibrary.add(Library(rootFolder: '/a', subFolder: ['/a/x', '/a/y'], videos: ['/a/x/one.mp4']));
    await DBLibrary.add(Library(rootFolder: '/b'));

    final all = await DBLibrary.getAll();
    expect(all, hasLength(2));
    expect(all.first.subFolder, ['/a/x', '/a/y']);
    expect(all.first.videos, ['/a/x/one.mp4']);
    expect(all.last.subFolder, isNull);
    expect(all.last.videos, isNull);

    final byId = await DBLibrary.getByID(all.first.id!);
    expect(byId.single.rootFolder, '/a');
    expect(await DBLibrary.getByID('missing'), isEmpty);

    expect((await DBLibrary.getByRootFolder('/b')).single.rootFolder, '/b');
    expect(await DBLibrary.getByRootFolder('/nope'), isEmpty);
  });

  test('update refreshes the timestamp and only touches the matching row', () async {
    final first = Library(rootFolder: '/a', totalVideo: 1);
    final second = Library(rootFolder: '/b', totalVideo: 1);
    await DBLibrary.add(first);
    await DBLibrary.add(second);
    final createdAt = first.createdAt;
    first.updatedAt = '2020-01-01 00:00:00';
    first.totalVideo = 42;
    first.videos = ['/a/new.mp4'];

    await DBLibrary.update(first);

    final updated = database.rows.firstWhere((row) => row['id'] == first.id);
    expect(updated['total_video'], 42);
    expect(updated['videos'], jsonEncode(['/a/new.mp4']));
    expect(updated['created_at'], createdAt);
    expect(first.updatedAt, isNot('2020-01-01 00:00:00'));
    expect(database.rows.firstWhere((row) => row['id'] == second.id)['total_video'], 1);
  });

  test('deletes a single library and clears the whole table', () async {
    final first = Library(rootFolder: '/a');
    await DBLibrary.add(first);
    await DBLibrary.add(Library(rootFolder: '/b'));

    await DBLibrary.delete(first);
    expect(database.rows, hasLength(1));
    expect(database.deletes.single['where'], 'id = ?');

    await DBLibrary.deleteAll();
    expect(database.rows, isEmpty);
    expect(database.deletes.last['where'], isNull);
  });

  test('counts libraries and falls back to zero when the count row is missing', () async {
    expect(await DBLibrary.getCount(), 0);
    await DBLibrary.add(Library(rootFolder: '/a'));
    await DBLibrary.add(Library(rootFolder: '/b'));
    expect(await DBLibrary.getCount(), 2);

    database.countReturnsNothing = true;
    expect(await DBLibrary.getCount(), 0);
  });
}
