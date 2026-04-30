import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../models/videos_entity.dart';
import '_init_db.dart';

mixin DBWatchSession {
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<void> addSession({
    required Videos video,
    required Duration duration,
  }) async {
    if (duration.inSeconds <= 0) return;

    await _db.insert('watch_session', {
      'id': const UuidV4().generate(),
      'video_id': video.id ?? '',
      'video_code': video.videoCode ?? '',
      'watched_seconds': duration.inSeconds,
      'created_at': DateTime.now().toStringEx(),
    });
  }

  static Future<int> getCurrentStreakDays() async {
    final maps = await _db.rawQuery('''
      SELECT substr(created_at, 1, 10) AS day
      FROM watch_session
      GROUP BY substr(created_at, 1, 10)
      ORDER BY day DESC
    ''');

    if (maps.isEmpty) return 0;

    final uniqueDays = <DateTime>[];
    for (final item in maps) {
      final raw = '${item['day'] ?? ''}';
      if (raw.isEmpty) continue;
      final date = DateTime.tryParse(raw);
      if (date == null) continue;
      uniqueDays.add(DateTime(date.year, date.month, date.day));
    }

    if (uniqueDays.isEmpty) return 0;

    final todayRaw = DateTime.now();
    var cursor = DateTime(todayRaw.year, todayRaw.month, todayRaw.day);
    var streak = 0;

    for (final day in uniqueDays) {
      if (day.year == cursor.year && day.month == cursor.month && day.day == cursor.day) {
        streak++;
        cursor = cursor.subtract(1.days);
      } else {
        break;
      }
    }

    return streak;
  }
}
