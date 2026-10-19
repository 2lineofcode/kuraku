import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/data/database/standalone_player_history.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_test_database.dart';

class _History extends StandalonePlayerHistory {
  _History(this.db) : super('');
  final Database db;
  bool failOpen = false;
  @override
  Future<Database> open() async {
    if (failOpen) throw const FileSystemException('Storage unavailable');
    return db;
  }
}

void main() {
  late SqliteTestDatabase db;
  late StandalonePlayerHistory history;

  setUp(() async {
    db = await SqliteTestDatabase.open();
    await StandalonePlayerHistory.createTable(db);
    history = _History(db);
  });
  tearDown(() => db.close());

  test('recent storage retries after an opening failure', () async {
    final unavailable = _History(db)..failOpen = true;
    await expectLater(unavailable.getAll(), throwsA(isA<FileSystemException>()));
    unavailable.failOpen = false;
    await unavailable.save(const StandaloneRecent(path: '/recovered.mp4'));
    expect((await unavailable.getAll()).single.path, '/recovered.mp4');
  });

  test('recent files deduplicate paths, retain position across reload and stay independent of library tables', () async {
    const path = "/Videos/日本語 #1's movie.mp4";
    await history.save(const StandaloneRecent(path: path, position: Duration(seconds: 527), duration: Duration(hours: 2)));
    await history.save(const StandaloneRecent(path: path, position: Duration(seconds: 600), duration: Duration(hours: 2)));
    expect(await history.getAll(), hasLength(1));
    final directory = await Directory.systemTemp.createTemp('kuraku-recent-');
    addTearDown(() => directory.delete(recursive: true));
    final snapshot = '${directory.path}/recent.db';
    await db.execute('VACUUM INTO ?', [snapshot]);
    final reopened = await SqliteTestDatabase.open(sourcePath: snapshot);
    try {
      final saved = (await _History(reopened).getAll()).single;
      expect(saved.path, path);
      expect(saved.position, const Duration(minutes: 10));
      expect(saved.duration, const Duration(hours: 2));
      expect((await reopened.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")).map((row) => row['name']), ['standalone_recent']);
    } finally {
      await reopened.close();
    }
    await expectLater(history.save(const StandaloneRecent(path: '')), throwsArgumentError);
    await expectLater(history.save(const StandaloneRecent(path: path, position: Duration(seconds: -1))), throwsArgumentError);
  });

  test('only the ten latest files remain and removing one or all is persistent', () async {
    for (var i = 0; i < 12; i++) {
      await history.save(StandaloneRecent(path: '/video$i.mp4'));
      await db.rawUpdate('UPDATE standalone_recent SET opened_at = ? WHERE path = ?', [i, '/video$i.mp4']);
    }
    final files = await history.getAll();
    expect(files, hasLength(10));
    expect(files.first.path, '/video11.mp4');
    expect(files.last.path, '/video2.mp4');
    await history.save(const StandaloneRecent(path: '/video2.mp4', position: Duration(seconds: 5)));
    expect((await history.getAll()).first.path, '/video2.mp4');
    await history.remove('/video2.mp4');
    expect((await history.getAll()).any((item) => item.path == '/video2.mp4'), isFalse);
    await history.remove(null);
    expect(await _History(db).getAll(), isEmpty);
  });
}
