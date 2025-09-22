import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../models/collection_entity.dart';
import '_init_db.dart';

// -- Collection Type
const kCollectionTypePlaylist = 'playlist';
const kCollectionTypeActressFavorite = 'actress_favorite';
// ---

mixin DBCollection {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'collection';

  static Future<bool> _validation(Collection header) async {
    return true;
  }

  static Future<void> add(Collection header) async {
    header.id = UuidV4().generate();
    header.createdAt = DateTime.now().toStringEx();
    header.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validation(header);
    if (isOK) await _db.insert(_tableName, header.toJson());
  }

  static Future<void> update(Collection header) async {
    await _validation(header);
    header.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, header.toJson(), where: 'id = ?', whereArgs: [header.id]);
  }

  static Future<void> delete(Collection header) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [header.id]);
  }

  static Future<List<Collection>> getAll() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return List.generate(maps.length, (index) => Collection.fromJson(maps[index]));
  }

  static Future<List<Collection>> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => Collection.fromJson(maps[index]));
  }

  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return maps.length;
  }

  static Future<void> deleteAll() async => await _db.delete(_tableName);
}
