import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../models/relapse_entity.dart';
import '_init_db.dart';

mixin DBRelapse {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'Relapse';

  static Future<void> add(Relapse relapse) async {
    relapse.id = UuidV4().generate();
    relapse.createdAt = DateTime.now().toStringEx();
    relapse.updatedAt = DateTime.now().toStringEx();
    await _db.insert(_tableName, relapse.toJson());
  }

  static Future<List<Map<String, dynamic>>> getAll() async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
      SELECT date, COUNT(id) AS count
      FROM $_tableName
      GROUP BY date
      ORDER BY date DESC
    ''');

    return maps;
  }

  static Future<String> getLastRelapse() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, limit: 1, orderBy: 'date DESC');
    if (maps.isEmpty) return '';
    return maps.first['date'] ?? '';
  }

  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return maps.length;
  }

  static Future<void> deleteAll() async => await _db.delete(_tableName);
}
