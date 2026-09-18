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
  static const _tableName = 'collection';

  // ────────────────────────────────────────────────────────────────
  // ⵌ COMMON UTILITIES
  // ────────────────────────────────────────────────────────────────
  static Collection _stamp(Collection collection) {
    final now = DateTime.now().toStringEx();
    collection.id ??= UuidV4().generate();
    collection.createdAt ??= now;
    collection.updatedAt = now;
    return collection;
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
      SELECT header.*, 1 + (
        SELECT count(*) FROM $_tableName AS item
        WHERE item.type = header.type AND item.playlist_id = header.id AND item.video_id IS NOT NULL
      ) AS total
      FROM $_tableName AS header
      WHERE header.type = ? AND header.video_id IS NULL
      ORDER BY header.name ASC
    ''', [kCollectionTypePlaylist]);
    return List.generate(maps.length, (index) => Collection.fromJson(maps[index]));
  }

  static Future<List<Collection>> getPlaylist(String playlistId) async {
    final maps = await _query(
      where: 'type = ? AND playlist_id = ? AND video_id IS NOT NULL',
      whereArgs: [kCollectionTypePlaylist, playlistId],
      orderBy: 'name ASC',
    );
    return maps;
  }

  static Future<bool> addPlaylist(Collection playlist) async {
    final name = (playlist.name ?? '').trim();
    if (name.isEmpty || name.toLowerCase() == 'favorite') return false;
    return _db.transaction((txn) async {
      final duplicate = await txn.query(_tableName,
        where: 'type = ? AND video_id IS NULL AND name = ? COLLATE NOCASE',
        whereArgs: [kCollectionTypePlaylist, name], limit: 1);
      if (duplicate.isNotEmpty) return false;
      playlist
        ..name = name
        ..type = kCollectionTypePlaylist
        ..videoId = null
        ..playlistId = null;
      await txn.insert(_tableName, _stamp(playlist).toJson());
      return true;
    });
  }

  static Future<bool> updatePlaylist(Collection playlist) async {
    final name = (playlist.name ?? '').trim();
    if (playlist.id.isNullOrEmpty || name.isEmpty || name.toLowerCase() == 'favorite') return false;
    return _db.transaction((txn) async {
      final duplicate = await txn.query(_tableName,
        where: 'type = ? AND video_id IS NULL AND name = ? COLLATE NOCASE AND id != ?',
        whereArgs: [kCollectionTypePlaylist, name, playlist.id], limit: 1);
      if (duplicate.isNotEmpty) return false;
      final updated = await txn.update(_tableName,
        {'name': name, 'cover': playlist.cover, 'updated_at': DateTime.now().toStringEx()},
        where: 'type = ? AND id = ? AND video_id IS NULL',
        whereArgs: [kCollectionTypePlaylist, playlist.id]);
      return updated != 0;
    });
  }

  static Future<void> deletePlaylist(Collection playlist) async {
    if (playlist.id.isNullOrEmpty) return;
    await _delete(where: 'type = ? AND id = ? AND video_id IS NULL', whereArgs: [kCollectionTypePlaylist, playlist.id]);
  }

  static Future<void> addPlaylistItems(String playlistId, String videoId) => addPlaylistItemBulk(playlistId, [Videos(id: videoId)]);

  static Future<void> addPlaylistItemBulk(String playlistId, List<Videos> videos) async {
    if (videos.isEmpty || playlistId.isEmpty) return;

    await _db.transaction((txn) async {
      final header = await txn.query(_tableName,
        where: 'type = ? AND id = ? AND video_id IS NULL',
        whereArgs: [kCollectionTypePlaylist, playlistId], limit: 1);
      if (header.isEmpty) throw StateError('Playlist no longer exists');
      for (final video in videos) {
        final videoId = video.id ?? '';
        if (videoId.isEmpty) continue;

        final playlist = Collection(
          type: kCollectionTypePlaylist,
          playlistId: playlistId,
          videoId: videoId,
          createdAt: DateTime.now().toStringEx(),
          updatedAt: DateTime.now().toStringEx(),
        );

        final where = 'type = ? AND playlist_id = ? AND video_id = ?';
        final whereArgs = [kCollectionTypePlaylist, playlistId, videoId];
        final dup = await txn.query(
          _tableName,
          where: where,
          whereArgs: whereArgs,
          limit: 1,
        );
        if (dup.isNotEmpty) continue;

        if (playlist.id.isNullOrEmpty) {
          playlist.id = UuidV4().generate();
        }

        await txn.insert(_tableName, playlist.toJson());
      }
    });
  }

  static Future<void> deletePlaylistItems(String playlistId, String videoId) async {
    await _delete(where: 'type = ? AND playlist_id = ? AND video_id = ?', whereArgs: [kCollectionTypePlaylist, playlistId, videoId]);
  }
}
