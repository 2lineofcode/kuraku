import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/database/library_health_check.dart';
import 'package:kuraku/app/data/models/library_entity.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_test_database.dart';

Map<String, Object?> _video(String path) => {
  'video_path': path, 'video_code': 'ABC-001', 'title': 'Title', 'poster': 'poster.jpg',
  'release_date': '2026-01-01', 'duration': 60,
  'actress': '[{"name_romaji":"Jane"}]', 'category': '[{"category":"Drama"}]',
};

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final calls = <String>[];

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where,
      List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    calls.add(table);
    if (table == 'videos') {
      expect(where, 'is_deleted = 0');
      expect(columns, containsAll(['video_path', 'actress', 'category']));
    }
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected database write: $invocation');
}

void main() {
  late Directory folder;
  setUp(() async => folder = await Directory.systemTemp.createTemp('kuraku_health_'));
  tearDown(() async {
    await folder.delete(recursive: true);
    Get.reset();
  });

  test('healthy files have no issues and missing files are listed without mutation', () async {
    final file = await File('${folder.path}/video.mp4').writeAsBytes([1, 2, 3]);
    final rows = [_video(file.path), _video('${folder.path}/missing.mp4')];
    final issues = await LibraryHealthCheck.inspect([Library(rootFolder: folder.path)], rows, mountedRoots: {});
    expect(issues, hasLength(1));
    expect(issues.single.status, LibraryHealthStatus.missingFile);
    expect(issues.single.path, '${folder.path}/missing.mp4');
    expect(issues.single.details, isEmpty);
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(rows.first, _video(file.path));
  });

  test('empty files, directories and denied reads are unreadable, not missing', () async {
    final empty = await File('${folder.path}/empty.mp4').create();
    final denied = await File('${folder.path}/denied.mp4').writeAsBytes([1]);
    if (!Platform.isWindows) await Process.run('chmod', ['000', denied.path]);
    try {
      final issues = await LibraryHealthCheck.inspect([], [
        _video(empty.path), _video(folder.path), if (!Platform.isWindows) _video(denied.path),
      ], mountedRoots: {});
      expect(issues.every((issue) => issue.status == LibraryHealthStatus.unreadableFile), isTrue);
      expect(issues.length, Platform.isWindows ? 2 : 3);
    } finally {
      if (!Platform.isWindows) await Process.run('chmod', ['600', denied.path]);
    }
  });

  test('metadata can be incomplete independently of file availability, including malformed JSON', () async {
    final row = _video('${folder.path}/missing.mp4')..addAll({
      'video_code': ' ', 'title': 'null', 'poster': null, 'release_date': '', 'duration': 0,
      'actress': '[{"name_romaji":""}]', 'category': 'broken json',
    });
    final issues = await LibraryHealthCheck.inspect([], [row], mountedRoots: {});
    expect(issues.map((issue) => issue.status), [LibraryHealthStatus.incompleteMetadata, LibraryHealthStatus.missingFile]);
    expect(issues.first.details, ['video_code', 'title', 'poster', 'release_date', 'duration', 'actress', 'category']);
  });

  test('missing and unset library folders are reported even without video records', () async {
    final missing = '${folder.path}/gone';
    final issues = await LibraryHealthCheck.inspect([Library(rootFolder: missing), Library()], [], mountedRoots: {});
    expect(issues.map((issue) => issue.path), [missing, '']);
    expect(issues.every((issue) => issue.status == LibraryHealthStatus.missingFile), isTrue);
    expect(issues.first.details, ['Library folder']);
  });

  test('unmounted drives are counted once and their files are never marked missing', () async {
    final root = Platform.isWindows ? r'Z:\Movies' : Platform.isMacOS ? '/Volumes/KurakuHealthOffline/Movies' : '/mnt/KurakuHealthOffline/Movies';
    final issues = await LibraryHealthCheck.inspect([Library(rootFolder: root)], [
      _video('$root/one.mp4'), _video('$root/two.mp4')..['title'] = '',
    ], mountedRoots: {});
    expect(issues.where((issue) => issue.status == LibraryHealthStatus.offlineDrive), hasLength(1));
    expect(issues.where((issue) => issue.status == LibraryHealthStatus.missingFile), isEmpty);
    expect(issues.where((issue) => issue.status == LibraryHealthStatus.incompleteMetadata), hasLength(1));
  });

  test('missing files on a mounted drive remain missing', () async {
    if (Platform.isWindows) return;
    final drive = Platform.isMacOS ? '/Volumes/KurakuHealthMounted' : '/mnt/KurakuHealthMounted';
    final path = '$drive/Movies/missing.mp4';
    final issues = await LibraryHealthCheck.inspect([], [_video(path)], mountedRoots: {drive});
    expect(issues.single.status, LibraryHealthStatus.missingFile);
    expect(issues.single.path, path);
  });

  test('run reads active records only and never writes to the database', () async {
    final database = _Database();
    Get.put<DBService>(_Service()..dbMain = database);
    expect(await LibraryHealthCheck.run(), isEmpty);
    expect(database.calls, ['library', 'videos']);
  });

  test('delete missing files rechecks availability, rolls back failures and preserves other records', () async {
    final db = await SqliteTestDatabase.open();
    addTearDown(db.close);
    await db.execute('CREATE TABLE videos (id TEXT PRIMARY KEY, root_path TEXT, video_path TEXT, is_deleted INTEGER, updated_at TEXT)');
    Get.put<DBService>(_Service()..dbMain = db);
    final returned = await File('${folder.path}/returned.mp4').writeAsBytes([1]);
    final unreadable = await File('${folder.path}/empty.mp4').create();
    final offline = Platform.isWindows ? r'Z:\KurakuHealthOffline\video.mp4'
      : Platform.isMacOS ? '/Volumes/KurakuHealthOffline/video.mp4' : '/mnt/KurakuHealthOffline/video.mp4';
    final paths = {
      'a': '${folder.path}/a.mp4', 'b': '${folder.path}/b.mp4', 'returned': returned.path,
      'unreadable': unreadable.path, 'offline': offline, 'untouched': '${folder.path}/untouched.mp4',
      'deleted': '${folder.path}/deleted.mp4',
    };
    for (final entry in paths.entries) {
      await db.insert('videos', {'id': entry.key, 'root_path': folder.path, 'video_path': entry.value,
        'is_deleted': entry.key == 'deleted' ? 1 : 0, 'updated_at': 'original'});
    }
    final requested = paths.entries.where((entry) => entry.key != 'untouched').map((entry) => entry.value).toList();
    final revision = DBVideos.revision.value;
    await db.execute("CREATE TRIGGER fail_delete BEFORE UPDATE ON videos WHEN OLD.id = 'b' BEGIN SELECT RAISE(ABORT,'Write failed'); END");
    await expectLater(LibraryHealthCheck.deleteMissingFiles(requested), throwsA(isA<SqliteTestException>()));
    expect((await db.query('videos', where: 'is_deleted = 1')).single['id'], 'deleted');
    expect((await db.query('videos', where: 'id = ?', whereArgs: ['a'])).single['updated_at'], 'original');
    expect(DBVideos.revision.value, revision);
    await db.execute('DROP TRIGGER fail_delete');
    expect(await LibraryHealthCheck.deleteMissingFiles([...requested, paths['a']!, '', folder.path]), {paths['a'], paths['b']});
    expect(DBVideos.revision.value, revision + 1);
    expect((await db.query('videos', where: 'is_deleted = 1')).map((row) => row['id']), unorderedEquals(['a', 'b', 'deleted']));
    for (final id in ['returned', 'unreadable', 'offline', 'untouched', 'deleted']) {
      expect((await db.query('videos', where: 'id = ?', whereArgs: [id])).single['updated_at'], 'original');
    }
    expect(await returned.readAsBytes(), [1]);
    expect(await LibraryHealthCheck.deleteMissingFiles(requested), isEmpty);
    expect(await LibraryHealthCheck.deleteMissingFiles([]), isEmpty);
    expect(await LibraryHealthCheck.deleteMissingFiles(['${folder.path}/not-in-library.mp4']), isEmpty);
    expect(DBVideos.revision.value, revision + 1);
  });
}
