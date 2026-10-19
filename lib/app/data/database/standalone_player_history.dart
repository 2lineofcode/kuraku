import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class StandaloneRecent {
  const StandaloneRecent({required this.path, this.position = Duration.zero, this.duration = Duration.zero});

  final String path;
  final Duration position;
  final Duration duration;
}

class StandalonePlayerHistory extends GetxService {
  StandalonePlayerHistory(this.directory);

  final String directory;
  Future<Database>? _database;

  Future<Database> get database => _database ??= open().catchError((Object error) {
    _database = null;
    throw error;
  });

  Future<Database> open() async {
    await Directory(directory).create(recursive: true);
    if (Platform.isLinux || Platform.isWindows) sqfliteFfiInit();
    final factory = Platform.isLinux || Platform.isWindows ? databaseFactoryFfi : databaseFactory;
    return factory.openDatabase(p.join(directory, 'standalone_player.db'), options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => createTable(db),
    ));
  }

  static Future<void> createTable(Database db) => db.execute('''CREATE TABLE standalone_recent (
    path TEXT NOT NULL PRIMARY KEY CHECK(length(path) > 0),
    position_ms INTEGER NOT NULL CHECK(position_ms >= 0),
    duration_ms INTEGER NOT NULL CHECK(duration_ms >= 0),
    opened_at INTEGER NOT NULL
  )''');

  Future<List<StandaloneRecent>> getAll() async {
    final rows = await (await database).query('standalone_recent', orderBy: 'opened_at DESC, rowid DESC', limit: 10);
    return rows.map((row) => StandaloneRecent(path: row['path'] as String,
      position: Duration(milliseconds: row['position_ms'] as int), duration: Duration(milliseconds: row['duration_ms'] as int))).toList();
  }

  Future<void> save(StandaloneRecent item) async {
    if (item.path.isEmpty || item.position.isNegative || item.duration.isNegative) throw ArgumentError('Invalid recent file');
    await (await database).transaction((txn) async {
      await txn.rawInsert('''INSERT INTO standalone_recent (path, position_ms, duration_ms, opened_at) VALUES (?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET position_ms = excluded.position_ms,
          duration_ms = excluded.duration_ms, opened_at = excluded.opened_at''',
        [item.path, item.position.inMilliseconds, item.duration.inMilliseconds, DateTime.now().millisecondsSinceEpoch]);
      await txn.execute('''DELETE FROM standalone_recent WHERE path NOT IN (
        SELECT path FROM standalone_recent ORDER BY opened_at DESC, rowid DESC LIMIT 10
      )''');
    });
  }

  Future<void> remove(String? path) async {
    await (await database).delete('standalone_recent', where: path == null ? null : 'path = ?', whereArgs: path == null ? null : [path]);
  }
}
