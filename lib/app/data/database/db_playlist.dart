import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../models/playlist_entity.dart';
import '../models/videos_entity.dart';
import '_init_db.dart';

mixin DBPlaylist {
  static final revision = 0.obs;
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<void> deleteAll() async {
    if (await _db.delete('playlist') > 0) revision.value++;
  }

  static Future<List<Playlist>> getAllPlaylist() async {
    final maps = await _db.rawQuery('''
      SELECT playlist.*, (
        SELECT count(*) FROM playlist_item item JOIN videos video ON video.id = item.video_id
        WHERE item.playlist_id = playlist.id AND video.is_deleted = 0
      ) AS total
      FROM playlist ORDER BY name ASC
    ''');
    return maps.map(Playlist.fromJson).toList();
  }

  static Future<List<Videos>> getPlaylist(String playlistId) async {
    final maps = await _db.rawQuery('''
      SELECT video.* FROM playlist_item AS item
      JOIN videos AS video ON video.id = item.video_id
      WHERE item.playlist_id = ? AND video.is_deleted = 0
      ORDER BY item.created_at ASC, item.video_id ASC
    ''', [playlistId]);
    return maps.map(Videos.fromJson).toList();
  }

  static Future<bool> addPlaylist(Playlist playlist) async {
    final name = (playlist.name ?? '').trim();
    if (name.isEmpty || name.toLowerCase() == 'favorite') return false;
    return _db.transaction((txn) async {
      final duplicate = await txn.query('playlist', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
      if (duplicate.isNotEmpty) return false;
      final now = DateTime.now().toStringEx();
      playlist
        ..id ??= UuidV4().generate()
        ..name = name
        ..createdAt ??= now
        ..updatedAt = now;
      await txn.insert('playlist', playlist.toJson());
      return true;
    });
  }

  static Future<bool> updatePlaylist(Playlist playlist) async {
    final name = (playlist.name ?? '').trim();
    if (playlist.id.isNullOrEmpty || name.isEmpty || name.toLowerCase() == 'favorite') return false;
    return _db.transaction((txn) async {
      final duplicate = await txn.query('playlist',
        where: 'name = ? COLLATE NOCASE AND id != ?', whereArgs: [name, playlist.id], limit: 1);
      if (duplicate.isNotEmpty) return false;
      final updated = await txn.update('playlist',
        {'name': name, 'cover': playlist.cover, 'updated_at': DateTime.now().toStringEx()},
        where: 'id = ?', whereArgs: [playlist.id]);
      return updated != 0;
    });
  }

  static Future<void> deletePlaylist(Playlist playlist) async {
    if (playlist.id.isNullOrEmpty) return;
    if (await _db.delete('playlist', where: 'id = ?', whereArgs: [playlist.id]) > 0) revision.value++;
  }

  static Future<void> addPlaylistItemBulk(String playlistId, List<Videos> videos) async {
    if (videos.isEmpty || playlistId.isEmpty) return;
    await _db.transaction((txn) async {
      final header = await txn.query('playlist', where: 'id = ?', whereArgs: [playlistId], limit: 1);
      if (header.isEmpty) throw StateError('Playlist no longer exists');
      final now = DateTime.now().toStringEx();
      for (final video in videos) {
        if (video.id.isNullOrEmpty) continue;
        await txn.rawInsert('''
          INSERT INTO playlist_item (playlist_id, video_id, created_at) VALUES (?, ?, ?)
          ON CONFLICT(playlist_id, video_id) DO NOTHING
        ''', [playlistId, video.id, now]);
      }
    });
    revision.value++;
  }

  static Future<void> deletePlaylistItems(String playlistId, String videoId) async {
    if (await _db.delete('playlist_item', where: 'playlist_id = ? AND video_id = ?', whereArgs: [playlistId, videoId]) > 0) revision.value++;
  }
}
