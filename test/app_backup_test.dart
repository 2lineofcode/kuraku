import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/app_backup.dart';
import 'package:kuraku/app/modules/home/page_settings/page_settings_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:sqflite_common/src/factory.dart';
import 'package:toastification/toastification.dart';

import 'sqlite_test_database.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  bool failSave = false;
  bool failQueuedSave = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  void writeInMemory(String key, dynamic value) { values[key] = value; }
  @override
  Future<void> save() async {
    if (failSave) { failSave = false; throw StateError('Disk full'); }
    if (failQueuedSave) {
      failQueuedSave = false;
      scheduleMicrotask(() { unawaited(queue.add<void>(() async { throw const FileSystemException('Disk full'); })); });
    }
  }
  @override
  final queue = GetQueue();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends PageSettingsController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.uri);
  @override
  final Uri uri;
  @override
  String get name => p.basename(uri.toFilePath());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Picker extends FilePickerPlatform {
  _Picker(this.file);
  final File file;
  @override
  Future<List<PlatformFile>> pickFiles({String? dialogTitle, String? initialDirectory, FileType type = FileType.any,
    List<String>? allowedExtensions, Function(FilePickerStatus)? onFileLoading, int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(), DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(), LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions()}) async => [_PickedFile(file.uri)];
}

Future<SqliteTestDatabase> _database() async {
  final db = await SqliteTestDatabase.open();
  await db.transaction((_) async {
    await DBService.onCreate(db, DBUpdate.version);
    await db.setVersion(DBUpdate.version);
  });
  return db;
}

class _Factory implements SqfliteDatabaseFactory {
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) => _database();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _seed(Database db) async {
  await db.execute("INSERT INTO library(id,root_folder,videos) VALUES ('l1','/offline','[\"/offline/a.mp4\"]')");
  await db.execute("INSERT INTO videos(id,root_path,video_path,title,is_favorite,view_count,actress,category,screenshot) VALUES ('v1','/offline','/offline/a.mp4','Keep metadata',1,3,'[{\"id\":1,\"name_romaji\":\"Name\"}]','[{\"id\":1,\"category\":\"Drama\"}]','[\"https://example.test/image.jpg\"]')");
  await db.execute("INSERT INTO videos(id,root_path,video_path,is_deleted) VALUES ('deleted','/offline','/offline/deleted.mp4',1)");
  await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Saved')");
  await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','2026-01-01')");
  await db.execute("INSERT INTO watch_session VALUES ('s1','v1','TEST-001',42,'2026-01-01')");
  await db.execute("INSERT INTO watch_session VALUES ('s2','missing','OLD-001',10,'2026-01-02')");
  await db.execute("INSERT INTO todo(id,title) VALUES ('t1','Saved todo')");
  await db.insert('download_log', {'id': 'd1', 'payload': jsonEncode({'filename': 'a.mp4', 'url': 'https://example.test/a', 'dir': '/offline', 'ev': 'completed', 'output_path': '/offline/a.mp4'})});
  await db.insert('video_file_identity', {'video_id': 'v1', 'filesize': 42, 'modified_at': 1, 'fingerprint': 'a' * 64});
  await db.execute("INSERT INTO chat_conversation(id,title,draft,created_at,updated_at,last_activity_at,is_pinned) VALUES ('c1','Saved chat','Draft','2026-01-01','2026-01-01','2026-01-01',1)");
  await db.execute("INSERT INTO chat_message(id,conversation_id,position,role,content,status,created_at,updated_at) VALUES ('m1','c1',1,'user','Saved message','completed','2026-01-01','2026-01-01')");
  await db.execute("INSERT INTO chat_translation VALUES ('Title','id','Judul','2026-01-01')");
  await db.execute("UPDATE profile SET name='Saved profile',total_watch_duration=52");
  await db.execute("INSERT INTO relapse_event(id,occurred_on) VALUES ('r1','2026-01-01')");
  await db.execute("INSERT INTO historical(type,query,updated_at) VALUES ('search','Keep',1)");
  await db.execute("INSERT INTO achievement_unlock(id,achievement_key,title,unlocked_at) VALUES ('a1','first','First','2026-01-01')");
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteTestDatabase db;
  late _Preferences pref;
  late Directory directory;
  setUpAll(() { databaseFactory = _Factory(); });
  tearDownAll(() { databaseFactory = null; });
  setUp(() async {
    db = await _database();
    pref = _Preferences()..values.addAll({
      '_kAppLanguage': 'id', '_kAppTheme': 'light', '_kPlayerVolume': 0.5,
      '_kExplorePins': ['actress'], '_kAppPin': {'hash': 'secret'},
      '_kDownloadOptions': {'mode': 'extract', 'concurrency': '8', 'headless': true},
      '_kSearchTabs': {'tabs': [{'query': 'Saved search', 'pinned': true}], 'activeTab': 0},
      '_kExploreTabs': {'tabs': [{'leftQuery': 'Actress'}]}, '_kDownloadTabs': {'tabs': [{'query': '/search TEST-001'}]},
      'sql_tabs': {'tabs': [{'drafts': {'kuraku.db': 'SELECT * FROM todo'}}]},
      'sql_snippets': {'kuraku.db': {'Saved': 'SELECT * FROM todo'}}, 'chat_active_id': 'c1',
      '_kAppCart': [{'id': 'cart1', 'video_code': 'TEST-001'}],
    });
    directory = await Directory.systemTemp.createTemp('backup-test-');
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('round trip preserves metadata, relationships, history and settings without video files or PIN', () async {
    await _seed(db);
    final backup = await AppBackup.capture(db, pref);
    expect(backup.favorites, 1);
    expect(backup.count('watch_session'), 2);
    final storedTables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'video_embeddings'");
    expect(AppBackup.tables.toSet(), storedTables.map((row) => row['name']).toSet());
    expect((jsonDecode(backup.encode()) as Map)['tables']['download_log'].single.keys,
      unorderedEquals(['id', 'payload', 'created_at', 'updated_at']));
    expect(backup.encode(), isNot(contains('secret')));
    final file = File(p.join(directory.path, 'backup.json'));
    await backup.write(file);
    final restored = await AppBackup.read(file);
    final scratch = await _database();
    try { await restored.validate(database: scratch); } finally { await scratch.close(); }
    final before = {for (final table in AppBackup.tables) table: await db.query(table, orderBy: '1')};
    final savedSettings = {for (final key in AppBackup.settingKeys) key: pref.read(key)};
    for (final table in ['todo', 'download_log', 'chat_conversation', 'chat_translation', 'video_file_identity']) { await db.delete(table); }
    for (final key in AppBackup.settingKeys) { pref.values[key] = null; }
    await db.execute("UPDATE videos SET title='Changed',is_favorite=0");
    await db.delete('playlist');
    await db.delete('watch_session');
    pref.values['_kAppLanguage'] = 'en';
    pref.values['_kAppPin'] = 'current PIN';
    await restored.apply(db, pref);
    for (final table in AppBackup.tables) expect(await db.query(table, orderBy: '1'), before[table], reason: table);
    expect(pref.values['_kAppLanguage'], 'id');
    expect(pref.values['_kDownloadOptions'], {'mode': 'extract', 'concurrency': '8', 'headless': true});
    expect(pref.values['_kAppPin'], 'current PIN');
    for (final key in AppBackup.settingKeys) { expect(pref.values[key], savedSettings[key], reason: key); }
    expect(await File('/offline/a.mp4').exists(), isFalse);
    expect(await db.query('todo'), hasLength(1));
    expect(await db.query('download_log'), hasLength(1));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('restore marks in-flight chat responses interrupted', () async {
    await _seed(db);
    await db.update('chat_message', {'role': 'assistant', 'status': 'streaming'});
    final backup = await AppBackup.capture(db, pref);
    await backup.validate();
    await backup.apply(db, pref);
    expect((await db.query('chat_message')).single['status'], 'failed');
  });

  test('Home section preferences survive backup and restore with their original order', () async {
    final order = ['_kHomeSecNewRelease', '_kHomeSecForYou', '_kHomeSecNewAdd', '_kHomeSecFavorite',
      '_kHomeSecRecommendation', '_kHomeSecRandom', '_kHomeSecMostWatch', '_kHomeSecNeverWatch', '_kHomeSecOldest'];
    pref.values['_kHomeOrderList'] = order;
    final backup = await AppBackup.capture(db, pref);
    final decoded = AppBackup.decode(backup.encode());
    await decoded.validate();
    pref.values['_kHomeOrderList'] = ['_kHomeSecFavorite'];
    await decoded.apply(db, pref);
    expect(pref.values['_kHomeOrderList'], order);
  });


  test('current backups preserve image albums', () async {
    await _seed(db);
    await db.update('library', {'images': jsonEncode(['/offline/cover.jpg'])});
    final current = await AppBackup.capture(db, pref);
    await current.validate();
    await db.update('library', {'images': '[]'});
    await current.apply(db, pref);
    expect((await db.query('library')).first['images'], jsonEncode(['/offline/cover.jpg']));
  });

  test('invalid envelope, missing data and invalid settings are rejected', () async {
    final original = (await AppBackup.capture(db, pref)).encode();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (data) => data['format'] = 'other',
      (data) => data['version'] = 99,
      (data) => data['version'] = 1,
      (data) => data['database_version'] = 17,
      (data) => data['database_version'] = DBUpdate.version + 1,
      (data) => data['created_at'] = 'invalid',
      (data) => data['tables'].remove('videos'),
      (data) => data['tables']['unexpected'] = [],
      (data) => data['tables']['profile'] = [],
      (data) => data['settings'].remove('_kAppTheme'),
      (data) => data['settings']['_kAppPin'] = 'overwrite',
      (data) => data['settings']['_kAppLanguage'] = 'unknown',
      (data) => data['settings']['_kAppAccent'] = 'invalid',
      (data) => data['settings']['_kPlayerVolume'] = 2,
      (data) => data['settings']['_kPlayerSeekShort'] = -1,
      (data) => data['settings']['_kHomeOrderList'] = [10],
      (data) => data['settings']['_kDownloadOptions'] = {'headless': 'yes'},
      (data) => data['tables'].remove('todo'),
      (data) => data['settings'].remove('sql_snippets'),
      (data) => data['settings']['_kAppCart'] = [1],
      (data) => data['settings']['_kSearchTabs'] = {'tabs': [1]},
      (data) => data['settings']['sql_snippets'] = {'kuraku.db': {'Bad': 1}},
    ]) {
      final data = jsonDecode(original) as Map<String, dynamic>;
      mutate(data);
      expect(() => AppBackup.decode(jsonEncode(data)), throwsFormatException);
    }
    expect(() => AppBackup.decode('{broken'), throwsFormatException);
  });

  test('schema validation rejects invalid rows, JSON members and foreign keys without mutation', () async {
    await _seed(db);
    final original = (await AppBackup.capture(db, pref)).encode();
    final before = (await AppBackup.capture(db, pref)).encode();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (data) => data['tables']['videos'][0]['view_count'] = -1,
      (data) => data['tables']['videos'][0]['duration'] = '42',
      (data) => data['tables']['videos'][0]['unknown_column'] = 'x',
      (data) => data['tables']['videos'][0]['actress'] = '[1]',
      (data) => data['tables']['videos'][0]['screenshot'] = '[1]',
      (data) => data['tables']['library'][0]['videos'] = '[1]',
      (data) => data['tables']['playlist_item'][0]['video_id'] = 'unknown',
      (data) => data['tables']['watch_session'][0]['created_at'] = 'invalid date',
      (data) => data['tables']['videos'].add(data['tables']['videos'][0]),
      (data) => data['tables']['todo'][0]['title'] = '',
      (data) => data['tables']['download_log'][0]['payload'] = '[]',
      (data) => data['tables']['download_log'][0]['filename'] = 'generated',
      (data) => data['tables']['chat_message'][0]['conversation_id'] = 'missing',
      (data) => data['tables']['video_file_identity'][0]['video_id'] = 'missing',
    ]) {
      final data = jsonDecode(original) as Map<String, dynamic>;
      mutate(data);
      await expectLater(AppBackup.decode(jsonEncode(data)).validate(database: db), throwsA(anything));
    }
    // Ignore the newly captured timestamp when checking preservation.
    final after = jsonDecode((await AppBackup.capture(db, pref)).encode()) as Map;
    final saved = jsonDecode(before) as Map;
    expect(after['tables'], saved['tables']);
    expect(after['settings'], saved['settings']);
  });

  test('settings failure rolls database and preferences back', () async {
    final empty = await AppBackup.capture(db, pref);
    await _seed(db);
    pref.values['_kAppLanguage'] = 'en';
    pref.failSave = true;
    await expectLater(empty.apply(db, pref), throwsStateError);
    expect(await db.query('videos'), hasLength(2));
    expect(await db.query('playlist_item'), hasLength(1));
    expect(pref.values['_kAppLanguage'], 'en');
  });

  test('detached secure-storage flush failure also rolls database and preferences back', () async {
    final empty = await AppBackup.capture(db, pref);
    await _seed(db);
    pref.values['_kAppLanguage'] = 'en';
    pref.failQueuedSave = true;
    await expectLater(empty.apply(db, pref), throwsA(isA<FileSystemException>()));
    expect(await db.query('videos'), hasLength(2));
    expect(await db.query('playlist_item'), hasLength(1));
    expect(pref.values['_kAppLanguage'], 'en');
  });

  test('startup validates pending restore, makes a recovery backup, and applies empty tables', () async {
    final backup = await AppBackup.capture(db, pref);
    await backup.write(File(p.join(directory.path, 'pending-restore.json')));
    await _seed(db);
    pref.values['_kAppLanguage'] = 'en';
    await AppBackup.applyPending(directory.path, db, pref);
    expect(await db.query('videos'), isEmpty);
    expect(await db.query('playlist_item'), isEmpty);
    for (final table in ['todo', 'download_log', 'chat_conversation', 'chat_message', 'chat_translation', 'video_file_identity']) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    expect(pref.values['_kAppLanguage'], 'id');
    final recovery = directory.listSync().whereType<File>().single;
    expect(p.basename(recovery.path), startsWith('recovery-'));
    expect((await AppBackup.read(recovery)).count('videos'), 2);
    expect((await AppBackup.read(recovery)).count('watch_session'), 2);
    final recovered = await AppBackup.read(recovery);
    await recovered.apply(db, pref);
    for (final table in ['todo', 'download_log', 'chat_conversation', 'chat_message', 'chat_translation', 'video_file_identity']) {
      expect(await db.query(table), hasLength(1), reason: table);
    }
  });

  test('startup recovers an interrupted restore before continuing', () async {
    await _seed(db);
    final previous = await AppBackup.capture(db, pref);
    await previous.write(File(p.join(directory.path, 'restore-journal.json')));
    await db.execute("UPDATE videos SET title='Partial restore'");
    await db.delete('playlist');
    pref.values['_kAppLanguage'] = 'en';
    await AppBackup.applyPending(directory.path, db, pref);
    expect((await db.query('videos', where: 'id = ?', whereArgs: ['v1'])).single['title'], 'Keep metadata');
    expect(await db.query('playlist_item'), hasLength(1));
    expect(pref.values['_kAppLanguage'], 'id');
    expect(directory.listSync(), isEmpty);
  });

  test('invalid pending backup preserves existing data and creates no recovery files', () async {
    await _seed(db);
    final pending = File(p.join(directory.path, 'pending-restore.json'));
    await pending.writeAsString('{}');
    await expectLater(AppBackup.applyPending(directory.path, db, pref), throwsFormatException);
    expect(await db.query('videos'), hasLength(2));
    expect(directory.listSync(), hasLength(1));
  });
  testWidgets('restore preview allows cancellation and confirmation only stages the selected backup', (tester) async {
    Get.testMode = true;
    final originalPicker = FilePickerPlatform.instance;
    final service = Get.put<AppSettingService>(AppSettingService()..pref = pref..appPath = directory.path);
    Get.put<DBService>(DBService()..dbMain = db);
    final controller = Get.put<PageSettingsController>(_Settings());
    addTearDown(() {
      FilePickerPlatform.instance = originalPicker;
      service.onClose();
      Get.reset();
      Get.clearTranslations();
    });
    final file = File(p.join(directory.path, 'selected.json'));
    await tester.runAsync(() async {
      await _seed(db);
      await (await AppBackup.capture(db, pref)).write(file);
      await db.delete('playlist');
    });
    FilePickerPlatform.instance = _Picker(file);
    await tester.pumpWidget(GetMaterialApp(translations: AppTranslations(), locale: const Locale('en'),
      builder: (context, child) => ToastificationWrapper(child: child!),
      home: Scaffold(body: TextButton(onPressed: controller.restoreBackup, child: const Text('Open restore')))));
    for (final confirm in [false, true]) {
      await tester.runAsync(() => tester.tap(find.text('Open restore')));
      for (var attempt = 0; attempt < 100 && find.text('Restore Preview').evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Restore Preview'), findsOneWidget);
      expect(find.text('Playlists: 0 → 1'), findsOneWidget);
      expect(find.text('Favorites: 1 → 1'), findsOneWidget);
      expect(find.textContaining('recovery backup'), findsOneWidget);
      await tester.ensureVisible(find.text(confirm ? 'Restore on next startup' : 'Cancel'));
      await tester.runAsync(() => tester.tap(find.text(confirm ? 'Restore on next startup' : 'Cancel')));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 100 && controller.backupBusy.value; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(find.text('Restore Preview'), findsNothing, reason: 'confirm=$confirm navigator=${Get.key.currentState?.canPop()}');
      expect(controller.backupBusy.value, isFalse);
      await tester.runAsync(() async {
        expect(await File(p.join(directory.path, 'pending-restore.json')).exists(), confirm);
        expect(await db.query('playlist'), isEmpty);
      });
      await tester.pumpAndSettle();
      expect(controller.restorePending.value, confirm);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
