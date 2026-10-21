import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '_init_db.dart';
import 'db_achievement.dart';
import 'db_profile.dart';
import 'db_watch_session.dart';

class GamificationSummary {
  final int streakDays;
  final List<AchievementProgress> progress;
  final List<AchievementUnlock> latestAchievements;
  final List<String> newAchievementTitles;
  final Map<String, int> stats;

  GamificationSummary({required this.streakDays, required this.progress, required this.latestAchievements,
    required this.newAchievementTitles, required this.stats});

  int get achievementCount => progress.where((item) => item.isUnlocked).length;
  int get xp => progress.where((item) => item.isUnlocked).fold(0, (total, item) => total + item.xp);
  int get level => xp ~/ 500 + 1;
  int get levelXp => xp % 500;
  String get rank => level >= 10 ? 'Archive Legend' : level >= 7 ? 'Master Curator' : level >= 4 ? 'Collection Expert' : level >= 2 ? 'Rising Curator' : 'New Explorer';
}

class AchievementProgress {
  final String key;
  final String title;
  final String description;
  final String group;
  final int currentValue;
  final int targetValue;
  final bool isUnlocked;
  final String unlockedAt;
  final int xp;
  final String unit;

  AchievementProgress({required this.key, required this.title, required this.description, required this.group,
    required this.currentValue, required this.targetValue, required this.isUnlocked, required this.unlockedAt,
    this.xp = 0, this.unit = ''});

  int get percent {
    if (isUnlocked) return 100;
    if (targetValue <= 0) return 0;
    return ((currentValue / targetValue) * 100).clamp(0, 100).toInt();
  }

  int get remaining => targetValue <= 0 ? 0 : (targetValue - currentValue).clamp(0, targetValue);
}

class _AchievementDefinition {
  final String key;
  final String title;
  final String description;
  final String group;
  final String metric;
  final int target;
  final int xp;
  final String unit;

  const _AchievementDefinition(this.key, this.title, this.description, this.group, this.metric, this.target, this.xp, this.unit);
}

mixin DBGamification {
  static Database get _db => Get.find<DBService>().dbMain;

  static const _definitions = [
    _AchievementDefinition('collection_1', 'First Steps', 'Add your first video to the library.', 'Collection', 'videos', 1, 50, 'videos'),
    _AchievementDefinition('collection_25', 'Growing Shelf', 'Build a collection of 25 videos.', 'Collection', 'videos', 25, 100, 'videos'),
    _AchievementDefinition('collection_100', 'Collector I', 'Collected 100 videos', 'Collection', 'videos', 100, 200, 'videos'),
    _AchievementDefinition('collection_300', 'Collector II', 'Collected 300 videos', 'Collection', 'videos', 300, 300, 'videos'),
    _AchievementDefinition('collection_500', 'Collector III', 'Collected 500 videos', 'Collection', 'videos', 500, 400, 'videos'),
    _AchievementDefinition('collection_1000', 'Archive Legend', 'Build a collection of 1,000 videos.', 'Collection', 'videos', 1000, 500, 'videos'),
    _AchievementDefinition('favorite_1', 'A Personal Pick', 'Save your first favorite.', 'Curation', 'favorites', 1, 50, 'favorites'),
    _AchievementDefinition('favorite_10', 'Good Taste', 'Choose 10 favorite videos.', 'Curation', 'favorites', 10, 150, 'favorites'),
    _AchievementDefinition('favorite_50', 'Personal Hall of Fame', 'Choose 50 favorite videos.', 'Curation', 'favorites', 50, 300, 'favorites'),
    _AchievementDefinition('playlist_1', 'The Organizer', 'Create a playlist with at least one video.', 'Curation', 'playlists', 1, 100, 'playlists'),
    _AchievementDefinition('playlist_3', 'Shelf Architect', 'Build 3 non-empty playlists.', 'Curation', 'playlists', 3, 250, 'playlists'),
    _AchievementDefinition('curated_10', 'Everything in Its Place', 'Organize 10 different videos into playlists.', 'Curation', 'curated', 10, 150, 'videos'),
    _AchievementDefinition('curated_50', 'A Curated Archive', 'Organize 50 different videos into playlists.', 'Curation', 'curated', 50, 300, 'videos'),
    _AchievementDefinition('studio_3', 'Studio Sampler', 'Collect videos from 3 different studios.', 'Exploration', 'studios', 3, 100, 'studios'),
    _AchievementDefinition('studio_10', 'Studio Explorer', 'Collect videos from 10 different studios.', 'Exploration', 'studios', 10, 250, 'studios'),
    _AchievementDefinition('studio_25', 'Across the Industry', 'Collect videos from 25 different studios.', 'Exploration', 'studios', 25, 400, 'studios'),
    _AchievementDefinition('actress_5', 'New Faces', 'Collect videos featuring 5 different actresses.', 'Exploration', 'actresses', 5, 100, 'actresses'),
    _AchievementDefinition('actress_25', 'Cast Explorer', 'Collect videos featuring 25 different actresses.', 'Exploration', 'actresses', 25, 250, 'actresses'),
    _AchievementDefinition('actress_100', 'A Hundred Faces', 'Collect videos featuring 100 different actresses.', 'Exploration', 'actresses', 100, 400, 'actresses'),
    _AchievementDefinition('category_5', 'Beyond the Usual', 'Collect videos across 5 different categories.', 'Exploration', 'categories', 5, 100, 'categories'),
    _AchievementDefinition('category_15', 'Genre Explorer', 'Collect videos across 15 different categories.', 'Exploration', 'categories', 15, 300, 'categories'),
    _AchievementDefinition('explored_1', 'Press Play', 'Explore one video for at least a minute.', 'Watch Time', 'explored', 1, 50, 'videos'),
    _AchievementDefinition('explored_10', 'Off the Shelf', 'Explore 10 different videos for at least a minute each.', 'Watch Time', 'explored', 10, 100, 'videos'),
    _AchievementDefinition('explored_50', 'Library Wanderer', 'Explore 50 different videos for at least a minute each.', 'Watch Time', 'explored', 50, 200, 'videos'),
    _AchievementDefinition('watch_1h', 'Getting Comfortable', 'Watch one hour in total.', 'Watch Time', 'watch_minutes', 60, 50, 'minutes'),
    _AchievementDefinition('watch_10h', 'Watcher I', 'Watched 10 hours in total', 'Watch Time', 'watch_minutes', 600, 100, 'minutes'),
    _AchievementDefinition('watch_50h', 'Watcher II', 'Watched 50 hours in total', 'Watch Time', 'watch_minutes', 3000, 150, 'minutes'),
    _AchievementDefinition('watch_100h', 'Watcher III', 'Watched 100 hours in total', 'Watch Time', 'watch_minutes', 6000, 200, 'minutes'),
    _AchievementDefinition('streak_3', 'Daily Streak I', 'Watch at least one minute on 3 consecutive days.', 'Streak', 'streak', 3, 50, 'days'),
    _AchievementDefinition('streak_7', 'Daily Streak II', 'Watch at least one minute on 7 consecutive days.', 'Streak', 'streak', 7, 100, 'days'),
    _AchievementDefinition('streak_14', 'Daily Streak III', 'Watch at least one minute on 14 consecutive days.', 'Streak', 'streak', 14, 150, 'days'),
  ];

  static Future<GamificationSummary> syncAndGetSummary({Map<String, int>? collectionStats}) async {
    final stats = await _getStats(collectionStats: collectionStats);
    if (collectionStats == null) await DBProfile.syncCollectionBadge(stats['videos']!);
    await DBProfile.syncWatchDurationBadge();
    final unlocked = await DBAchievement.getAll();
    final keys = unlocked.map((item) => item.achievementKey).toSet();
    final newTitles = <String>[];
    for (final definition in _definitions) {
      if (!keys.contains(definition.key) && stats[definition.metric]! >= definition.target) {
        if (await DBAchievement.unlock(key: definition.key, title: definition.title, description: definition.description)) {
          newTitles.add(definition.title);
        }
      }
    }
    final all = await DBAchievement.getAll();
    return GamificationSummary(streakDays: stats['streak']!, progress: _progress(stats, all),
      latestAchievements: all.take(3).toList(), newAchievementTitles: newTitles, stats: stats);
  }

  static List<AchievementProgress> _progress(Map<String, int> stats, List<AchievementUnlock> unlocked) {
    final byKey = {for (final item in unlocked) item.achievementKey: item};
    final list = _definitions.map((definition) => AchievementProgress(
      key: definition.key, title: definition.title, description: definition.description, group: definition.group,
      currentValue: stats[definition.metric]!, targetValue: definition.target, xp: definition.xp, unit: definition.unit,
      isUnlocked: byKey.containsKey(definition.key), unlockedAt: byKey[definition.key]?.unlockedAt ?? '',
    )).toList();
    // Keep retired unlocks visible without awarding XP for an empty history.
    for (final item in unlocked.where((item) => !_definitions.any((definition) => definition.key == item.achievementKey))) {
      list.add(AchievementProgress(key: item.achievementKey, title: item.title,
        description: item.achievementKey == 'relapse_zero' ? 'Legacy milestone: started with no relapse records.' : item.description,
        group: 'Legacy', currentValue: 1, targetValue: 1, isUnlocked: true, unlockedAt: item.unlockedAt));
    }
    list.sort((a, b) {
      if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? 1 : -1;
      if (a.isUnlocked) {
        final date = b.unlockedAt.compareTo(a.unlockedAt);
        if (date != 0) return date;
      }
      final percent = b.percent.compareTo(a.percent);
      if (percent != 0) return percent;
      if (!a.isUnlocked) {
        final reward = a.xp.compareTo(b.xp);
        if (reward != 0) return reward;
        final target = a.targetValue.compareTo(b.targetValue);
        if (target != 0) return target;
      }
      return a.key.compareTo(b.key);
    });
    return list;
  }

  static Future<Map<String, int>> _getStats({Map<String, int>? collectionStats}) async {
    final stats = <String, int>{...?collectionStats};
    if (collectionStats == null) {
      final library = (await _db.rawQuery('''
        SELECT COUNT(*) AS videos, COALESCE(SUM(is_favorite), 0) AS favorites,
          COUNT(DISTINCT CASE WHEN trim(studio) != '' AND lower(trim(studio)) != 'null' THEN lower(trim(studio)) END) AS studios
        FROM videos WHERE is_deleted = 0
      ''')).single;
      final curation = (await _db.rawQuery('''
        SELECT COUNT(DISTINCT item.playlist_id) AS playlists, COUNT(DISTINCT item.video_id) AS curated
        FROM playlist_item item JOIN videos video ON video.id = item.video_id WHERE video.is_deleted = 0
      ''')).single;
      stats.addAll({for (final row in [library, curation]) for (final entry in row.entries) entry.key: (entry.value as num).toInt()});
      for (final field in ['actress', 'category']) {
        final name = field == 'actress' ? 'name_romaji' : 'category';
        final rows = await _db.rawQuery('''
          SELECT COUNT(DISTINCT CASE WHEN CAST(json_extract(item.value, '\$.id') AS INTEGER) > 0
            THEN 'id:' || CAST(json_extract(item.value, '\$.id') AS INTEGER)
            ELSE 'name:' || lower(trim(json_extract(item.value, '\$.$name'))) END) AS total
          FROM videos video, json_each(CASE WHEN json_valid(video.$field) THEN video.$field ELSE '[]' END) item
          WHERE video.is_deleted = 0 AND item.type = 'object'
            AND json_type(item.value, '\$.$name') = 'text'
            AND trim(COALESCE(json_extract(item.value, '\$.$name'), '')) != ''
            AND lower(trim(json_extract(item.value, '\$.$name'))) != 'null'
        ''');
        stats[field == 'actress' ? 'actresses' : 'categories'] = (rows.single['total'] as num).toInt();
      }
    }
    final explored = await _db.rawQuery('''
      SELECT COUNT(*) AS total FROM (
        SELECT video_id FROM watch_session WHERE video_id IS NOT NULL
        GROUP BY video_id HAVING SUM(watched_seconds) >= 60
      )
    ''');
    stats['explored'] = (explored.single['total'] as num).toInt();
    stats['watch_minutes'] = ((await DBProfile.getProfile())?.totalWatchDuration ?? 0) ~/ 60;
    stats['streak'] = await DBWatchSession.getCurrentStreakDays();
    return stats;
  }
}
