import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_achievement.dart';
import 'package:kuraku/app/data/database/db_activity.dart';
import 'package:kuraku/app/data/database/db_library.dart';
import 'package:kuraku/app/data/database/db_playlist.dart';
import 'package:kuraku/app/data/database/db_video_embedding.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/__kuraku_metadata_entity.dart';
import 'package:kuraku/app/data/models/activity_entity.dart';
import 'package:kuraku/app/data/models/library_entity.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';

import 'sqlite_test_database.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

Future<SqliteTestDatabase> _database({int? version, String? sourcePath}) async {
  final db = await SqliteTestDatabase.open(sourcePath: sourcePath);
  addTearDown(db.close);
  if (sourcePath == null) {
    await db.transaction((_) async {
      await DBService.onCreate(db, version ?? DBUpdate.version);
      await db.setVersion(version ?? DBUpdate.version);
    });
  }
  return db;
}

Future<void> _upgrade(SqliteTestDatabase db) => db.transaction((_) async {
  await DBUpdate.onUpgrade(db, await db.getVersion(), DBUpdate.version);
  await db.setVersion(DBUpdate.version);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('soft deletion survives scans and moves and excludes videos from lists and counts', () async {
    final db = await _database(version: 15);
    await db.execute("INSERT INTO videos(id,root_path,video_path,video_code,title,is_favorite,view_count,filesize,series,studio,label,director,release_date,actress,category) VALUES ('v1','/videos','/videos/a.mp4','TEST-001','Original',1,4,123,'Series','Studio','Label','Director','2026-01-01','[{\"id\":1,\"name_romaji\":\"Jane Doe\"}]','[{\"id\":1,\"category\":\"Drama\"}]')");
    await _upgrade(db);
    expect((await db.query('videos')).single['is_deleted'], 0);
    Get.put<DBService>(_Service()..dbMain = db);
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','created')");
    final video = (await DBVideos.getAll()).single;
    await DBVideos.delete(video);
    expect((await db.query('videos')).single['is_deleted'], 1);
    expect(await DBVideos.getAll(), isEmpty);
    expect(await DBVideos.getAll(where: 'is_favorite = 1 OR view_count > 0'), isEmpty);
    expect(await DBVideos.search('TEST'), isEmpty);
    expect(await DBVideos.getByVideoPath('/videos/a.mp4'), isNull);
    expect(await DBVideos.getBySeries('Series'), isEmpty);
    expect(await DBVideos.getByActress('Jane Doe'), isEmpty);
    expect(await DBVideos.getAllLike('actress', '1'), isEmpty);
    expect(await DBVideos.getAllLike('category', 'Drama'), isEmpty);
    expect(await DBVideos.getAllLike('title', 'Original'), isEmpty);
    expect(await DBVideos.getAllVideoPath('video_path', '/videos/'), isEmpty);
    expect(await DBVideos.getRecommendationSeeds(), isEmpty);
    expect(await DBVideos.getDuplicateVideoGroups(), isEmpty);
    expect(await DBVideos.getCount(), 0);
    expect(await DBVideos.getTotalFileSizeAllVideo(), isNull);
    expect(await DBVideos.getMissingQuality(), isEmpty);
    expect(await DBVideos.countMissingQuality(), 0);
    for (final load in [DBVideos.getAllActressWithCount, DBVideos.getAllCategoryWithCount,
      DBVideos.getAllPathWithCount, DBVideos.getAllStudioWithCount, DBVideos.getAllLabelWithCount,
      DBVideos.getAllSeriesWithCount, DBVideos.getAllDirectorWithCount, DBVideos.getAllReleaseYearWithCount]) {
      expect(await load(), isEmpty);
    }
    expect(await DBPlaylist.getPlaylist('p1'), isEmpty);
    expect((await DBPlaylist.getAllPlaylist()).single.total, 0);
    await DBLibrary.commitScan([], additions: [Videos(rootPath: '/videos', videoPath: '/videos/a.mp4')]);
    await DBLibrary.commitScan([]);
    expect(await DBVideos.getAll(includeDeleted: true), hasLength(1));
    await DBLibrary.commitScan([], moves: [{'oldPath': '/videos/a.mp4', 'newPath': '/videos/b.mp4', 'newRoot': '/videos'}]);
    await DBLibrary.commitScan([], additions: [Videos(rootPath: '/videos', videoPath: '/videos/b.mp4')]);
    expect(await DBVideos.getAll(), isEmpty);
    final saved = (await db.query('videos')).single;
    expect([saved['id'], saved['is_deleted'], saved['title'], saved['video_path']], ['v1', 1, 'Original', '/videos/b.mp4']);
    await expectLater(DBVideos.update(video), throwsStateError);
    await DBVideos.updateViewCount(video);
    expect((await db.query('videos')).single['view_count'], 4);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('restore preserves identity and related data without recreating missing files', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await db.execute("INSERT INTO videos(id,root_path,video_path,video_code,title,is_favorite,view_count,is_deleted) VALUES ('v1','/missing','/missing/a.mp4','TEST-001','Keep title',1,4,1),('v2','/missing','/missing/b.mp4','TEST-002','Active',0,0,0)");
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','created')");
    await db.execute("INSERT INTO watch_session VALUES ('w1','v1','TEST-001',42,'2020-01-01')");
    final deleted = (await DBVideos.getAll(includeDeleted: true, where: 'is_deleted = 1')).single;
    final watch = await db.query('watch_session');
    final revision = DBVideos.revision.value;
    expect(await DBVideos.restore(deleted), 1);
    expect(DBVideos.revision.value, revision + 1);
    final restored = await DBVideos.getByID('v1');
    expect([restored.id, restored.videoPath, restored.title, restored.isFavorite, restored.viewCount],
      ['v1', '/missing/a.mp4', 'Keep title', 1, 4]);
    expect(await DBVideos.getAll(includeDeleted: true, where: 'is_deleted = 1'), isEmpty);
    expect((await DBPlaylist.getPlaylist('p1')).single.id, 'v1');
    expect((await DBPlaylist.getAllPlaylist()).single.total, 1);
    expect(await db.query('watch_session'), watch);
    expect(await DBVideos.restore(deleted), 0);
    expect(await DBVideos.restore(Videos(id: 'gone')), 0);
    expect(DBVideos.revision.value, revision + 1);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('permanent delete removes only deleted records and cascades related data', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    final file = File('${Directory.systemTemp.path}/kuraku-permanent-delete-${DateTime.now().microsecondsSinceEpoch}.mp4');
    await file.writeAsString('keep');
    addTearDown(() => file.delete());
    await db.insert('videos', {'id': 'v1', 'root_path': file.parent.path, 'video_path': file.path, 'is_deleted': 1});
    await db.insert('videos', {'id': 'v2', 'root_path': '/', 'video_path': '/active.mp4', 'is_deleted': 0});
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','created')");
    await db.execute("INSERT INTO video_embeddings VALUES ('v1','source',?,'clip','created','updated')", [Float32List.fromList([1]).buffer.asUint8List()]);
    await db.execute("INSERT INTO watch_session VALUES ('w1','v1','TEST-001',42,'2020-01-01')");
    final revision = DBVideos.revision.value;
    await db.execute("CREATE TRIGGER fail_delete BEFORE DELETE ON videos BEGIN SELECT RAISE(ABORT,'Write failed'); END");
    await expectLater(DBVideos.deletePermanently(Videos(id: 'v1')), throwsA(isA<SqliteTestException>()));
    expect(await db.query('playlist_item'), hasLength(1));
    expect(await db.query('video_embeddings'), hasLength(1));
    expect(DBVideos.revision.value, revision);
    await db.execute('DROP TRIGGER fail_delete');
    expect(await DBVideos.deletePermanently(Videos(id: 'v2')), 0);
    expect(await DBVideos.deletePermanently(Videos(id: 'gone')), 0);
    expect(await DBVideos.deletePermanently(Videos(id: 'v1')), 1);
    expect(await DBVideos.deletePermanently(Videos(id: 'v1')), 0);
    expect(DBVideos.revision.value, revision + 1);
    expect((await db.query('videos')).single['id'], 'v2');
    expect(await db.query('playlist_item'), isEmpty);
    expect(await db.query('video_embeddings'), isEmpty);
    expect(await db.query('watch_session'), hasLength(1));
    expect(await file.readAsString(), 'keep');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('delete all deleted records is atomic, cascades related data and preserves active records and history', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await db.execute("INSERT INTO videos(id,root_path,video_path,is_deleted) VALUES ('v1','/','/deleted-a.mp4',1),('v2','/','/active.mp4',0),('v3','/','/deleted-b.mp4',1)");
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','created'),('p1','v2','created'),('p1','v3','created')");
    for (final id in ['v1', 'v2', 'v3']) {
      await db.execute("INSERT INTO video_embeddings VALUES (?,'source',?,'clip','created','updated')", [id, Float32List.fromList([1]).buffer.asUint8List()]);
    }
    await db.execute("INSERT INTO watch_session VALUES ('w1','v1','TEST-001',42,'2020-01-01')");
    final revision = DBVideos.revision.value;
    await db.execute("CREATE TRIGGER fail_delete BEFORE DELETE ON videos WHEN OLD.id = 'v3' BEGIN SELECT RAISE(ABORT,'Write failed'); END");
    await expectLater(DBVideos.deleteAllDeleted(), throwsA(isA<SqliteTestException>()));
    expect(await db.query('videos'), hasLength(3));
    expect(await db.query('playlist_item'), hasLength(3));
    expect(await db.query('video_embeddings'), hasLength(3));
    expect(DBVideos.revision.value, revision);
    await db.execute('DROP TRIGGER fail_delete');
    expect(await DBVideos.deleteAllDeleted(), 2);
    expect(DBVideos.revision.value, revision + 1);
    expect((await db.query('videos')).single['id'], 'v2');
    expect((await db.query('playlist_item')).single['video_id'], 'v2');
    expect((await db.query('video_embeddings')).single['video_id'], 'v2');
    expect(await db.query('watch_session'), hasLength(1));
    expect(await DBVideos.deleteAllDeleted(), 0);
    expect(DBVideos.revision.value, revision + 1);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('v15 preserves core data and relationships, cleans only rebuildable caches', () async {
    final db = await _database(version: 14);
    await db.execute("INSERT INTO library(id,root_folder,total_video,videos) VALUES ('l1','/videos',1,'[\"/videos/a.mp4\"]')");
    await db.execute("INSERT INTO videos(id,root_path,video_path,title) VALUES ('v1','/videos','/videos/a.mp4','Keep metadata')");
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep playlist')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','2020')");
    await db.execute("INSERT INTO watch_session VALUES ('w1','deleted','OLD-001',42,'2020-01-01')");
    await db.execute("UPDATE profile SET total_watch_duration=42 WHERE id='1'");
    await db.execute("INSERT INTO chat_conversation(id,title,created_at,updated_at,last_activity_at) VALUES ('c1','Keep chat','created','updated','latest')");
    await db.execute("INSERT INTO chat_message(id,conversation_id,position,role,status,content,activity,created_at,updated_at) VALUES ('m1','c1',1,'user','completed','Keep message','{}','created','updated')");
    await db.execute("INSERT INTO video_embeddings VALUES ('v1','source',?,'clip','created','updated')", [Float32List.fromList([0.5, 0.5]).buffer.asUint8List()]);
    await db.execute("INSERT INTO video_embeddings VALUES ('orphan','source',?,'clip','created','updated')", [Float32List.fromList([1]).buffer.asUint8List()]);
    await _upgrade(db);
    final video = (await db.query('videos')).single;
    expect(video['title'], 'Keep metadata');
    expect([video['view_count'], video['is_favorite'], video['duration'], video['filesize']], [0, 0, 0, 0]);
    expect((await db.query('playlist_item')).single, {'playlist_id': 'p1', 'video_id': 'v1', 'created_at': '2020'});
    expect((await db.query('chat_message')).single['content'], 'Keep message');
    expect((await db.query('watch_session')).single['video_id'], 'deleted');
    expect((await db.query('video_embeddings')).single['video_id'], 'v1');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.delete('videos', where: 'id = ?', whereArgs: ['v1']);
    expect(await db.query('playlist_item'), isEmpty);
    expect(await db.query('video_embeddings'), isEmpty);
    expect(await db.query('watch_session'), hasLength(1));
    await db.delete('chat_conversation');
    expect(await db.query('chat_message'), isEmpty);
  });

  test('invalid legacy rows roll back the whole migration, including dropped child tables', () async {
    final db = await _database(version: 14);
    await db.execute("INSERT INTO videos(id,root_path,video_path) VALUES ('v1','/videos','same'),('v2','/videos','same')");
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','created')");
    final schema = await db.rawQuery('SELECT * FROM sqlite_master ORDER BY name');
    await expectLater(_upgrade(db), throwsA(isA<SqliteTestException>()));
    expect(await db.getVersion(), 14);
    expect(await db.rawQuery('SELECT * FROM sqlite_master ORDER BY name'), schema);
    expect(await db.query('playlist_item'), hasLength(1));
    expect(await db.query('videos'), hasLength(2));
  });

  test('late migration failure restores rebuilt tables, relationships and version', () async {
    final db = await _database(version: 14);
    await db.execute("INSERT INTO videos(id,root_path,video_path) VALUES ('v1','/videos','/videos/a.mp4')");
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1','v1','created')");
    await db.execute("INSERT INTO download_log(id,payload) VALUES ('d1','{\"filename\":123}')");
    final schema = await db.rawQuery('SELECT * FROM sqlite_master ORDER BY name');
    final videos = await db.query('videos');
    final downloads = await db.query('download_log');
    await expectLater(_upgrade(db), throwsA(isA<SqliteTestException>()));
    expect(await db.getVersion(), 14);
    expect(await db.rawQuery('SELECT * FROM sqlite_master ORDER BY name'), schema);
    expect(await db.query('videos'), videos);
    expect(await db.query('download_log'), downloads);
    expect(await db.query('playlist_item'), hasLength(1));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('schema rejects malformed values at every hardened boundary', () async {
    final db = await _database();
    await db.execute("INSERT INTO videos(id,root_path,video_path) VALUES ('v1','/videos','/videos/a.mp4')");
    await db.execute("INSERT INTO library(id,root_folder) VALUES ('l1','/videos')");
    await db.execute("INSERT INTO chat_conversation(id,title,created_at,updated_at,last_activity_at) VALUES ('c1','Chat','now','now','now')");
    for (final sql in [
      "INSERT INTO videos(id,root_path,video_path) VALUES ('v2','/videos','/videos/a.mp4')",
      "INSERT INTO videos(id,root_path,video_path) VALUES ('v2','','/videos/b.mp4')",
      'UPDATE videos SET view_count=-1',
      'UPDATE videos SET is_favorite=99',
      'UPDATE videos SET duration=1.5',
      "UPDATE videos SET actress='{}'",
      "INSERT INTO library(id,root_folder) VALUES ('l2','/videos')",
      "INSERT INTO library(id,root_folder) VALUES ('l2','')",
      "UPDATE library SET videos='invalid'",
      "UPDATE profile SET name=''",
      "INSERT INTO profile(id,name) VALUES ('2','Other')",
      'UPDATE profile SET total_watch_duration=-1',
      "INSERT INTO historical(type,query,updated_at) VALUES ('search','  ',1)",
      "INSERT INTO achievement_unlock(id,achievement_key,title,unlocked_at) VALUES ('a','','Title','now')",
      "INSERT INTO chat_conversation(id,title,created_at,updated_at,last_activity_at) VALUES ('','Chat','now','now','now')",
      "INSERT INTO chat_message(id,conversation_id,position,role,status,created_at,updated_at,activity) VALUES ('m','c1',1,'user','completed','now','now','invalid')",
      "INSERT INTO download_log(id,payload) VALUES ('d','{\"filename\":123}')",
      "INSERT INTO download_log(id,payload) VALUES ('d','{\"headless\":1}')",
      "INSERT INTO download_log(id,payload) VALUES ('d','{\"concurrency\":\"8\"}')",
      "INSERT INTO video_embeddings(video_id,source_text,embedding,model) VALUES ('missing','source',X'00000000','clip')",
      "INSERT INTO video_embeddings(video_id,source_text,embedding,model) VALUES ('v1','source','[1]','clip')",
    ]) {
      await expectLater(db.execute(sql), throwsA(isA<SqliteTestException>()), reason: sql);
    }
  });

  test('bulk import, concurrent counters, favorites and JSON filters preserve identity and metadata', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mp4', title: 'Original')]);
    final original = (await DBVideos.getAll()).single;
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep')");
    await db.execute("INSERT INTO playlist_item VALUES ('p1',?,'created')", [original.id]);
    await Future.wait(List.generate(3, (_) => DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: original.videoPath, title: 'Replacement')])));
    expect((await DBVideos.getAll()).single.id, original.id);
    expect((await DBVideos.getAll()).single.title, 'Original');
    expect(await db.query('playlist_item'), hasLength(1));
    await db.update('videos', {'title': 'Fresh metadata', 'actress': jsonEncode([
      {'id': 12, 'name_romaji': 'First'}, {'id': 312, 'name_romaji': 'Second'},
    ]), 'category': '[{"category":"Drama"}]'}, where: 'id = ?', whereArgs: [original.id]);
    await Future.wait(List.generate(4, (_) => DBVideos.updateViewCount(original)));
    await DBVideos.addToFavorite(original);
    final saved = (await DBVideos.getAll()).single;
    expect(saved.viewCount, 4);
    expect(saved.title, 'Fresh metadata');
    expect(saved.isFavorite, 1);
    expect(await DBVideos.getByActress('second'), hasLength(1));
    expect(await DBVideos.getAllLike('actress', '2'), isEmpty);
    expect(await DBVideos.getAllLike('actress', '312'), hasLength(1));
    expect(await DBVideos.getAllLike('category', 'Drama'), hasLength(1));
    expect(await DBVideos.getAllLike('category', 'Dram'), isEmpty);
  });

  test('metadata updates preserve required numeric values when upstream values are missing', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mp4', duration: 90, viewCount: 4, isFavorite: 1, filesize: 123)]);
    final video = (await DBVideos.getAll()).single;
    video.title = 'Updated metadata';
    video.duration = video.viewCount = video.isFavorite = video.filesize = null;
    await DBVideos.update(video);
    final saved = (await DBVideos.getAll()).single;
    expect(saved.title, 'Updated metadata');
    expect([saved.duration, saved.viewCount, saved.isFavorite, saved.filesize], [90, 4, 1, 123]);
    video.duration = -1;
    await expectLater(DBVideos.update(video), throwsA(isA<SqliteTestException>()));
    expect((await DBVideos.getAll()).single.duration, 90);
  });

  test('API refresh preserves local records and relationships using the real SQLite schema', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mkv',
      videoCode: 'ABP-001', title: 'Original', duration: 90, durationFormated: '1 hour, 30 minutes',
      releaseDate: '2026-01-01', releaseDateFormated: 'Jan 01, 2026', viewCount: 4,
      isFavorite: 1, filesize: 123, quality: '1920x1080',
      category: [VideoCategory(id: 1, category: 'Drama')], screenshot: ['existing-shot'])]);
    final video = (await DBVideos.getAll()).single;
    await db.insert('playlist', {'id': 'playlist', 'name': 'Keep'});
    await db.insert('playlist_item', {'playlist_id': 'playlist', 'video_id': video.id, 'created_at': '2026-01-01'});
    await db.insert('watch_session', {'id': 'watch', 'video_id': video.id, 'watched_seconds': 60, 'created_at': '2026-01-01'});
    final before = (await db.query('videos')).single;
    final membership = await db.query('playlist_item');
    final history = await db.query('watch_session');
    expect(await DBVideos.updateMetadata(video, Videos.fromMetadata(KurakuMetadata(
      title: 'New title', duration: 0, releaseDate: '', genre: [], screenshot: [],
    ))), 1);
    final saved = (await db.query('videos')).single;
    expect(saved['title'], 'New title');
    expect(video.title, 'Original');
    for (final key in ['id', 'root_path', 'video_path', 'view_count', 'is_favorite', 'filesize', 'quality',
      'created_at', 'duration', 'duration_formated', 'release_date', 'release_date_formated', 'category', 'screenshot']) {
      expect(saved[key], before[key], reason: key);
    }
    expect(await db.query('playlist_item'), membership);
    expect(await db.query('watch_session'), history);
    await expectLater(DBVideos.updateMetadata((await DBVideos.getAll()).single, Videos(title: 'Invalid', duration: 1.5)),
      throwsA(isA<SqliteTestException>()));
    expect((await db.query('videos')).single, saved);
    await DBVideos.delete(video);
    expect(await DBVideos.updateMetadata(video, Videos(title: 'Deleted update')), 0);
    expect((await db.query('videos')).single['title'], 'New title');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('video path lookup follows platform case sensitivity and excludes deleted rows', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/A.mkv', title: 'Tracked')]);
    final video = (await DBVideos.getAll()).single;
    final differentCase = await DBVideos.getByVideoPath('/VIDEOS/a.MKV');
    expect(differentCase?.id, Platform.isWindows ? video.id : isNull);
    expect((await DBVideos.getByVideoPath('/videos/A.mkv'))?.id, video.id);
    await DBVideos.delete(video);
    expect(await DBVideos.getByVideoPath('/videos/A.mkv'), isNull);
    expect(await DBVideos.getByVideoPath('/VIDEOS/a.MKV'), isNull);
  });

  test('late metadata refresh cannot overwrite a newer manual edit even with the same timestamp', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mkv', title: 'Original')]);
    final stale = (await DBVideos.getAll()).single;
    await db.update('videos', {'title': 'Manual title', 'actress': '[{"id":7,"name_romaji":"Manual Cast"}]'},
      where: 'id = ?', whereArgs: [stale.id]);
    final saved = (await db.query('videos')).single;
    expect(saved['updated_at'], stale.updatedAt);
    final revision = DBVideos.revision.value;
    expect(await DBVideos.updateMetadata(stale, Videos(title: 'Late API title',
      actress: [VideoActress(id: 8, nameRomaji: 'API Cast')])), 0);
    expect((await db.query('videos')).single, saved);
    expect(DBVideos.revision.value, revision);

    final fresh = (await DBVideos.getAll()).single;
    await DBVideos.addToFavorite(fresh);
    expect(await DBVideos.updateMetadata(fresh, Videos(title: 'Fresh metadata')), 1);
    expect((await DBVideos.getAll()).single.isFavorite, 1);
  });

  test('stale metadata saves preserve moves, counters, favorites and file properties', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mp4', viewCount: 1, filesize: 123, quality: 'old')]);
    final stale = (await DBVideos.getAll()).single;
    await DBVideos.moveVideoPaths([{'id': stale.id!, 'oldPath': stale.videoPath!, 'newPath': '/new/a.mp4', 'newRoot': '/new'}]);
    final current = (await DBVideos.getAll()).single;
    await DBVideos.updateViewCount(current);
    await DBVideos.addToFavorite(current);
    await db.update('videos', {'filesize': 456, 'quality': 'new'}, where: 'id = ?', whereArgs: [current.id]);
    stale.title = 'Edited title';
    await DBVideos.update(stale);
    final saved = (await DBVideos.getAll()).single;
    expect(saved.title, 'Edited title');
    expect([saved.rootPath, saved.videoPath, saved.viewCount, saved.isFavorite, saved.filesize, saved.quality],
      ['/new', '/new/a.mp4', 2, 1, 456, 'new']);
  });

  test('manual editor baseline rejects refreshed metadata but permits local counter changes', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mkv', title: 'Original', duration: 120)]);
    final original = (await DBVideos.getAll()).single;
    final edited = Videos.fromJson(original.toJson())..title = 'Draft title';
    expect(await DBVideos.updateMetadata(original, Videos(poster: 'New poster', duration: 125)), 1);
    final saved = (await db.query('videos')).single;
    final revision = DBVideos.revision.value;
    await expectLater(DBVideos.update(edited, original: original), throwsStateError);
    expect((await db.query('videos')).single, saved);
    expect(DBVideos.revision.value, revision);

    final fresh = (await DBVideos.getAll()).single;
    await DBVideos.addToFavorite(fresh);
    await DBVideos.updateViewCount(fresh);
    await DBVideos.update(Videos.fromJson(fresh.toJson())..title = 'New title', original: fresh);
    final current = (await DBVideos.getAll()).single;
    expect([current.title, current.poster, current.duration, current.isFavorite, current.viewCount],
      ['New title', 'New poster', 125, 1, 1]);
    await DBVideos.delete(current);
    await expectLater(DBVideos.update(edited, original: current), throwsStateError);
  });

  test('directory queries match direct children only and treat wildcards literally', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    for (final path in ['/videos/A/one.mp4', '/videos/AB/two.mp4', '/videos/A/sub/three.mp4',
        '/videos/A_%/four.mp4', '/videos/A_X/five.mp4']) {
      await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: path)]);
    }
    for (final root in ['/videos/A', '/videos/A/']) {
      expect((await DBVideos.getAllVideoPath('video_path', root)).map((video) => video.videoPath), ['/videos/A/one.mp4']);
    }
    expect((await DBVideos.getAllVideoPath('video_path', '/videos/A_%')).single.videoPath, '/videos/A_%/four.mp4');
  });

  test('library deletion rolls back registration and related records together', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    final library = Library(rootFolder: '/videos');
    await DBLibrary.add(library);
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mp4')]);
    final video = (await DBVideos.getAll()).single;
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p','Keep')");
    await db.insert('playlist_item', {'playlist_id': 'p', 'video_id': video.id});
    await db.execute("CREATE TRIGGER fail_library_delete BEFORE DELETE ON library BEGIN SELECT RAISE(ABORT,'Simulated write failure'); END");
    await expectLater(DBLibrary.deleteWithVideos(library), throwsA(isA<SqliteTestException>()));
    expect(await DBLibrary.getAll(), hasLength(1));
    expect(await DBVideos.getAll(), hasLength(1));
    expect(await db.query('playlist_item'), hasLength(1));
    await db.execute('DROP TRIGGER fail_library_delete');
    await db.update('library', {'root_folder': '/relocated'}, where: 'id = ?', whereArgs: [library.id]);
    await db.update('videos', {'root_path': '/relocated'});
    await DBLibrary.deleteWithVideos(library);
    expect(await DBLibrary.getAll(), isEmpty);
    expect(await DBVideos.getAll(), isEmpty);
    expect(await db.query('playlist_item'), isEmpty);
  });

  test('scan commits roll back moves, additions and snapshots together and retain missing records', () async {
    final db = await _database();
    Get.put<DBService>(_Service()..dbMain = db);
    final library = Library(rootFolder: '/videos', totalVideo: 2, videos: ['/videos/a.mp4', '/videos/deleted.mp4']);
    await DBLibrary.commitScan([library], additions: [
      Videos(rootPath: '/videos', videoPath: '/videos/a.mp4'),
      Videos(rootPath: '/videos', videoPath: '/videos/deleted.mp4'),
    ]);
    final beforeVideos = await db.query('videos', orderBy: 'video_path');
    final beforeLibrary = (await db.query('library')).single;
    final oldVideo = (await DBVideos.getByVideoPath('/videos/a.mp4'))!;
    await db.execute("INSERT INTO playlist(id,name) VALUES ('p1','Keep membership')");
    await db.execute("INSERT INTO playlist_item SELECT 'p1',id,'created' FROM videos WHERE video_path='/videos/deleted.mp4'");
    final snapshot = Library.fromJson(library.toJson())..videos = ['/videos/b.mp4']..totalVideo = 1;
    final moves = [{'oldPath': '/videos/a.mp4', 'newPath': '/videos/b.mp4', 'newRoot': '/videos'}];
    final newLibrary = Library(rootFolder: '/new');
    await expectLater(DBLibrary.commitScan([snapshot, newLibrary], moves: moves, additions: [
      Videos(rootPath: '/videos', videoPath: '/videos/new.mp4'),
      Videos(rootPath: '/videos', videoPath: '/videos/invalid.mp4', duration: -1),
    ]), throwsA(isA<SqliteTestException>()));
    expect(await db.query('videos', orderBy: 'video_path'), beforeVideos);
    expect((await db.query('library')).single, beforeLibrary);
    expect(await db.query('playlist_item'), hasLength(1));
    expect(newLibrary.id, isNull);
    await DBLibrary.commitScan([snapshot], moves: moves);
    expect(await db.query('playlist_item'), hasLength(1));
    expect((await DBVideos.getByVideoPath('/videos/b.mp4'))!.id, oldVideo.id);
    expect(await DBVideos.getAll(), hasLength(2));
    expect((await DBLibrary.getAll()).single.videos, ['/videos/b.mp4']);
    await DBLibrary.commitScan([Library.fromJson(snapshot.toJson())..videos = []..totalVideo = 0]);
    expect(await DBVideos.getAll(), hasLength(2));
    expect((await DBLibrary.getAll()).single.totalVideo, 0);
  });

  test('concurrent uniqueness, typed downloads, binary embeddings and reset use the new schema', () async {
    final db = await _database();
    final service = _Service()..dbMain = db;
    Get.put<DBService>(service);
    final libraries = await Future.wait(List.generate(3, (_) => DBLibrary.add(Library(rootFolder: '/videos'))));
    expect(libraries.where((added) => added), hasLength(1));
    final todos = await Future.wait(['Watch later', 'watch LATER', ' Watch later '].map(DBActivity.addTodo));
    expect(todos.where((todo) => todo != null), hasLength(1));
    final achievements = await Future.wait(List.generate(3, (_) => DBAchievement.unlock(key: 'first', title: 'First', description: 'Keep')));
    expect(achievements.where((added) => added), hasLength(1));
    expect(await DBActivity.addDownloadLog(Activity(content: '{"filename":123}')), isNull);
    await DBActivity.addDownloadLog(Activity(content: '{"filename":"a.mp4","headless":true,"concurrency":8}'));
    await DBVideos.addBulk([Videos(rootPath: '/videos', videoPath: '/videos/a.mp4')]);
    final video = (await DBVideos.getAll()).single;
    await DBVideoEmbeddings.upsert(videoId: video.id!, sourceText: 'source', embedding: [0.5, -0.5], model: 'clip');
    final created = (await db.query('video_embeddings')).single['created_at'];
    await DBVideoEmbeddings.upsert(videoId: video.id!, sourceText: 'new', embedding: [1, 0], model: 'clip');
    expect((await db.query('video_embeddings')).single['created_at'], created);
    expect((await db.query('video_embeddings')).single['embedding'], isA<Uint8List>());
    expect((await DBVideoEmbeddings.getByVideoId(video.id!))!.embedding, [1, 0]);
    await db.execute("INSERT INTO chat_translation VALUES ('source','id','target','now')");
    await db.execute("UPDATE profile SET badge_for_collection='stale' WHERE id='1'");
    await service.deleteAllData();
    for (final table in ['videos', 'library', 'video_embeddings', 'download_log', 'achievement_unlock', 'chat_translation']) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    expect((await db.query('profile')).single['badge_for_collection'], 'Noobless');
  });

  test('local database backup migrates without changing original core records', () async {
    final path = Platform.environment['KURAKU_ACTIVITY_DB'];
    final db = await _database(sourcePath: path);
    final before = <String, List<Map<String, Object?>>>{};
    for (final table in ['library', 'playlist', 'playlist_item', 'watch_session', 'profile', 'achievement_unlock', 'historical', 'chat_conversation', 'chat_message', 'chat_translation', 'activity']) {
      before[table] = await db.query(table, orderBy: '1');
    }
    final videosBefore = (await db.query('videos', orderBy: 'id')).map((row) => Map<String, Object?>.from(row)).toList();
    for (final row in videosBefore) {
      for (final field in ['duration', 'view_count', 'is_favorite', 'filesize']) row[field] ??= 0;
    }
    final videoCount = videosBefore.length;
    await _upgrade(db);
    for (final entry in before.entries) {
      expect(await db.query(entry.key, orderBy: '1'), entry.value, reason: entry.key);
    }
    expect(await db.query('videos', orderBy: 'id'), videosBefore);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await db.rawQuery('PRAGMA quick_check')).single.values.single, 'ok');
    expect((await db.rawQuery('SELECT COUNT(*) AS count FROM video_embeddings e WHERE NOT EXISTS (SELECT 1 FROM videos v WHERE v.id=e.video_id)')).single['count'], 0);
    print('Local backup v${DBUpdate.version} verified: $videoCount videos, ${(await db.query('video_embeddings')).length} embeddings retained');
  }, skip: Platform.environment['KURAKU_ACTIVITY_DB'] == null ? 'Set KURAKU_ACTIVITY_DB to verify a read-only local backup' : false);
}
