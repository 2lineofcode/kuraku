import 'dart:convert';

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

  static String _table(String? type) => switch (type) {
    kActivityTypeTodo => 'todo',
    kActivityTypeDownload => 'download_log',
    kActivityTypeRelapse => 'relapse_event',
    _ => throw ArgumentError('Unsupported activity type: $type'),
  };

  static Map<String, dynamic> _values(Activity activity) => {
    'id': activity.id,
    switch (activity.type) {
      kActivityTypeTodo => 'title',
      kActivityTypeDownload => 'payload',
      kActivityTypeRelapse => 'occurred_on',
      _ => throw ArgumentError('Unsupported activity type: ${activity.type}'),
    }: activity.content,
    'created_at': activity.createdAt,
    'updated_at': activity.updatedAt,
  };

  static bool _validation(Activity activity) {
    final content = activity.content?.trim();
    if (content == null || content.isEmpty) return false;
    if (activity.type == kActivityTypeDownload) {
      try {
        final payload = jsonDecode(content);
        if (payload is! Map<String, dynamic> || !isValidDownloadPayload(payload)) return false;
      } on FormatException {
        return false;
      }
    }
    return true;
  }

  static Future<bool> _insert(Activity activity) async {
    if (!_validation(activity)) return false;
    try {
      await _db.insert(_table(activity.type), _values(_stamp(activity)));
      return true;
    } on DatabaseException catch (error) {
      if (activity.type != kActivityTypeTodo || !error.isUniqueConstraintError('todo.title')) rethrow;
      AppLog.logW('Rejected duplicate todo: "${activity.content}"');
      return false;
    }
  }

  static Future<void> deleteAll({String? where, List<Object?>? whereArgs}) async {
    await _db.transaction((txn) async {
      for (final type in [kActivityTypeTodo, kActivityTypeDownload, kActivityTypeRelapse]) {
        await txn.delete(_table(type),
          where: where == null ? null : 'id IN (SELECT id FROM activity WHERE type = ? AND ($where))',
          whereArgs: where == null ? null : [type, ...?whereArgs]);
      }
    });
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
  static Future<List<Activity>> getTodos({String? orderBy}) => _query(where: 'type = ?', whereArgs: [kActivityTypeTodo], orderBy: orderBy ?? 'updated_at DESC');

  static Future<Activity?> addTodo(String content) async {
    final todo = Activity(type: kActivityTypeTodo, content: content.trim());
    final ok = await _insert(todo);
    return ok ? todo : null;
  }

  static Future<void> deleteTodo(String id) async {
    await _db.delete('todo', where: 'id = ?', whereArgs: [id]);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ PART: DOWNLOAD LOG
  // ────────────────────────────────────────────────────────────────
  static Future<Activity?> getDownloadLog(String id) => _queryOne(where: 'id = ? AND type = ?', whereArgs: [id, kActivityTypeDownload]);

  static Future<Activity?> getDownloadLogByFilename(String filename) => _queryOne(
        where: 'type = ? AND id IN (SELECT id FROM download_log WHERE filename LIKE ?)',
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
    if (!_validation(current)) return null;
    current.updatedAt = DateTime.now().toStringEx();
    final changed = await _db.update('download_log', {'payload': current.content, 'updated_at': current.updatedAt},
      where: 'id = ?', whereArgs: [id]);
    return changed == 0 ? null : current;
  }

  static Future<void> deleteDownloadLogByFilename(String filename) async {
    await _db.delete('download_log', where: 'filename LIKE ?', whereArgs: [filename]);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ PART: RELAPSE / ACTIVITY
  // ────────────────────────────────────────────────────────────────
  static Future<Activity?> getLatestRelapseTransaction() async {
    final maps = await _db.query(
      _tableName,
      where: 'type = ?',
      whereArgs: [kActivityTypeRelapse],
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );
    return maps.isEmpty ? null : Activity.fromJson(maps.first);
  }

  /// Returns relapse data grouped by date with aggregated `times`.
  static Future<List<Activity>> getAllRelapse() async {
    final maps = await _db.rawQuery('''
      SELECT
        NULL as id,
        type,
        content,
        count(content) as times,
        max(created_at) as created_at,
        max(updated_at) as updated_at
      FROM $_tableName
      WHERE type = ?
      GROUP BY type, content
      ORDER BY content desc, created_at desc
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

  static Future<Activity?> deleteRelapseByDateLimitOne(String date) async {
    return _db.transaction((txn) async {
      final rows = await txn.query(_tableName, where: 'type = ? AND content = ?',
        whereArgs: [kActivityTypeRelapse, date], orderBy: 'created_at DESC, id DESC', limit: 1);
      if (rows.isEmpty) return null;
      final item = Activity.fromJson(rows.first);
      await txn.delete('relapse_event', where: 'id = ?', whereArgs: [item.id]);
      return item;
    });
  }

  static Future<void> restoreRelapse(Activity item) async {
    if (item.type != kActivityTypeRelapse || item.id == null || item.content == null) {
      throw ArgumentError('Invalid relapse record');
    }
    try {
      await _db.insert('relapse_event', _values(item));
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError('relapse_event.id')) rethrow;
    }
  }

  static Future<int> countRelapse({DateTime? start, DateTime? end}) async {
    if (start == null && end == null) {
      return _count(where: 'type = ?', whereArgs: [kActivityTypeRelapse]);
    }

    final conditions = <String>[];
    final args = <Object?>[];
    if (start != null) {
      conditions.add('occurred_on >= ?');
      args.add(start.toStringEx(format: kYMd));
    }
    if (end != null) {
      conditions.add('occurred_on <= ?');
      args.add(end.toStringEx(format: kYMd));
    }
    final maps = await _db.rawQuery('''
      SELECT COUNT(*) AS times FROM relapse_event WHERE ${conditions.join(' AND ')}
    ''', args);

    return maps.isNotEmpty ? maps[0]['times'] as int : 0;
  }

  static Future<int> getCountRelapseToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return countRelapse(start: today, end: today);
  }
}
