import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/modules/home/page_sqleditor/page_sqleditor_tab.dart';
import 'package:sqflite/sqflite.dart';

// Exercise the actual metadata SQL against SQLite without a native Flutter plugin.
class _SchemaDatabase implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final result = await Process.run('python3', ['-c', '''
import sqlite3, json, sys
conn = sqlite3.connect(':memory:')
conn.row_factory = sqlite3.Row
conn.executescript('CREATE TABLE videos (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, video_code TEXT); CREATE TABLE playlist (id INTEGER, name TEXT); CREATE VIEW titles AS SELECT title FROM videos;')
conn.execute('PRAGMA query_only=ON')
print(json.dumps([dict(row) for row in conn.execute(sys.argv[1])]))
''', sql]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return (jsonDecode(result.stdout as String) as List).cast<Map<String, dynamic>>();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Live schema SQL and contextual table, column, alias completion', () async {
    final schema = await PageSqleditorTab.readSchema(_SchemaDatabase());
    expect(schema['videos'], ['id', 'title', 'video_code']);
    expect(schema['titles'], ['title']);
    expect(schema, contains('sqlite_sequence'));
    final controller = PageSqleditorTab(sources: {'javit.db': '/javit.db'}, loadSchema: (_) async => schema);
    controller.onInit();
    await controller.refreshSchema();
    void type(String sql, [int? cursor]) {
      controller.input.value = TextEditingValue(text: sql, selection: TextSelection.collapsed(offset: cursor ?? sql.length));
    }

    type('SELECT * FROM ');
    expect(controller.suggestions.toSet(), schema.keys.toSet());
    type('SELECT video_');
    expect(controller.suggestions, ['video_code']);
    type('SELECT * FROM vid');
    expect(controller.suggestions, ['videos']);
    controller.complete('videos');
    expect(controller.input.text, 'SELECT * FROM videos');
    type('SELECT * FROM videos WHERE ti');
    expect(controller.suggestions, ['title']);
    type('SELECT * FROM videos WHERE ');
    expect(controller.suggestions, containsAll(['id', 'title', 'video_code']));
    type('SELECT v. FROM videos AS v', 9);
    expect(controller.suggestions, ['id', 'title', 'video_code']);
    type('SELECT v.vi FROM videos v', 11);
    expect(controller.suggestions, ['video_code']);
    controller.complete('video_code');
    expect(controller.input.text, 'SELECT v.video_code FROM videos v');
    type('SELECT * FROM videos JOIN playlist p ON p.');
    expect(controller.suggestions, ['id', 'name']);
    type('SELECT * FROM videos JOIN pl');
    expect(controller.suggestions, ['playlist']);
    type('SELECT "v". FROM "videos" AS "v"', 11);
    expect(controller.suggestions, ['id', 'title', 'video_code']);
    type('SELECT * FROM videos; SELECT * FROM playlist WHERE ');
    expect(controller.suggestions, ['id', 'name']);
    type("SELECT * FROM videos WHERE title = 'FROM vi");
    expect(controller.suggestions, isEmpty);
    type('SELECT * FROM videos -- FROM vi');
    expect(controller.suggestions, isEmpty);
    type('SELECT * FROM videos /* FROM vi');
    expect(controller.suggestions, isEmpty);
    type(';', 0);
    expect(controller.suggestions, isEmpty);
    controller.onClose();
  });

  test('Source switches discard stale schema; failed metadata loads can retry', () async {
    final pending = <Completer<Map<String, List<String>>>>[];
    final controller = PageSqleditorTab(sources: {'javit.db': '/javit.db', 'r18*.db': '/r18.db'}, loadSchema: (_) {
      final completer = Completer<Map<String, List<String>>>();
      pending.add(completer);
      return completer.future;
    });
    controller.onInit();
    controller.selectSource('r18*.db');
    controller.input.value = const TextEditingValue(text: 'SELECT * FROM ', selection: TextSelection.collapsed(offset: 14));
    pending[1].complete({'r18_titles': ['content_id']});
    await Future<void>.delayed(Duration.zero);
    pending[0].complete({'videos': ['title']});
    await Future<void>.delayed(Duration.zero);
    expect(controller.suggestions, ['r18_titles']);
    var refresh = controller.refreshSchema();
    pending[2].completeError(StateError('Database unavailable'));
    await refresh;
    expect(controller.schemaError.value, isNotEmpty);
    expect(controller.schemaLoading.value, isFalse);
    expect(controller.suggestions, isEmpty);
    refresh = controller.refreshSchema();
    pending[3].complete({'updated_table': ['id']});
    await refresh;
    expect(controller.schemaError.value, isEmpty);
    expect(controller.suggestions, ['updated_table']);
    controller.onClose();
  });
}
