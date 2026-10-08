import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/_update_db.dart';
import 'package:javit/app/data/database/db_library.dart';
import 'package:javit/app/data/database/db_videos.dart';
import 'package:javit/app/data/database/library_reconciler.dart';
import 'package:javit/app/data/database/library_relocation.dart';
import 'package:javit/app/data/models/library_entity.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_library.dart';
import 'package:javit/app/modules/home/page_search/page_search_tab.dart';
import 'package:javit/app/utils/helper_file_picker.dart';
import 'package:javit/app/utils/video_file_identity.dart';

import 'sqlite_test_database.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Home extends HomeController {
  int refreshes = 0;
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  void onReady() {}
  @override
  Future<void> updateFooterSummary() async {}
  @override
  Future<void> refreshVideoContent() async { refreshes++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteTestDatabase db;
  late Directory folder;
  late Directory internal;
  late Directory external;

  setUp(() async {
    db = await SqliteTestDatabase.open();
    await DBService.onCreate(db, DBUpdate.version);
    Get.put<DBService>(_Service()..dbMain = db);
    folder = await Directory.systemTemp.createTemp('javit-relocate-');
    internal = Directory('${folder.path}/internal')..createSync();
    external = Directory('${folder.path}/external')..createSync();
  });
  tearDown(() async {
    await HomePanelLibrary.stopAutoRescanWatcher();
    Get.reset();
    await db.close();
    folder.deleteSync(recursive: true);
  });

  File video(Directory root, String name, {int marker = 1, int size = 12 * 1024 * 1024}) {
    final file = File('${root.path}/$name');
    final handle = file.openSync(mode: FileMode.write);
    handle.truncateSync(size);
    handle.writeByteSync(marker);
    handle.closeSync();
    return file;
  }

  Future<List<Videos>> prepare(Library library) async => [
    for (final path in library.videos ?? <String>[])
      Videos(rootPath: library.rootFolder, videoPath: path, title: 'Imported'),
  ];

  Future<LibraryScanResult> scan({List<Directory>? roots, Future<List<Videos>> Function(Library)? prepareVideos}) async {
    final snapshots = <Library>[];
    for (final root in roots ?? [internal, external]) {
      final current = await DBLibrary.getByRootFolder(root.path);
      final scanned = (await HelperFilePicker.scanFolderAndSubFolder(root.path))!;
      if (current.isNotEmpty) {
        scanned.id = current.single.id;
        scanned.createdAt = current.single.createdAt;
      }
      snapshots.add(scanned);
    }
    return LibraryReconciler.reconcile(snapshots, prepareVideos: prepareVideos ?? prepare);
  }

  Future<void> seed(File file, {String id = 'original', bool fingerprint = true}) async {
    await db.execute('INSERT INTO videos(id,root_path,video_path,title,view_count,is_favorite,filesize) VALUES (?,?,?,?,9,1,?)',
      [id, file.parent.path, file.path, 'Keep title', file.lengthSync()]);
    await db.execute("INSERT OR IGNORE INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1',?,'created')", [id]);
    await db.execute("INSERT INTO watch_session VALUES (?,?,'TEST-001',600,'2026-10-08')", ['watch-$id', id]);
    await db.execute("INSERT INTO video_embeddings(video_id,source_text,embedding,model) VALUES (?,'Keep embedding',?,'test')",
      [id, Uint8List.fromList([0, 0, 0, 0])]);
    if (fingerprint) await scan();
  }

  Future<Library> relocationSource() async {
    for (final library in await DBLibrary.getByRootFolder(external.path)) { await DBLibrary.delete(library); }
    return (await DBLibrary.getByRootFolder(internal.path)).single;
  }

  test('relocation preview is read-only and preserves nested, missing and soft-deleted records from an offline root', () async {
    final nested = Directory('${internal.path}/日本語 folder')..createSync();
    final source = video(nested, 'a .mp4');
    await seed(source);
    final missing = video(internal, 'missing.mp4', marker: 2);
    await seed(missing, id: 'missing');
    final deleted = video(internal, 'deleted.mp4', marker: 3);
    await seed(deleted, id: 'deleted');
    await DBVideos.delete((await DBVideos.getByVideoPath(deleted.path))!);
    final library = await relocationSource();
    final targetFolder = Directory('${external.path}/日本語 folder')..createSync();
    source.copySync('${targetFolder.path}/a .mp4');
    deleted.copySync('${external.path}/deleted.mp4');
    internal.deleteSync(recursive: true);
    final before = await db.query('videos', orderBy: 'id');
    final preview = await LibraryRelocation.preview(library, external.path);
    expect([preview.count(RelocationStatus.matched), preview.count(RelocationStatus.missing)], [2, 1]);
    expect(preview.canApply, isTrue);
    expect(await db.query('videos', orderBy: 'id'), before);
    expect((await DBLibrary.getAll()).single.rootFolder, internal.path);
    await preview.apply();
    final saved = await db.query('videos', orderBy: 'id');
    for (var i = 0; i < before.length; i++) {
      expect(saved[i], {...before[i], 'root_path': external.path,
        'video_path': (before[i]['video_path'] as String).replaceFirst(internal.path, external.path),
        'updated_at': saved[i]['updated_at']});
    }
    final relocated = (await DBLibrary.getAll()).single;
    expect([relocated.id, relocated.alias, relocated.createdAt], [library.id, library.alias, library.createdAt]);
    expect(relocated.rootFolder, external.path);
    expect(relocated.totalVideo, 2);
    expect(await db.query('playlist_item'), hasLength(3));
    expect(await db.query('watch_session'), hasLength(3));
    expect(await db.query('video_embeddings'), hasLength(3));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(File('${external.path}/missing.mp4').existsSync(), isFalse);
    expect(File('${targetFolder.path}/a .mp4').existsSync(), isTrue);
  });

  test('legacy offline relocation labels path-only matches and retains all metadata', () async {
    final source = video(internal, 'a.mp4');
    await seed(source, fingerprint: false);
    final library = Library(rootFolder: internal.path, alias: 'Keep alias');
    await DBLibrary.add(library);
    source.renameSync('${external.path}/a.mp4');
    final preview = await LibraryRelocation.preview(library, external.path);
    expect(preview.entries.single.status, RelocationStatus.unverified);
    await db.execute("UPDATE videos SET view_count=15 WHERE id='original'");
    await preview.apply();
    final saved = (await DBVideos.getAll()).single;
    expect([saved.id, saved.viewCount, saved.isFavorite, saved.title], ['original', 15, 1, 'Keep title']);
    expect((await db.query('video_file_identity')).single['video_id'], 'original');
  });

  test('relocation blocks changed content, tracked destinations and previews without matches', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final library = await relocationSource();
    final empty = await LibraryRelocation.preview(library, external.path);
    expect(empty.entries.single.status, RelocationStatus.missing);
    expect(empty.canApply, isFalse);
    await expectLater(empty.apply(), throwsStateError);
    final target = video(external, 'a.mp4', marker: 2);
    final mismatch = await LibraryRelocation.preview(library, external.path);
    expect(mismatch.entries.single.reason, 'The destination content differs from the original.');
    expect(mismatch.canApply, isFalse);
    source.copySync(target.path);
    await DBVideos.addBulk([Videos(rootPath: '/other', videoPath: target.path)]);
    final collision = await LibraryRelocation.preview(library, external.path);
    expect(collision.entries.single.reason, 'The destination path is already tracked.');
    expect(collision.canApply, isFalse);
    expect((await DBLibrary.getAll()).single.rootFolder, internal.path);
    expect(await DBVideos.getAll(), hasLength(2));
  });

  test('relocation validates roots, including registered descendants and symlink aliases', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final library = await relocationSource();
    await expectLater(LibraryRelocation.preview(library, internal.path), throwsStateError);
    await expectLater(LibraryRelocation.preview(library, ''), throwsStateError);
    await expectLater(LibraryRelocation.preview(library, '${folder.path}/offline'), throwsA(isA<FileSystemException>()));
    final link = Link('${folder.path}/alias')..createSync(internal.path);
    await expectLater(LibraryRelocation.preview(library, link.path), throwsStateError);
    final nested = Directory('${external.path}/registered')..createSync();
    await DBLibrary.add(Library(rootFolder: nested.path));
    await expectLater(LibraryRelocation.preview(library, external.path), throwsStateError);
    await expectLater(LibraryRelocation.preview(library, '${nested.path}/child'), throwsStateError);
  });

  test('relocation rejects stale filesystem and database previews without changing the root', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final library = await relocationSource();
    final target = source.copySync('${external.path}/a.mp4');
    final preview = await LibraryRelocation.preview(library, external.path);
    target.setLastModifiedSync(DateTime(2030));
    await expectLater(preview.apply(), throwsStateError);
    final fresh = await LibraryRelocation.preview(library, external.path);
    await DBVideos.addBulk([Videos(rootPath: internal.path, videoPath: '${internal.path}/new.mp4')]);
    await expectLater(fresh.apply(), throwsStateError);
    expect((await DBLibrary.getAll()).single.rootFolder, internal.path);
    expect((await DBVideos.getByVideoPath(source.path))!.id, 'original');
  });

  test('a failed relocation rolls back the root, paths and identity cache together', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final second = video(internal, 'b.mp4', marker: 2);
    await seed(second, id: 'second');
    final library = await relocationSource();
    source.copySync('${external.path}/a.mp4');
    second.copySync('${external.path}/b.mp4');
    final preview = await LibraryRelocation.preview(library, external.path);
    final before = <String, List<Map<String, Object?>>>{};
    for (final table in ['library', 'videos', 'video_file_identity', 'playlist_item', 'watch_session', 'video_embeddings']) {
      before[table] = await db.query(table, orderBy: '1');
    }
    await db.execute("CREATE TRIGGER fail_relocation BEFORE UPDATE OF video_path ON videos WHEN OLD.id='second' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(preview.apply(), throwsA(isA<SqliteTestException>()));
    for (final entry in before.entries) { expect(await db.query(entry.key, orderBy: '1'), entry.value, reason: entry.key); }
    await db.execute('DROP TRIGGER fail_relocation');
    await preview.apply();
    expect((await DBLibrary.getAll()).single.rootFolder, external.path);
  });

  test('queued rescans reload relocated roots and do not undo a successful relocation', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final library = await relocationSource();
    source.copySync('${external.path}/a.mp4');
    final home = Get.put<HomeController>(_Home()) as _Home;
    await HomePanelLibrary.startAutoRescanWatcher();
    final preview = await LibraryRelocation.preview(library, external.path);
    final relocation = HomePanelLibrary.relocateLibrary(preview);
    final rescan = HomePanelLibrary.doRescanAllVideoFromLibrary([library], showSummaryToast: false);
    await relocation;
    await rescan;
    expect((await DBLibrary.getAll()).single.rootFolder, external.path);
    expect((await DBVideos.getAll()).single.id, 'original');
    expect((await DBVideos.getAll()).single.videoPath, '${external.path}/a.mp4');
    expect(home.refreshes, greaterThan(0));
    expect(HomePanelLibrary.canStartFileDrag, isTrue);
  });

  test('source-first move survives repeated empty scans and a renamed destination', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final before = (await db.query('videos')).single;
    final contents = source.readAsBytesSync();
    source.deleteSync();
    for (var i = 0; i < 3; i++) {
      expect((await scan()).missing, 1);
      expect((await db.query('videos')).single, before);
      expect(await db.query('playlist_item'), hasLength(1));
    }
    final destination = File('${external.path}/日本語 renamed .mp4')..writeAsBytesSync(contents);
    final result = await scan();
    expect([result.added, result.moved, result.missing], [0, 1, 0]);
    final saved = (await db.query('videos')).single;
    expect([saved['id'], saved['title'], saved['view_count'], saved['is_favorite']], ['original', 'Keep title', 9, 1]);
    expect([saved['video_path'], saved['root_path']], [destination.path, external.path]);
    expect(saved['created_at'], before['created_at']);
    expect((await db.query('watch_session')).single['video_id'], 'original');
    expect((await db.query('video_embeddings')).single['source_text'], 'Keep embedding');
    expect((await DBLibrary.getByRootFolder(internal.path)).single.videos, isEmpty);
    expect((await DBLibrary.getByRootFolder(external.path)).single.videos, [destination.path]);
    expect((await scan()).changed, isFalse);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('destination-first partial copy merges its usage after Finder removes the source', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final destination = video(external, 'a.mp4', size: 11 * 1024 * 1024);
    expect((await scan()).added, 1);
    final target = (await DBVideos.getByVideoPath(destination.path))!;
    await db.execute('UPDATE videos SET view_count=3 WHERE id=?', [target.id]);
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p2','New playlist')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1',?,'target'),('p2',?,'target')", [target.id, target.id]);
    await db.execute("INSERT INTO watch_session VALUES ('target-watch',?,'TEST-001',120,'2026-10-08')", [target.id]);
    await db.execute("UPDATE profile SET total_watch_duration=720 WHERE id='1'");
    source.copySync(destination.path);
    expect((await scan()).moved, 0);
    expect(await DBVideos.getAll(), hasLength(2));
    source.deleteSync();
    expect((await scan()).moved, 1);
    final saved = (await db.query('videos')).single;
    expect([saved['id'], saved['view_count'], saved['is_favorite'], saved['filesize']], ['original', 12, 1, 12 * 1024 * 1024]);
    expect(await db.query('playlist_item', orderBy: 'playlist_id'), [
      {'playlist_id': 'p1', 'video_id': 'original', 'created_at': 'created'},
      {'playlist_id': 'p2', 'video_id': 'original', 'created_at': 'target'},
    ]);
    expect((await db.query('watch_session')).map((row) => row['video_id']), ['original', 'original']);
    expect((await db.query('profile')).single['total_watch_duration'], 720);
    expect((await db.query('video_file_identity')).single['video_id'], 'original');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('duplicate content is ambiguous and same-name different content never inherits usage', () async {
    final first = video(internal, 'a.mp4');
    await seed(first);
    final second = video(internal, 'b.mp4');
    await seed(second, id: 'second');
    first.copySync('${external.path}/copy.mp4');
    first.deleteSync();
    second.deleteSync();
    expect((await scan()).moved, 0);
    expect(await db.query('videos'), hasLength(3));
    final fresh = video(external, 'a.mp4', marker: 2);
    expect((await scan()).moved, 0);
    final saved = (await DBVideos.getByVideoPath(fresh.path))!;
    expect([saved.viewCount, saved.isFavorite], [0, 0]);
  });

  test('offline source does not match until its root can be successfully scanned', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    source.copySync('${external.path}/a.mp4');
    internal.deleteSync(recursive: true);
    expect((await scan(roots: [external])).moved, 0);
    expect(await db.query('videos'), hasLength(2));
    internal.createSync();
    expect((await scan()).moved, 1);
    expect((await db.query('videos')).single['id'], 'original');
  });

  test('moving a soft-deleted video never restores it', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    await DBVideos.delete((await DBVideos.getAll()).single);
    source.renameSync('${external.path}/a.mp4');
    expect((await scan()).moved, 1);
    expect(await DBVideos.getAll(), isEmpty);
    expect((await db.query('videos')).single['is_deleted'], 1);
    expect(await db.query('playlist_item'), hasLength(1));
  });

  test('legacy missing records without a fingerprint are retained rather than guessed', () async {
    final source = video(internal, 'a.mp4');
    await seed(source, fingerprint: false);
    source.renameSync('${external.path}/a.mp4');
    expect((await scan()).moved, 0);
    expect(await db.query('videos'), hasLength(2));
    expect((await db.query('videos', where: 'id = ?', whereArgs: ['original'])).single['is_favorite'], 1);
  });

  test('a changed file during metadata preparation retries without committing a stale plan', () async {
    final file = video(internal, 'a.mp4');
    final result = await scan(prepareVideos: (library) async {
      file.setLastModifiedSync(DateTime(2030));
      return prepare(library);
    });
    expect(result.retry, isTrue);
    expect(await db.query('videos'), isEmpty);
    expect(await db.query('library'), isEmpty);
    expect((await scan()).added, 1);
  });

  test('failed additions roll back a destination merge including playlists and history', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    source.copySync('${external.path}/a.mp4');
    await scan();
    source.deleteSync();
    video(external, 'invalid.mp4', marker: 3);
    final before = await db.query('videos', orderBy: 'id');
    final playlists = await db.query('playlist_item');
    final history = await db.query('watch_session');
    final libraries = await db.query('library', orderBy: 'id');
    await expectLater(scan(prepareVideos: (library) async => [
      for (final path in library.videos!) Videos(rootPath: library.rootFolder, videoPath: path, duration: -1),
    ]), throwsA(isA<SqliteTestException>()));
    expect(await db.query('videos', orderBy: 'id'), before);
    expect(await db.query('playlist_item'), playlists);
    expect(await db.query('watch_session'), history);
    expect(await db.query('library', orderBy: 'id'), libraries);
    expect((await scan()).moved, 1);
  });

  test('cached fingerprints invalidate when a file changes and missing files return null', () async {
    final file = video(internal, 'a.mp4');
    final first = (await VideoFileIdentity.read(file.path))!;
    expect(await VideoFileIdentity.read(file.path, cached: first), first);
    video(internal, 'a.mp4', marker: 2).setLastModifiedSync(DateTime(2030));
    final changed = (await VideoFileIdentity.read(file.path, cached: first))!;
    expect(changed.fingerprint, isNot(first.fingerprint));
    file.deleteSync();
    expect(await VideoFileIdentity.read(file.path, cached: changed), isNull);
  });

  test('an unresolved drag keeps the original record until a later destination scan', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final original = (await DBVideos.getAll()).single;
    source.renameSync('${external.path}/a.mp4');
    final tab = PageSearchTab(1)..close();
    addTearDown(tab.dispose);
    await tab.applyFileMoves({source.path: original}, {}, [source.path]);
    expect((await db.query('videos')).single['id'], 'original');
    expect(await db.query('playlist_item'), hasLength(1));
    expect((await scan()).moved, 1);
    expect((await db.query('videos')).single['id'], 'original');
  });

  test('registered parent roots adopt already-tracked paths without recreating the video', () async {
    final nested = Directory('${internal.path}/nested')..createSync();
    final source = video(nested, 'a.mp4');
    await seed(source, fingerprint: false);
    expect((await scan()).added, 0);
    expect((await db.query('videos')).single['root_path'], internal.path);
    expect((await db.query('videos')).single['id'], 'original');
  });

  test('real filesystem watcher handles a Finder-style move without a manual rescan', () async {
    final source = video(internal, 'a.mp4');
    await seed(source);
    final home = Get.put<HomeController>(_Home()) as _Home;
    await HomePanelLibrary.startAutoRescanWatcher();
    final destination = source.renameSync('${external.path}/a.mp4');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    Videos? saved;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      saved = await DBVideos.getByVideoPath(destination.path);
      if (saved != null) break;
    }
    expect(saved?.id, 'original');
    expect(saved?.isFavorite, 1);
    expect(saved?.viewCount, 9);
    expect(home.refreshes, greaterThan(0));
    expect(HomePanelLibrary.canStartFileDrag, isTrue);
  });
}
