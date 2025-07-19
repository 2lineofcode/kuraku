import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../models/history_entity.dart';
import 'db_init.dart';

mixin DBHistory {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'History';

  static Future<bool> _validation(History history) async {
    if (history.id == null) return false;
    return true;
  }

  static Future<void> add(History history) async {
    history.id = UuidV4().generate();
    history.createdAt = DateTime.now().toStringEx();
    history.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validation(history);
    if (isOK) await _db.insert(_tableName, history.toJson());
  }

  static Future<void> update(History history) async {
    await _validation(history);
    history.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, history.toJson(), where: 'id = ?', whereArgs: [history.id]);
  }

  static Future<void> delete(History history) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [history.id]);
  }

  static Future<List<History>> getAll() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return List.generate(maps.length, (index) => History.fromJson(maps[index]));
  }

  static Future<List<History>> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => History.fromJson(maps[index]));
  }

  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return maps.length;
  }

  static Future<void> deleteAll() async => await _db.delete(_tableName);
}
