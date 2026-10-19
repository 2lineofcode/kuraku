import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/standalone_player_history.dart';
import 'package:kuraku/app/modules/home/home_binding.dart';
import 'package:kuraku/app/modules/home/page_sqleditor/page_sqleditor_controller.dart';
import 'package:kuraku/app/modules/player/player_controller.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_test_database.dart';

class _Preferences implements GetSecureStorage {
  @override
  T? read<T>(String key) => null;
  @override
  Future<void> write(String key, dynamic value) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements Database {
  _Database(this.path, this.db);
  @override
  final String path;
  final Database db;
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) => db.rawQuery(sql, arguments);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History extends StandalonePlayerHistory {
  _History(super.directory, this.db);
  final Database db;
  int opens = 0;
  @override
  Future<Database> open() async {
    opens++;
    return db;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Home SQL sources load and query standalone history without using the library database', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-sql-sources-');
    final db = await SqliteTestDatabase.open();
    final library = await SqliteTestDatabase.open();
    addTearDown(() async {
      Get.reset();
      await db.close();
      await library.close();
      await directory.delete(recursive: true);
    });
    await StandalonePlayerHistory.createTable(db);
    await db.rawInsert('INSERT INTO standalone_recent VALUES (?, ?, ?, ?)', ['/movie.mp4', 5000, 10000, 1]);
    final path = '${directory.path}/standalone_player.db';
    await db.execute('VACUUM INTO ?', [path]);
    final history = _History(directory.path, _Database(path, db));
    Get.put(AppSettingService()..pref = _Preferences());
    Get.put(DBService()..dbMain = _Database('${directory.path}/kuraku.db', library));
    Get.put<StandalonePlayerHistory>(history);
    Get.lazyPut<PlayerController>(() => PlayerController());
    HomeBinding().dependencies();
    final editor = Get.find<PageSqleditorController>();
    expect(editor.sources.keys, ['kuraku.db', 'r18*.db', 'standalone_player.db']);
    expect(editor.sources['standalone_player.db'], path);
    expect(history.opens, 0);

    editor.activeTab.selectSource('standalone_player.db');
    await editor.activeTab.refreshSchema();
    expect(editor.activeTab.schemaTables, contains('standalone_recent'));
    final result = await editor.query!('standalone_player.db', {
      'sql': 'SELECT path, position_ms FROM standalone_recent',
    }, CancelToken());
    expect(result['rows'], [['/movie.mp4', 5000]]);
    expect(history.opens, 1);
    expect(await editor.loadSchema!('r18*.db'), isEmpty);
    await expectLater(editor.query!('r18*.db', {'sql': 'SELECT 1'}, CancelToken()), throwsStateError);
    await expectLater(editor.query!('unknown.db', {'sql': 'SELECT 1'}, CancelToken()), throwsStateError);
  });
}
