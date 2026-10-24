import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Startup uses DELETE mode and safely merges an existing WAL into the main file', () async {
    final directory = await Directory.systemTemp.createTemp('kuraku-journal-');
    final previousFactory = databaseFactoryOrNull;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService? service;
    addTearDown(() async {
      await service?.close();
      Get.reset();
      databaseFactoryOrNull = previousFactory;
      await directory.delete(recursive: true);
    });
    Get.put(AppSettingService()..appPath = directory.path);
    final catalogPath = '${directory.path}/r18_20261021.db';
    final catalog = await databaseFactoryFfi.openDatabase(catalogPath);
    for (final statement in (await File('test/fixtures/r18_catalog.sql').readAsString()).split(';')) {
      if (statement.trim().isNotEmpty) await catalog.execute(statement);
    }
    await catalog.close();
    service = await DBService().init();
    expect((await service.dbR18!.rawQuery('PRAGMA journal_mode')).single['journal_mode'], 'delete');
    var db = service.dbMain;
    expect((await db.rawQuery('PRAGMA journal_mode')).single['journal_mode'], 'delete');
    expect((await db.rawQuery('PRAGMA foreign_keys')).single['foreign_keys'], 1);
    final path = db.path;
    await service.close();
    service = null;

    final seed = await Process.run('python3', ['-B', '-c', r'''
import os, sqlite3, sys
connections = []
for path in sys.argv[1:]:
    db = sqlite3.connect(path)
    connections.append(db)
    assert db.execute('PRAGMA journal_mode=WAL').fetchone()[0] == 'wal'
    db.execute('PRAGMA wal_autocheckpoint=0')
    db.execute('CREATE TABLE journal_test (value TEXT)')
    db.execute("INSERT INTO journal_test VALUES ('Committed in WAL')")
    db.commit()
os._exit(0)
''', path, catalogPath]);
    expect(seed.exitCode, 0, reason: '${seed.stderr}');
    expect(await File('$path-wal').length(), greaterThan(0));

    service = await DBService().init();
    db = service.dbMain;
    expect((await service.dbR18!.rawQuery('PRAGMA journal_mode')).single['journal_mode'], 'delete');
    expect((await service.dbR18!.rawQuery('SELECT value FROM journal_test')).single['value'], 'Committed in WAL');
    expect((await db.rawQuery('PRAGMA journal_mode')).single['journal_mode'], 'delete');
    expect((await db.rawQuery('SELECT value FROM journal_test')).single['value'], 'Committed in WAL');
    expect((await db.rawQuery('PRAGMA quick_check')).single.values.single, 'ok');
    await db.insert('journal_test', {'value': 'Written in DELETE mode'});
    await service.close();
    service = null;
    for (final suffix in ['-wal', '-shm', '-journal']) {
      expect(await File('$path$suffix').exists(), isFalse);
    }
    service = await DBService().init();
    expect(await service.dbMain.query('journal_test'), hasLength(2));
  });

  for (final releaseLock in [true, false]) {
    test('Startup ${releaseLock ? 'waits for a temporary' : 'times out for a persistent'} external lock on an existing DELETE database', () async {
      final directory = await Directory.systemTemp.createTemp('kuraku-journal-lock-');
      final previousFactory = databaseFactoryOrNull;
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      DBService? service;
      Process? holder;
      Timer? release;
      addTearDown(() async {
        release?.cancel();
        holder?.kill();
        if (holder != null) await holder.exitCode;
        await service?.close();
        Get.reset();
        databaseFactoryOrNull = previousFactory;
        await directory.delete(recursive: true);
      });
      Get.put(AppSettingService()..appPath = directory.path);
      service = await DBService().init();
      final path = service.dbMain.path;
      await service.close();
      service = null;
      holder = await Process.start('python3', ['-B', '-u', '-c', r'''
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
assert db.execute('PRAGMA journal_mode').fetchone()[0] == 'delete'
db.execute('BEGIN EXCLUSIVE')
print('locked', flush=True)
sys.stdin.readline()
db.rollback()
db.close()
''', path]);
      expect(await holder.stdout.transform(utf8.decoder).transform(const LineSplitter()).first, 'locked');
      if (releaseLock) {
        release = Timer(const Duration(milliseconds: 300), () => holder!.stdin.writeln('release'));
      } else {
        final waiting = Stopwatch()..start();
        await expectLater(DBService().init(), throwsA(isA<DatabaseException>()
          .having((error) => error.getResultCode(), 'result code', 5)));
        expect(waiting.elapsedMilliseconds, greaterThanOrEqualTo(5000));
        holder.stdin.writeln('release');
        expect(await holder.exitCode, 0);
      }
      service = await DBService().init();
      expect(await holder.exitCode, 0);
      expect((await service.dbMain.rawQuery('PRAGMA journal_mode')).single['journal_mode'], 'delete');
      expect((await service.dbMain.rawQuery('PRAGMA busy_timeout')).single.values.single, 5000);
      expect((await service.dbMain.rawQuery('PRAGMA quick_check')).single.values.single, 'ok');
    });
  }

}
