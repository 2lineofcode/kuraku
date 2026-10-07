import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/_update_db.dart';
import 'package:javit/app/data/database/db_achievement.dart';
import 'package:javit/app/data/database/db_activity.dart';
import 'package:javit/app/data/database/db_library.dart';
import 'package:javit/app/data/database/db_video_embedding.dart';
import 'package:javit/app/data/database/db_videos.dart';
import 'package:javit/app/data/models/activity_entity.dart';
import 'package:javit/app/data/models/library_entity.dart';
import 'package:javit/app/data/models/videos_entity.dart';

import 'sqlite_test_database.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

Future<SqliteTestDatabase> _database({int version = 15, String? sourcePath}) async {
  final db = await SqliteTestDatabase.open(sourcePath: sourcePath);
  addTearDown(db.close);
  if (sourcePath == null) {
    await db.transaction((_) async {
      await DBService.onCreate(db, version);
      await db.setVersion(version);
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

  test('scan commits roll back moves, deletes, additions and snapshots together, then retry succeeds', () async {
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
    await expectLater(DBLibrary.commitScan([snapshot, newLibrary], moves: moves, deletedPaths: ['/videos/deleted.mp4'], additions: [
      Videos(rootPath: '/videos', videoPath: '/videos/new.mp4'),
      Videos(rootPath: '/videos', videoPath: '/videos/invalid.mp4', duration: -1),
    ]), throwsA(isA<SqliteTestException>()));
    expect(await db.query('videos', orderBy: 'video_path'), beforeVideos);
    expect((await db.query('library')).single, beforeLibrary);
    expect(await db.query('playlist_item'), hasLength(1));
    expect(newLibrary.id, isNull);
    await DBLibrary.commitScan([snapshot], moves: moves, deletedPaths: ['/videos/deleted.mp4']);
    expect(await db.query('playlist_item'), isEmpty);
    expect((await DBVideos.getAll()).single.id, oldVideo.id);
    expect((await DBVideos.getAll()).single.videoPath, '/videos/b.mp4');
    expect((await DBLibrary.getAll()).single.videos, ['/videos/b.mp4']);
    await DBLibrary.commitScan([Library.fromJson(snapshot.toJson())..videos = []..totalVideo = 0], deletedPaths: ['/videos/b.mp4']);
    expect(await DBVideos.getAll(), isEmpty);
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
    final path = Platform.environment['JAVIT_ACTIVITY_DB'];
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
    print('Local backup v15 verified: $videoCount videos, ${(await db.query('video_embeddings')).length} embeddings retained');
  }, skip: Platform.environment['JAVIT_ACTIVITY_DB'] == null ? 'Set JAVIT_ACTIVITY_DB to verify a read-only local backup' : false);
}
