import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_identity.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  setUp(() async {
    documents = await Directory.systemTemp.createTemp('kuraku-identity-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => documents.path,
    );
  });
  tearDown(() async => documents.delete(recursive: true));

  test('Moves legacy data and re-encrypts all settings, preserving PIN and SQL drafts', () async {
    final legacy = await Directory(p.join(documents.path, 'JavIt')).create();
    final pref = GetSecureStorage(container: 'javit', password: 'JavIt', path: legacy.path);
    await pref.initStorage;
    await AppPref.savePreferences(pref, {
      '_kAppPin': {'salt': 'salt', 'hash': 'hash'}, '_kAppLanguage': 'id',
      'sql_tabs': {'tabs': [{'source': 'javit.db', 'drafts': {'javit.db': 'SELECT \'javit.db\''},
        'parameters': {'javit.db': '{"id":1}'}, 'loaded': {'javit.db': {'name': 'Saved', 'prefix': ''}}}]},
      'sql_snippets': {'javit.db': {'Saved': 'SELECT * FROM videos'}},
    });
    final encrypted = await File(p.join(legacy.path, 'javit.gs')).readAsBytes();
    await File(p.join(legacy.path, 'javit.bak')).writeAsBytes(encrypted);
    for (final name in ['javit.db', 'javit.db-wal', 'javit.db-shm', 'javit.dio', 'r18_20261006.db', 'pending-restore.json']) {
      await File(p.join(legacy.path, name)).writeAsString(name);
    }
    final bin = await Directory(p.join(legacy.path, 'semantic_runtime', 'venv', 'bin')).create(recursive: true);
    await File(p.join(bin.path, 'pip')).writeAsString('#!${legacy.path}/semantic_runtime/venv/bin/python');
    final target = await AppIdentity.migrate(documents, 'kuraku');
    final migrated = GetSecureStorage(container: 'kuraku', password: 'kuraku', path: target);
    await migrated.initStorage;
    expect(migrated.read('_kAppPin'), {'salt': 'salt', 'hash': 'hash'});
    expect(migrated.read('_kAppLanguage'), 'id');
    expect(migrated.read<Map>('sql_snippets'), {'kuraku.db': {'Saved': 'SELECT * FROM videos'}});
    final tab = (migrated.read<Map>('sql_tabs')!['tabs'] as List).single as Map;
    expect(tab['source'], 'kuraku.db');
    expect(tab['drafts'], {'kuraku.db': 'SELECT \'javit.db\''});
    expect(tab['parameters'], {'kuraku.db': '{"id":1}'});
    expect((tab['loaded'] as Map).keys, ['kuraku.db']);
    for (final name in ['kuraku.db', 'kuraku.db-wal', 'kuraku.db-shm', 'kuraku.dio', 'r18_20261006.db', 'pending-restore.json']) {
      expect(await File(p.join(target, name)).exists(), isTrue);
    }
    expect(await File(p.join(target, 'semantic_runtime', 'venv', 'bin', 'pip')).readAsString(), '#!$target/semantic_runtime/venv/bin/python');
    expect(await legacy.exists(), isFalse);
    expect(await File(p.join(target, 'javit.gs')).exists(), isFalse);
    final saved = await File(p.join(target, 'kuraku.gs')).readAsBytes();
    expect(saved, isNot(encrypted));
    expect(await AppIdentity.migrate(documents, 'kuraku'), target);
    expect(await File(p.join(target, 'kuraku.gs')).readAsBytes(), saved);
  });

  test('Refuses to overwrite populated data folders or conflicting database files', () async {
    final legacy = await Directory(p.join(documents.path, 'JavIt')).create();
    final current = await Directory(p.join(documents.path, 'kuraku')).create();
    await File(p.join(legacy.path, 'javit.db')).writeAsString('old');
    await File(p.join(current.path, 'kuraku.db')).writeAsString('new');
    await expectLater(AppIdentity.migrate(documents, 'kuraku'), throwsStateError);
    expect(await File(p.join(legacy.path, 'javit.db')).readAsString(), 'old');
    expect(await File(p.join(current.path, 'kuraku.db')).readAsString(), 'new');
    await legacy.delete(recursive: true);
    await File(p.join(current.path, 'javit.db')).writeAsString('old');
    await expectLater(AppIdentity.migrate(documents, 'kuraku'), throwsStateError);
    expect(await File(p.join(current.path, 'javit.db')).readAsString(), 'old');
  });

  test('Corrupt storage fails closed; valid backup recovers and migration can resume', () async {
    final legacy = await Directory(p.join(documents.path, 'JavIt')).create();
    await File(p.join(legacy.path, 'javit.gs')).writeAsString('broken');
    await expectLater(AppIdentity.migrate(documents, 'kuraku'), throwsFormatException);
    final current = Directory(p.join(documents.path, 'kuraku'));
    expect(await File(p.join(current.path, 'kuraku.gs')).exists(), isFalse);
    expect(await File(p.join(current.path, 'javit.gs')).readAsString(), 'broken');
    await File(p.join(current.path, 'javit.bak')).writeAsString('{"_kAppLanguage":"id"}');
    await AppIdentity.migrate(documents, 'kuraku');
    expect(await File(p.join(current.path, 'kuraku.gs')).exists(), isTrue);
    expect(await File(p.join(current.path, 'javit.gs')).exists(), isFalse);
  });

  test('Fresh install, empty destination, and interrupted sidecar moves are supported', () async {
    final target = await AppIdentity.migrate(documents, 'kuraku');
    expect(await Directory(target).exists(), isTrue);
    final legacy = await Directory(p.join(documents.path, 'JavIt')).create();
    await File(p.join(legacy.path, 'javit.db')).writeAsString('database');
    await AppIdentity.migrate(documents, 'kuraku');
    await File(p.join(target, 'kuraku.db')).rename(p.join(target, 'javit.db'));
    await File(p.join(target, 'kuraku.db-wal')).writeAsString('wal');
    await AppIdentity.migrate(documents, 'kuraku');
    expect(await File(p.join(target, 'kuraku.db')).readAsString(), 'database');
    expect(await File(p.join(target, 'kuraku.db-wal')).readAsString(), 'wal');
  });

  test('Legacy backup-only preferences recover without creating empty settings', () async {
    final legacy = await Directory(p.join(documents.path, 'JavIt')).create();
    await File(p.join(legacy.path, 'javit.bak')).writeAsString('{"_kAppLanguage":"id"}');
    final target = await AppIdentity.migrate(documents, 'kuraku');
    expect(await File(p.join(target, 'kuraku.gs')).exists(), isTrue);
    expect(await File(p.join(target, 'javit.bak')).exists(), isFalse);
  });

  test('Legacy chat actions and covers remain usable without changing stored messages', () {
    expect(AppIdentity.migrateChatLinks('[ABP](javit-video:ABP-001) ![cover](javit-cover:abp.jpg) '
      '[translate](javit-translate:title) [similar](javit-similar:ABP-001)'),
      '[ABP](kuraku-video:ABP-001) ![cover](kuraku-cover:abp.jpg) [translate](kuraku-translate:title) [similar](kuraku-similar:ABP-001)');
  });

  test('macOS support/cache directories and old thumbnail files migrate without overwriting', () async {
    final old = await Directory(p.join(documents.path, 'com.example.javit')).create();
    final current = await Directory(p.join(documents.path, 'com.example.kuraku')).create();
    await File(p.join(old.path, 'javitThumbnail.db')).writeAsString('cache');
    await AppIdentity.migrateMacOSDirectory(current);
    expect(await File(p.join(current.path, 'kurakuThumbnail.db')).readAsString(), 'cache');
    expect(await old.exists(), isFalse);
    await AppIdentity.migrateMacOSDirectory(current);
    await old.create();
    await File(p.join(old.path, 'original')).writeAsString('keep');
    await expectLater(AppIdentity.migrateMacOSDirectory(current), throwsStateError);
    expect(await File(p.join(old.path, 'original')).readAsString(), 'keep');
  });
}
