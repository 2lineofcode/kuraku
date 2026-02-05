import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../models/collection_entity.dart';
import '../models/videos_entity.dart';
import '_init_db.dart';

// -- Collection Type
const kCollectionTypePlaylist = 'playlist';
const kCollectionTypeActressFavorite = 'actress_favorite';
// ---

mixin DBCollection {
  static Database get _db => Get.find<DBService>().dbMain;
  static final _tableName = 'collection';

  // ────────────────────────────────────────────────────────────────
  // ⵌ COMMON UTILITIES
  // ────────────────────────────────────────────────────────────────
  static Collection _stamp(Collection collection) {
    final now = DateTime.now().toStringEx();
    collection.id = UuidV4().generate();
    collection.createdAt ??= now;
    collection.updatedAt = now;
    return collection;
  }

  static Future<bool> _validation(Collection collection) async {
    final isHeader = collection.videoId == null;
    final whereBuffer = StringBuffer('type = ? AND name = ? AND ');
    final whereArgs = <Object?>[
      collection.type ?? kCollectionTypePlaylist,
      collection.name,
    ];

    if (isHeader) {
      whereBuffer.write('video_id IS NULL');
    } else {
      whereBuffer.write('video_id = ?');
      whereArgs.add(collection.videoId);
    }

    if (collection.id != null) {
      // Exclude current record when validating updates.
      whereBuffer.write(' AND id != ?');
      whereArgs.add(collection.id);
    }

    final dup = await _db.query(
      _tableName,
      where: whereBuffer.toString(),
      whereArgs: whereArgs,
      limit: 1,
    );
    return dup.isEmpty;
  }


  static Future<bool> _insert(Collection collection) async {
    if (!await _validation(collection)) return false;
    await _db.insert(_tableName, _stamp(collection).toJson());
    return true;
  }

  static Future<void> _update(Collection collection) async {
    if (!await _validation(collection)) return;
    collection.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, collection.toJson(), where: 'id = ?', whereArgs: [collection.id]);
  }

  static Future<void> _delete({required String where, List<Object?>? whereArgs}) async {
    await _db.delete(_tableName, where: where, whereArgs: whereArgs);
  }

  static Future<void> deleteAll({String? where, List<Object?>? whereArgs}) async {
    await _delete(where: where ?? '1 = 1', whereArgs: whereArgs);
  }

  static Future<List<Collection>> _query({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    String? groupBy,
  }) async {
    final maps = await _db.query(
      _tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      groupBy: groupBy,
    );
    return List.generate(maps.length, (index) => Collection.fromJson(maps[index]));
  }


  // ────────────────────────────────────────────────────────────────
  // ⵌ PART: Playlist
  // ────────────────────────────────────────────────────────────────
  static Future<List<Collection>> getAllPlaylist() async {
    final maps = await _db.rawQuery('''
      SELECT count(*) as total, * 
      FROM $_tableName
      WHERE type = ?
      GROUP BY name
      ORDER BY name ASC
    ''', [kCollectionTypePlaylist]);
    return List.generate(maps.length, (index) => Collection.fromJson(maps[index]));
  }

  static Future<List<Collection>> getPlaylist(String playlistName) async {
    final maps = await _query(
      where: 'type = ? AND name = ? AND video_id IS NOT NULL',
      whereArgs: [kCollectionTypePlaylist, playlistName],
      orderBy: 'name ASC',
    );
    return maps;
  }

  static Future<void> addPlaylist(Collection playlist) async {
    // mark as header row for playlist (no specific video attached)
    playlist.type = kCollectionTypePlaylist;
    playlist.videoId = null;
    logD('playlist -> $playlist');
    await _insert(playlist);
  }

  static Future<void> updatePlaylist(Collection playlist) async {
    // ensure header row keeps correct type
    playlist.type = kCollectionTypePlaylist;
    playlist.videoId = null;
    await _update(playlist);
  }

  static Future<void> deletePlaylist(Collection playlist) async {
    await _delete(where: 'name = ?', whereArgs: [playlist.name]);
  }

  // -- req : name, video_id
  static Future<void> addPlaylistItems(String playlistName, String videoId) async {
    final playlist = Collection(type: kCollectionTypePlaylist, name: playlistName, videoId: videoId);
    await _insert(playlist);
  }

  static Future<void> addPlaylistItemBulk(String playlistName, List<Videos> videos) async {
    for (final video in videos) {
      await addPlaylistItems(playlistName, video.id ?? '');
    }
  }

  // -- req : name, video_id
  static Future<void> deletePlaylistItems(String playlistName, String videoId) async {
    await _delete(where: 'type = ? AND name = ? AND video_id = ?', whereArgs: [kCollectionTypePlaylist, playlistName, videoId]);
  }

}
