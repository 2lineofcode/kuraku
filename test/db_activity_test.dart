import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/db_activity.dart';
import 'package:javit/app/data/models/activity_entity.dart';
import 'package:sqflite/sqflite.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final rows = <Map<String, Object?>>[];
  final queries = <Map<String, Object?>>[];
  final raw = <List<Object?>>[];

  bool _matches(Map<String, Object?> row, String? where, List<Object?> args) {
    switch (where) {
      case null:
      case '1 = 1':
        return true;
      case 'type = ?':
        return row['type'] == args[0];
      case 'id = ?':
        return row['id'] == args[0];
      case 'id = ? AND type = ?':
        return row['id'] == args[0] && row['type'] == args[1];
      case 'type = ? AND lower(content) = lower(?)':
        return row['type'] == args[0] && '${row['content']}'.toLowerCase() == '${args[1]}'.toLowerCase();
    }
    if (where!.contains('json_extract')) {
      if (row['type'] != args[0]) return false;
      Object? filename;
      try {
        final decoded = jsonDecode('${row['content']}');
        filename = decoded is Map ? decoded['filename'] : null;
      } catch (_) {
        filename = null;
      }
      return '$filename'.contains('${args[1]}'.replaceAll('%', ''));
    }
    throw UnsupportedError('Unexpected where clause: $where');
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    expect(table, 'activity');
    queries.add({'where': where, 'args': whereArgs, 'orderBy': orderBy, 'limit': limit, 'groupBy': groupBy});
    var found = rows.where((row) => _matches(row, where, whereArgs ?? const [])).toList();
    if (orderBy != null) {
      final column = orderBy.split(' ').first;
      found.sort((a, b) => '${b[column]}'.compareTo('${a[column]}'));
    }
    if (limit != null && found.length > limit) found = found.sublist(0, limit);
    return found.map(Map<String, Object?>.from).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'activity');
    rows.add(Map<String, Object?>.from(values));
    return rows.length;
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    expect(table, 'activity');
    final found = rows.where((row) => _matches(row, where, whereArgs ?? const [])).toList();
    for (final row in found) {
      row.addAll(values);
    }
    return found.length;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    expect(table, 'activity');
    final before = rows.length;
    rows.removeWhere((row) => _matches(row, where, whereArgs ?? const []));
    return before - rows.length;
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    raw.add([sql, arguments]);
    final index = rows.indexWhere((row) => row['type'] == arguments![0] && row['content'] == arguments[1]);
    if (index == -1) return 0;
    rows.removeAt(index);
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    raw.add([sql, arguments]);
    final args = arguments ?? const [];
    if (sql.contains('COUNT(*) AS cnt')) {
      final matching = args.isEmpty ? rows : rows.where((row) => row['type'] == args[0]);
      return [{'cnt': matching.length}];
    }
    if (sql.contains('COUNT(*) AS times')) {
      final matching = rows.where((row) => row['type'] == args[0] && '${row['content']}'.compareTo('${args[1]}') >= 0 && '${row['content']}'.compareTo('${args[2]}') <= 0);
      return [{'times': matching.length}];
    }
    if (sql.contains('GROUP BY type, content')) {
      final grouped = <String, List<Map<String, Object?>>>{};
      for (final row in rows.where((row) => row['type'] == args[0])) {
        grouped.putIfAbsent('${row['content']}', () => []).add(row);
      }
      final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
      return keys
          .map((content) => {
                'id': grouped[content]!.last['id'],
                'type': args[0],
                'content': content,
                'times': grouped[content]!.length,
                'created_at': grouped[content]!.last['created_at'],
                'updated_at': grouped[content]!.last['updated_at'],
              })
          .toList();
    }
    throw UnsupportedError('Unexpected raw query: $sql');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Database database;
  final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  setUp(() {
    database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
  });
  tearDown(Get.reset);

  group('todo', () {
    test('stores a trimmed todo with generated identity and timestamps', () async {
      final todo = await DBActivity.addTodo('   Clean the library   ');

      expect(todo, isNotNull);
      expect(todo!.content, 'Clean the library');
      expect(todo.type, kActivityTypeTodo);
      expect(todo.id, isNotEmpty);
      expect(todo.id, hasLength(36));
      expect(todo.createdAt, isNotNull);
      expect(todo.updatedAt, todo.createdAt);
      expect(database.rows.single['content'], 'Clean the library');
      expect(database.rows.single.containsKey('times'), isFalse);
    });

    test('rejects blank content and case-insensitive duplicates without touching the table', () async {
      expect(await DBActivity.addTodo('Watch later'), isNotNull);
      expect(await DBActivity.addTodo('   watch LATER'), isNull);
      expect(await DBActivity.addTodo('   '), isNull);
      expect(await DBActivity.addTodo(''), isNull);
      expect(database.rows, hasLength(1));

      // Duplicate detection is scoped to todos only.
      expect(await DBActivity.addDownloadLog(Activity(content: 'Watch later')), isNotNull);
      expect(database.rows, hasLength(2));
    });

    test('lists todos newest first and can override the sort', () async {
      await DBActivity.addTodo('first');
      await DBActivity.addTodo('second');
      database.rows[0]['updated_at'] = '2026-01-01 00:00:00';
      database.rows[1]['updated_at'] = '2026-02-01 00:00:00';
      await DBActivity.addDownloadLog(Activity(content: '{"filename":"x.mp4"}'));

      final todos = await DBActivity.getTodos();
      expect(todos.map((e) => e.content), ['second', 'first']);
      expect(database.queries.last['orderBy'], 'updated_at DESC');

      await DBActivity.getTodos(orderBy: 'created_at ASC');
      expect(database.queries.last['orderBy'], 'created_at ASC');
    });

    test('deletes a todo by id without removing other activity types', () async {
      final todo = await DBActivity.addTodo('temporary');
      await DBActivity.addDownloadLog(Activity(id: todo!.id, content: '{"filename":"same-id.mp4"}'));

      await DBActivity.deleteTodo(todo.id!);
      expect(database.rows, hasLength(1));
      expect(database.rows.single['type'], kActivityTypeDownload);

      await DBActivity.deleteTodo('missing-id');
      expect(database.rows, hasLength(1));
    });
  });

  group('download log', () {
    test('forces the download type and can be fetched by id or filename', () async {
      final log = await DBActivity.addDownloadLog(Activity(type: 'whatever', content: '{"filename":"ABP-001.mp4","status":"queued"}'));
      expect(log!.type, kActivityTypeDownload);

      final byId = await DBActivity.getDownloadLog(log.id!);
      expect(byId!.content, contains('ABP-001.mp4'));
      expect(await DBActivity.getDownloadLog('nope'), isNull);

      final byFilename = await DBActivity.getDownloadLogByFilename('%ABP-001.mp4%');
      expect(byFilename!.id, log.id);
      expect(await DBActivity.getDownloadLogByFilename('%MISSING.mp4%'), isNull);
    });

    test('updates the stored content and refreshes only the updated timestamp', () async {
      final log = await DBActivity.addDownloadLog(Activity(content: '{"filename":"a.mp4","status":"queued"}'));
      database.rows.single['created_at'] = '2020-01-01 00:00:00';
      database.rows.single['updated_at'] = '2020-01-01 00:00:00';

      final updated = await DBActivity.updateDownloadLog(id: log!.id!, content: '  {"filename":"a.mp4","status":"done"}  ');
      expect(updated!.content, '{"filename":"a.mp4","status":"done"}');
      expect(database.rows.single['content'], contains('done'));
      expect(database.rows.single['created_at'], '2020-01-01 00:00:00');
      expect(database.rows.single['updated_at'], isNot('2020-01-01 00:00:00'));

      expect(await DBActivity.updateDownloadLog(id: 'unknown', content: 'x'), isNull);
    });

    test('lists download logs and deletes them by filename', () async {
      await DBActivity.addDownloadLog(Activity(content: '{"filename":"one.mp4"}'));
      await DBActivity.addDownloadLog(Activity(content: '{"filename":"two.mp4"}'));
      await DBActivity.addTodo('not a download');

      expect(await DBActivity.getDownloadLogs(), hasLength(2));
      await DBActivity.getDownloadLogs(orderBy: 'created_at DESC', groupBy: 'content');
      expect(database.queries.last['groupBy'], 'content');

      await DBActivity.deleteDownloadLogByFilename('%one.mp4%');
      expect(database.rows.where((row) => row['type'] == kActivityTypeDownload), hasLength(1));
      expect(database.rows.where((row) => row['type'] == kActivityTypeTodo), hasLength(1));
    });
  });

  group('relapse', () {
    test('stores one row per relapse using a date-only content column', () async {
      final today = await DBActivity.addRelapse();
      expect(today!.content, matches(dateOnly));

      final past = await DBActivity.addRelapse(date: DateTime(2026, 3, 4, 23, 59));
      expect(past!.content, '2026-03-04');
      expect(database.rows, hasLength(2));
      expect(await DBActivity.addRelapse(date: DateTime(2026, 3, 4)), isNotNull);
      expect(database.rows, hasLength(3));
    });

    test('groups relapses by day with an aggregated times counter', () async {
      await DBActivity.addRelapse(date: DateTime(2026, 3, 4));
      await DBActivity.addRelapse(date: DateTime(2026, 3, 4));
      await DBActivity.addRelapse(date: DateTime(2026, 3, 1));
      await DBActivity.addTodo('ignored by relapse queries');

      final grouped = await DBActivity.getAllRelapse();
      expect(grouped.map((e) => e.content), ['2026-03-04', '2026-03-01']);
      expect(grouped.map((e) => e.times), [2, 1]);
      expect(grouped.every((e) => e.type == kActivityTypeRelapse), isTrue);
    });

    test('returns the newest relapse transaction or null when there is none', () async {
      expect(await DBActivity.getLatestRelapseTransaction(), isNull);

      await DBActivity.addRelapse(date: DateTime(2026, 3, 1));
      await DBActivity.addRelapse(date: DateTime(2026, 3, 4));
      database.rows[0]['created_at'] = '2026-03-01 08:00:00';
      database.rows[1]['created_at'] = '2026-03-04 08:00:00';

      final latest = await DBActivity.getLatestRelapseTransaction();
      expect(latest!.content, '2026-03-04');
      expect(database.queries.last['orderBy'], 'created_at DESC');
      expect(database.queries.last['limit'], 1);
    });

    test('counts every relapse, a date range and today only', () async {
      await DBActivity.addRelapse(date: DateTime(2026, 3, 1));
      await DBActivity.addRelapse(date: DateTime(2026, 3, 4));
      await DBActivity.addRelapse(date: DateTime(2026, 3, 4));
      await DBActivity.addTodo('not counted');

      expect(await DBActivity.countRelapse(), 3);
      expect(await DBActivity.countRelapse(start: DateTime(2026, 3, 2), end: DateTime(2026, 3, 31)), 2);
      expect(await DBActivity.countRelapse(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 1)), 1);
      expect(await DBActivity.countRelapse(start: DateTime(2020, 1, 1), end: DateTime(2020, 1, 2)), 0);

      expect(await DBActivity.getCountRelapseToday(), 0);
      await DBActivity.addRelapse();
      expect(await DBActivity.getCountRelapseToday(), 1);
    });

    test('deletes a single relapse row for a day and keeps the rest', () async {
      await DBActivity.addRelapse(date: DateTime(2026, 3, 4));
      await DBActivity.addRelapse(date: DateTime(2026, 3, 4));

      await DBActivity.deleteRelapseByDateLimitOne('2026-03-04');
      expect(database.rows, hasLength(1));
      expect(database.raw.last.first, contains('LIMIT 1'));

      await DBActivity.deleteRelapseByDateLimitOne('2026-03-04');
      await DBActivity.deleteRelapseByDateLimitOne('2026-03-04');
      expect(database.rows, isEmpty);
    });
  });

  test('deleteAll clears everything by default and honours a custom filter', () async {
    await DBActivity.addTodo('one');
    await DBActivity.addRelapse(date: DateTime(2026, 3, 4));

    await DBActivity.deleteAll(where: 'type = ?', whereArgs: [kActivityTypeTodo]);
    expect(database.rows, hasLength(1));
    expect(database.rows.single['type'], kActivityTypeRelapse);

    await DBActivity.deleteAll();
    expect(database.rows, isEmpty);
  });
}
