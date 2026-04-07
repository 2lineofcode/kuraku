import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../../core/const.dart';
import '../models/activity_entity.dart';
import '_init_db.dart';

// -- Activity Type
const kActivityTypeTodo = 'todo';
const kActivityTypeDownload = 'download';
const kActivityTypeRelapse = 'relapse';
// ---

mixin DBActivity {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _tableName = 'activity';

  // ────────────────────────────────────────────────────────────────
  // ⵌ COMMON UTILITIES
  // ────────────────────────────────────────────────────────────────
  static Activity _stamp(Activity activity) {
    final now = DateTime.now().toStringEx();
    activity.id ??= UuidV4().generate();
    activity.createdAt ??= now;
    activity.updatedAt = now;
    return activity;
  }

  static Future<bool> _validation(Activity activity) async {
    final content = activity.content?.trim();
    if (content.isNullOrEmpty) return false;

    // Only TODO type enforces duplicate check.
    if (activity.type == kActivityTypeTodo) {
      final dup = await _db.query(
        _tableName,
        where: 'type = ? AND lower(content) = lower(?)',
        whereArgs: [kActivityTypeTodo, content],
        limit: 1,
      );
      if (dup.isNotEmpty) {
        AppLog.logW('Rejected duplicate todo: "$content"');
        return false;
      }
    }
    return true;
  }

  static Future<bool> _insert(Activity activity) async {
    if (!await _validation(activity)) return false;
    await _db.insert(_tableName, _stamp(activity).toJson());
    return true;
  }

  static Future<void> _update(Activity activity) async {
    if (!await _validation(activity)) return;
    activity.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, activity.toJson(), where: 'id = ?', whereArgs: [activity.id]);
  }

  static Future<void> _delete({required String where, List<Object?>? whereArgs}) async {
    await _db.delete(_tableName, where: where, whereArgs: whereArgs);
  }

  static Future<void> deleteAll({String? where, List<Object?>? whereArgs}) async {
    await _delete(where: where ?? '1 = 1', whereArgs: whereArgs);
  }

  static Future<List<Activity>> _query({
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
    return List.generate(maps.length, (index) => Activity.fromJson(maps[index]));
  }

  static Future<Activity?> _queryOne({String? where, List<Object?>? whereArgs}) async {
    final data = await _query(where: where, whereArgs: whereArgs, limit: 1);
    return data.isEmpty ? null : data.first;
  }

  static Future<int> _count({String? where, List<Object?>? whereArgs}) async {
    final maps = await _db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $_tableName ${where != null ? 'WHERE $where' : ''}',
      whereArgs,
    );
    return maps.isNotEmpty ? (maps.first['cnt'] as int? ?? 0) : 0;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ PART: TODO
  // ────────────────────────────────────────────────────────────────
  static Future<Activity?> getTodo(String id) => _queryOne(where: 'id = ? AND type = ?', whereArgs: [id, kActivityTypeTodo]);

  static Future<List<Activity>> getTodos({String? orderBy}) => _query(where: 'type = ?', whereArgs: [kActivityTypeTodo], orderBy: orderBy ?? 'updated_at DESC');

  static Future<Activity?> addTodo(String content) async {
    final todo = Activity(type: kActivityTypeTodo, content: content.trim());
    final ok = await _insert(todo);
    return ok ? todo : null;
  }

  static Future<Activity?> updateTodo({required String id, required String content}) async {
    final current = await getTodo(id);
    if (current == null) return null;
    current.content = content.trim();
    await _update(current);
    return current;
  }

  static Future<void> deleteTodo(String id) => _delete(where: 'id = ? AND type = ?', whereArgs: [id, kActivityTypeTodo]);

  static Future<int> countTodo() => _count(where: 'type = ?', whereArgs: [kActivityTypeTodo]);

  // ────────────────────────────────────────────────────────────────
  // ⵌ PART: DOWNLOAD LOG
  // ────────────────────────────────────────────────────────────────
  static Future<Activity?> getDownloadLog(String id) => _queryOne(where: 'id = ? AND type = ?', whereArgs: [id, kActivityTypeDownload]);

  static Future<Activity?> getDownloadLogByFilename(String filename) => _queryOne(
        where: 'type = ? AND json_extract(content, "\$.filename") LIKE ?',
        whereArgs: [kActivityTypeDownload, filename],
      );

  static Future<List<Activity>> getDownloadLogs({String? orderBy, String? groupBy}) => _query(
        where: 'type = ?',
        whereArgs: [kActivityTypeDownload],
        orderBy: orderBy ?? 'updated_at DESC',
        groupBy: groupBy,
      );

  static Future<Activity?> addDownloadLog(Activity activity) async {
    activity.type = kActivityTypeDownload;
    final ok = await _insert(activity);
    return ok ? activity : null;
  }

  static Future<Activity?> updateDownloadLog({required String id, required String content}) async {
    final current = await getDownloadLog(id);
    if (current == null) return null;
    current.content = content.trim();
    await _update(current);
    return current;
  }

  static Future<void> deleteDownloadLog(String id) => _delete(where: 'id = ? AND type = ?', whereArgs: [id, kActivityTypeDownload]);

  static Future<void> deleteDownloadLogByFilename(String filename) => _delete(
        where: 'type = ? AND json_extract(content, "\$.filename") LIKE ?',
        whereArgs: [kActivityTypeDownload, filename],
      );

  static Future<int> countDownloadLog() => _count(where: 'type = ?', whereArgs: [kActivityTypeDownload]);

  // ────────────────────────────────────────────────────────────────
  // ⵌ PART: RELAPSE / ACTIVITY
  // ────────────────────────────────────────────────────────────────
  static Future<Activity?> getRelapse(String id) => _queryOne(where: 'id = ? AND type = ?', whereArgs: [id, kActivityTypeRelapse]);

  /// Returns relapse data grouped by date with aggregated `times`.
  static Future<List<Activity>> getAllRelapse() async {
    final maps = await _db.rawQuery('''
      SELECT *, count(content) as times
      FROM $_tableName
      WHERE type = ?
      GROUP BY content
      ORDER BY content desc
    ''', [kActivityTypeRelapse]);
    return List.generate(maps.length, (index) => Activity.fromJson(maps[index]));
  }

  static Future<Activity?> addRelapse({DateTime? date}) async {
    final relapse = Activity(
      type: kActivityTypeRelapse,
      content: (date ?? DateTime.now()).toStringEx(format: kYMd),
    );
    final ok = await _insert(relapse);
    return ok ? relapse : null;
  }

  static Future<Activity?> updateRelapse({required String id, required DateTime date}) async {
    final current = await getRelapse(id);
    if (current == null) return null;
    current.content = date.toStringEx(format: kYMd);
    await _update(current);
    return current;
  }

  static Future<void> deleteRelapse(String id) => _delete(where: 'id = ? AND type = ?', whereArgs: [id, kActivityTypeRelapse]);

  static Future<void> deleteRelapseByDateLimitOne(String date) =>
      _db.rawDelete('DELETE FROM $_tableName WHERE type = ? AND content = ? ORDER BY content DESC, id DESC LIMIT 1', [kActivityTypeRelapse, date]);

  static Future<int> countRelapse({DateTime? start, DateTime? end}) async {
    if (start == null && end == null) {
      return _count(where: 'type = ?', whereArgs: [kActivityTypeRelapse]);
    }

    final startStr = (start ?? DateTime.now()).toStringEx(format: kYMd);
    final endStr = (end ?? DateTime.now()).toStringEx(format: kYMd);
    final maps = await _db.rawQuery('''
      SELECT COUNT(*) AS times
      FROM $_tableName
      WHERE type = ? AND content >= ? AND content <= ?
    ''', [kActivityTypeRelapse, startStr, endStr]);

    return maps.isNotEmpty ? maps[0]['times'] as int : 0;
  }

  static Future<int> getCountRelapseToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return countRelapse(start: today, end: today);
  }
}
