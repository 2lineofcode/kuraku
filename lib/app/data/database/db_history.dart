import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';

import '../models/history_entity.dart';
import 'db_init.dart';

mixin DBHistory {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'History';

  static Future<bool> _validation(History history) async {
    if (history.id.isNullOrEmpty) return false;
    if (history.message.isNullOrEmpty) return false;
    return true;
  }

  static Future<void> add(History history) async {
    history.createdAt = DateTime.now().toStringEx();
    history.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validation(history);
    if (isOK) await _db.insert(_tableName, history.toJson());
  }

  static Future<void> update(History history) async {
    await _validation(history);
    final current = await getByID(history.id ?? '');
    current.message = history.message;
    current.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, current.toJson(), where: 'id = ?', whereArgs: [history.id]);
  }

  static Future<void> delete(History history) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [history.id]);
  }

  static Future<List<History>> getAll({String? where, List<Object?>? whereArgs, String? orderBy, int? limit}) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit);
    return List.generate(maps.length, (index) => History.fromJson(maps[index]));
  }

  static Future<History> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => History.fromJson(maps[index]))[0];
  }

  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return maps.length;
  }

  static Future<void> deleteAll({String? where, List<Object?>? whereArgs}) async => await _db.delete(_tableName, where: where, whereArgs: whereArgs);
}
