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

  static Future<void> update(Profile profile) async {
    profile.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, profile.toJson(), where: 'id = ?', whereArgs: [profile.id]);
  }

  static Future<void> updateTotalWatchDuration(Duration duration) async {
    final profile = await getProfile();
    if (profile == null) return;

    profile.totalWatchDuration = (profile.totalWatchDuration ?? 0) + duration.inSeconds;
    await update(profile);
  }
}
