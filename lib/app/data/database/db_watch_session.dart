import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '_init_db.dart';
import 'db_profile.dart';

class WatchSession {
  const WatchSession({required this.id, required this.startedAt, required this.duration, this.videoId, this.videoCode});

  final String id;
  final String? videoId;
  final String? videoCode;
  final DateTime startedAt;
  final Duration duration;
}

mixin DBWatchSession {
  static Database get _db => Get.find<DBService>().dbMain;

  static Future<void> saveSessions(List<WatchSession> sessions) async {
    if (sessions.isEmpty) return;
    await _db.transaction((txn) async {
      var addedSeconds = 0;
      for (final session in sessions) {
        if (session.id.isEmpty || session.duration.isNegative) throw ArgumentError('Invalid watch session');
        final seconds = session.duration.inSeconds;
        if (seconds == 0) continue;
        final rows = await txn.query('watch_session', where: 'id = ?', whereArgs: [session.id], limit: 1);
        final previous = rows.isEmpty ? 0 : rows.first['watched_seconds'] as int;
        if (seconds <= previous) continue;
        await txn.rawInsert('''
          INSERT INTO watch_session (id, video_id, video_code, watched_seconds, created_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET watched_seconds = excluded.watched_seconds
        ''', [session.id, session.videoId, session.videoCode, seconds, session.startedAt.toStringEx()]);
        addedSeconds += seconds - previous;
      }
      if (addedSeconds == 0) return;
      final updated = await txn.rawUpdate('''
        UPDATE profile SET total_watch_duration = COALESCE(total_watch_duration, 0) + ?, updated_at = ? WHERE id = '1'
      ''', [addedSeconds, DateTime.now().toStringEx()]);
      if (updated != 1) throw StateError('Profile not found; watch sessions were not saved');
      final profile = await txn.query('profile', columns: ['total_watch_duration'], where: 'id = ?', whereArgs: ['1']);
      await txn.update('profile', {
        'badge_for_watch_duration': DBProfile.watchDurationBadge(profile.single['total_watch_duration'] as int),
      }, where: 'id = ?', whereArgs: ['1']);
    });
  }

  static Future<int> getCurrentStreakDays({DateTime? now}) async {
    final date = now ?? DateTime.now();
    final today = DateTime.utc(date.year, date.month, date.day);
    final maps = await _db.rawQuery('''
      SELECT DISTINCT substr(created_at, 1, 10) AS day FROM watch_session
      WHERE watched_seconds > 0 AND substr(created_at, 1, 10) <= ? ORDER BY day DESC
    ''', [today.toIso8601String().substring(0, 10)]);
    var cursor = today;
    var streak = 0;
    for (final item in maps) {
      final parsed = DateTime.tryParse('${item['day'] ?? ''}');
      if (parsed == null) continue;
      final day = DateTime.utc(parsed.year, parsed.month, parsed.day);
      if (streak == 0 && day == today.subtract(const Duration(days: 1))) cursor = day;
      if (day != cursor) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
