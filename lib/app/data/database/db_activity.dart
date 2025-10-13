import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../../core/const.dart';
import '../../utils/helper.dart';
import '../models/activity_entity.dart';
import '_init_db.dart';

// -- Activity Type
const kActivityTypeTodo = 'todo';
const kActivityTypeDownload = 'download';
const kActivityTypeRelapse = 'relapse';
// ---

mixin DBActivity {
  static final _db = Get.find<DBService>().dbMain;
  static final _tableName = 'activity';

  static Future<bool> _validation(Activity activity) async {
    if (activity.content.isNullOrEmpty) return false;

    // check duplicate 
    final alldata = await getAll(where: 'type = ?', whereArgs: [kActivityTypeTodo]);
    for (var data in alldata) {
      if (data.content == activity.content) {
        await HelperToast.warn('Already exists');
        return false;
      }
    }
    return true;
  }

  static Future<void> add(Activity activity) async {
    activity.id = UuidV4().generate();
    activity.createdAt = DateTime.now().toStringEx();
    activity.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validation(activity);
    if (isOK) await _db.insert(_tableName, activity.toJson());
  }

  static Future<void> update(Activity activity) async {
    await _validation(activity);
    final current = await getByID(activity.id ?? '');
    current.content = activity.content;
    current.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, current.toJson(), where: 'id = ?', whereArgs: [activity.id]);
  }

  static Future<void> delete(Activity activity) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [activity.id]);
  }

  static Future<void> deleteByFilename(String filename) async {
    await _db.delete(
      _tableName,
      where: 'type = ? AND json_extract(content, "\$.filename") LIKE ?',
      whereArgs: [kActivityTypeDownload, filename],
    );
  }

  static Future<List<Activity>> getAll({String? where, List<Object?>? whereArgs, String? orderBy, int? limit, String? groupBy}) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit, groupBy: groupBy);
    return List.generate(maps.length, (index) => Activity.fromJson(maps[index]));
  }

  static Future<List<Activity>> getAllRelapse() async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery('''
      SELECT *, count(content) as times
      FROM $_tableName
      WHERE type = ?
      GROUP BY content
      ORDER BY content desc
    ''', [kActivityTypeRelapse]);
    return List.generate(maps.length, (index) => Activity.fromJson(maps[index]));
  }

  static Future<int> getCountRelapseToday() async {
    final today = DateTime.now().toStringEx(format: kYMd);
    final maps = await _db.rawQuery('''
      SELECT COUNT(*) AS times
      FROM $_tableName
      WHERE type = ? AND content >= ? AND content <= ?
    ''', [kActivityTypeRelapse, today, today]);

    return maps.isNotEmpty ? maps[0]['times'] as int : 0;
  }

  static Future<Activity> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return List.generate(maps.length, (index) => Activity.fromJson(maps[index]))[0];
  }

  static Future<Activity> getByFilename(String filename) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      _tableName,
      where: 'type = ? AND json_extract(content, "\$.filename") LIKE ?',
      whereArgs: [kActivityTypeDownload, filename],
    );
    return List.generate(maps.length, (index) => Activity.fromJson(maps[index]))[0];
  }


  static Future<int> getCount() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return maps.length;
  }

  static Future<void> deleteAll({String? where, List<Object?>? whereArgs}) async {
    await _db.delete(_tableName, where: where, whereArgs: whereArgs);
  }
}
