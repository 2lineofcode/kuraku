import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../models/profile_entity.dart';
import '_init_db.dart';

mixin DBProfile {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _tableName = 'profile';

  static Future<Profile?> getProfile() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: ['1']);
    return maps.isNotEmpty ? Profile.fromJson(maps.first) : null;
  }

  static Future<void> updateName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Name cannot be empty');
    final updated = await _db.update(_tableName, {
      'name': trimmed,
      'updated_at': DateTime.now().toStringEx(),
    }, where: 'id = ?', whereArgs: ['1']);
    if (updated == 0) throw StateError('Profile not found');
  }

  static Future<void> syncCollectionBadge(int totalVideo) async {
    await _db.update(_tableName, {'badge_for_collection': _collectionBadge(totalVideo)}, where: 'id = ?', whereArgs: ['1']);
  }

  static Future<void> syncWatchDurationBadge() async {
    await _db.transaction((txn) async {
      final rows = await txn.query(_tableName, columns: ['total_watch_duration'], where: 'id = ?', whereArgs: ['1']);
      if (rows.isEmpty) return;
      await txn.update(_tableName, {'badge_for_watch_duration': watchDurationBadge((rows.first['total_watch_duration'] as int?) ?? 0)},
        where: 'id = ?', whereArgs: ['1']);
    });
  }

  static String _collectionBadge(int count) {
    if (count == 0) return 'Noobless';
    if (count > 0 && count <= 100) {
      return 'Newbie Explorer';
    } else if (count > 100 && count <= 200) {
      return 'Jav Lover';
    } else if (count > 200 && count <= 300) {
      return 'Jav Hunter';
    } else if (count > 300 && count <= 400) {
      return 'True Nolep';
    } else if (count > 400 && count <= 500) {
      return 'Degenerate';
    } else if (count > 500 && count <= 1000) {
      return 'Certified Freak';
    } else {
      return 'Nolep x_x (beyond redemption)';
    }
  }

  static String watchDurationBadge(int seconds) {
    if (seconds <= 0) return 'Fresh Eyes';

    final hours = seconds ~/ 3600;
    if (hours <= 10) {
      return 'Warm Up';
    } else if (hours <= 50) {
      return 'Night Owl';
    } else if (hours <= 150) {
      return 'Screen Warrior';
    } else if (hours <= 300) {
      return 'Marathoner';
    } else {
      return 'Time Bender';
    }
  }
}
