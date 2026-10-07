import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '_init_db.dart';

class AchievementUnlock {
  final String id;
  final String achievementKey;
  final String title;
  final String description;
  final String unlockedAt;

  AchievementUnlock({
    required this.id,
    required this.achievementKey,
    required this.title,
    required this.description,
    required this.unlockedAt,
  });

  factory AchievementUnlock.fromMap(Map<String, dynamic> map) {
    return AchievementUnlock(
      id: '${map['id'] ?? ''}',
      achievementKey: '${map['achievement_key'] ?? ''}',
      title: '${map['title'] ?? ''}',
      description: '${map['description'] ?? ''}',
      unlockedAt: '${map['unlocked_at'] ?? ''}',
    );
  }
}

mixin DBAchievement {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _tableName = 'achievement_unlock';

  static Future<List<AchievementUnlock>> getAll({int? limit}) async {
    final maps = await _db.query(
      _tableName,
      orderBy: 'unlocked_at DESC',
      limit: limit,
    );
    return maps.map(AchievementUnlock.fromMap).toList();
  }

  static Future<int> countUnlocked() async {
    final maps = await _db.rawQuery('SELECT COUNT(*) AS total FROM $_tableName');
    return (maps.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<bool> isUnlocked(String key) async {
    final maps = await _db.query(
      _tableName,
      where: 'achievement_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  static Future<bool> unlock({
    required String key,
    required String title,
    required String description,
  }) async {
    if (key.trim().isEmpty || title.trim().isEmpty) throw ArgumentError('Achievement key and title are required');

    final now = DateTime.now().toStringEx();
    try {
      await _db.insert(_tableName, {
        'id': const UuidV4().generate(),
        'achievement_key': key,
        'title': title,
        'description': description,
        'unlocked_at': now,
        'created_at': now,
        'updated_at': now,
      });
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError('achievement_unlock.achievement_key')) rethrow;
      return false;
    }
    return true;
  }
}
