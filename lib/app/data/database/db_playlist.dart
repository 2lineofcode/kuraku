import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../models/playlist_entity.dart';
import 'db_init.dart';

mixin DBPlaylist {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableHeader = 'PlaylistHeader';
  // static final _tableItem = 'PlaylistItem';

  static Future<bool> _validationHeader(PlaylistHeader header) async {
    if (header.id == null) return false;
    return true;
  }

  static Future<void> addHeader(PlaylistHeader header) async {
    header.id = UuidV4().generate();
    header.createdAt = DateTime.now().toStringEx();
    header.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validationHeader(header);
    if (isOK) await _db.insert(_tableHeader, header.toJson());
  }

  static Future<void> updateHeader(PlaylistHeader header) async {
    await _validationHeader(header);
    header.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableHeader, header.toJson(), where: 'id = ?', whereArgs: [header.id]);
  }

  static Future<void> deleteHeader(PlaylistHeader header) async {
    await _db.delete(_tableHeader, where: 'id = ?', whereArgs: [header.id]);
  }

  static Future<List<PlaylistHeader>> getAllHeader() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableHeader);
    return List.generate(maps.length, (index) => PlaylistHeader.fromJson(maps[index]));
  }

  static Future<List<PlaylistHeader>> getByIDHeader(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableHeader, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => PlaylistHeader.fromJson(maps[index]));
  }

  static Future<int> getCountHeader() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableHeader);
    return maps.length;
  }

  static Future<void> deleteAllHeader() async => await _db.delete(_tableHeader);
}
