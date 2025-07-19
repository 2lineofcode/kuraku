import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../models/history_entity.dart';
import '../models/playlist_entity.dart';
import 'db_init.dart';

mixin DBPlaylist {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableHeader = 'PlaylistHeader';
  // static final _tableItem = 'PlaylistItem';

  static Future<bool> _validation(PlaylistHeader header) async {
    if (header.id == null) return false;
    return true;
  }

  static Future<void> add(PlaylistHeader header) async {
    header.id = UuidV4().generate();
    header.createdAt = DateTime.now().toStringEx();
    header.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validation(header);
    if (isOK) await _db.insert(_tableHeader, header.toJson());
  }

  static Future<void> update(PlaylistHeader header) async {
    await _validation(header);
    header.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableHeader, header.toJson(), where: 'id = ?', whereArgs: [header.id]);
  }

  static Future<void> delete(PlaylistHeader header) async {
    await _db.delete(_tableHeader, where: 'id = ?', whereArgs: [header.id]);
  }

  static Future<List<History>> getAll() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableHeader);
    return List.generate(maps.length, (index) => History.fromJson(maps[index]));
  }

  static Future<List<History>> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableHeader, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => History.fromJson(maps[index]));
  }

  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableHeader);
    return maps.length;
  }

  static Future<void> deleteAll() async => await _db.delete(_tableHeader);
}
