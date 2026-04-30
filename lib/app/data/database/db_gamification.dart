import 'db_achievement.dart';
import 'db_activity.dart';
import 'db_profile.dart';
import 'db_videos.dart';
import 'db_watch_session.dart';

class GamificationSummary {
  final int streakDays;
  final int achievementCount;
  final List<AchievementUnlock> latestAchievements;

  GamificationSummary({
    required this.streakDays,
    required this.achievementCount,
    required this.latestAchievements,
  });
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

  AchievementProgress({
    required this.key,
    required this.title,
    required this.description,
    required this.group,
    required this.currentValue,
    required this.targetValue,
    required this.isUnlocked,
    required this.unlockedAt,
  });

  int get percent {
    if (isUnlocked) return 100;
    if (targetValue <= 0) return 0;
    return ((currentValue / targetValue) * 100).clamp(0, 100).toInt();
  }
}

class _AchievementDefinition {
  final String key;
  final String title;
  final String description;
  final String group;
  final int targetValue;
  final int Function(_GamificationStats stats) currentValue;

  const _AchievementDefinition({
    required this.key,
    required this.title,
    required this.description,
    required this.group,
    required this.targetValue,
    required this.currentValue,
  });
}

class _GamificationStats {
  final int totalVideo;
  final int watchHours;
  final int streakDays;
  final int relapseTotal;

  _GamificationStats({
    required this.totalVideo,
    required this.watchHours,
    required this.streakDays,
    required this.relapseTotal,
  });
}

mixin DBGamification {
  static final _definitions = <_AchievementDefinition>[
    _AchievementDefinition(
      key: 'collection_100',
      title: 'Collector I',
      description: 'Collected 100 videos',
      group: 'Collection',
      targetValue: 100,
      currentValue: (stats) => stats.totalVideo,
    ),
    _AchievementDefinition(
      key: 'collection_300',
      title: 'Collector II',
      description: 'Collected 300 videos',
      group: 'Collection',
      targetValue: 300,
      currentValue: (stats) => stats.totalVideo,
    ),
    _AchievementDefinition(
      key: 'collection_500',
      title: 'Collector III',
      description: 'Collected 500 videos',
      group: 'Collection',
      targetValue: 500,
      currentValue: (stats) => stats.totalVideo,
    ),
    _AchievementDefinition(
      key: 'watch_10h',
      title: 'Watcher I',
      description: 'Watched 10 hours in total',
      group: 'Watch Time',
      targetValue: 10,
      currentValue: (stats) => stats.watchHours,
    ),
    _AchievementDefinition(
      key: 'watch_50h',
      title: 'Watcher II',
      description: 'Watched 50 hours in total',
      group: 'Watch Time',
      targetValue: 50,
      currentValue: (stats) => stats.watchHours,
    ),
    _AchievementDefinition(
      key: 'watch_100h',
      title: 'Watcher III',
      description: 'Watched 100 hours in total',
      group: 'Watch Time',
      targetValue: 100,
      currentValue: (stats) => stats.watchHours,
    ),
    _AchievementDefinition(
      key: 'streak_3',
      title: 'Daily Streak I',
      description: 'Watched 3 consecutive days',
      group: 'Streak',
      targetValue: 3,
      currentValue: (stats) => stats.streakDays,
    ),
    _AchievementDefinition(
      key: 'streak_7',
      title: 'Daily Streak II',
      description: 'Watched 7 consecutive days',
      group: 'Streak',
      targetValue: 7,
      currentValue: (stats) => stats.streakDays,
    ),
    _AchievementDefinition(
      key: 'streak_14',
      title: 'Daily Streak III',
      description: 'Watched 14 consecutive days',
      group: 'Streak',
      targetValue: 14,
      currentValue: (stats) => stats.streakDays,
    ),
    _AchievementDefinition(
      key: 'relapse_zero',
      title: 'Pure Start',
      description: 'No relapse record yet',
      group: 'Relapse',
      targetValue: 1,
      currentValue: (stats) => stats.relapseTotal == 0 ? 1 : 0,
    ),
  ];

  static Future<GamificationSummary> syncAndGetSummary() async {
    final totalVideo = await DBVideos.getCount();
    await DBProfile.syncCollectionBadge(totalVideo);
    await DBProfile.syncWatchDurationBadge();

    final profile = await DBProfile.getProfile();
    final totalWatchSeconds = profile?.totalWatchDuration ?? 0;
    final streakDays = await DBWatchSession.getCurrentStreakDays();
    final relapseTotal = await DBActivity.countRelapse();

    await _unlockCollectionAchievements(totalVideo);
    await _unlockWatchAchievements(totalWatchSeconds);
    await _unlockStreakAchievements(streakDays);
    await _unlockRelapseAchievements(relapseTotal);

    final achievementCount = await DBAchievement.countUnlocked();
    final latestAchievements = await DBAchievement.getAll(limit: 3);

    return GamificationSummary(
      streakDays: streakDays,
      achievementCount: achievementCount,
      latestAchievements: latestAchievements,
    );
  }

  static Future<List<AchievementProgress>> getAchievementProgress() async {
    final stats = await _getStats();
    final unlocked = await DBAchievement.getAll();
    final unlockedByKey = {
      for (final item in unlocked) item.achievementKey: item,
    };

    final list = _definitions.map((definition) {
      final unlockedItem = unlockedByKey[definition.key];
      return AchievementProgress(
        key: definition.key,
        title: definition.title,
        description: definition.description,
        group: definition.group,
        currentValue: definition.currentValue(stats),
        targetValue: definition.targetValue,
        isUnlocked: unlockedItem != null,
        unlockedAt: unlockedItem?.unlockedAt ?? '',
      );
    }).toList();

    list.sort((a, b) {
      if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? -1 : 1;
      return b.percent.compareTo(a.percent);
    });
    return list;
  }

  static Future<_GamificationStats> _getStats() async {
    final totalVideo = await DBVideos.getCount();
    final profile = await DBProfile.getProfile();
    final totalWatchSeconds = profile?.totalWatchDuration ?? 0;
    final streakDays = await DBWatchSession.getCurrentStreakDays();
    final relapseTotal = await DBActivity.countRelapse();

    return _GamificationStats(
      totalVideo: totalVideo,
      watchHours: totalWatchSeconds ~/ 3600,
      streakDays: streakDays,
      relapseTotal: relapseTotal,
    );
  }

  static Future<void> _unlockCollectionAchievements(int totalVideo) async {
    if (totalVideo >= 100) {
      await DBAchievement.unlock(
        key: 'collection_100',
        title: 'Collector I',
        description: 'Collected 100 videos',
      );
    }
    if (totalVideo >= 300) {
      await DBAchievement.unlock(
        key: 'collection_300',
        title: 'Collector II',
        description: 'Collected 300 videos',
      );
    }
    if (totalVideo >= 500) {
      await DBAchievement.unlock(
        key: 'collection_500',
        title: 'Collector III',
        description: 'Collected 500 videos',
      );
    }
  }

  static Future<void> _unlockWatchAchievements(int totalWatchSeconds) async {
    final watchHours = totalWatchSeconds ~/ 3600;
    if (watchHours >= 10) {
      await DBAchievement.unlock(
        key: 'watch_10h',
        title: 'Watcher I',
        description: 'Watched 10 hours in total',
      );
    }
    if (watchHours >= 50) {
      await DBAchievement.unlock(
        key: 'watch_50h',
        title: 'Watcher II',
        description: 'Watched 50 hours in total',
      );
    }
    if (watchHours >= 100) {
      await DBAchievement.unlock(
        key: 'watch_100h',
        title: 'Watcher III',
        description: 'Watched 100 hours in total',
      );
    }
  }

  static Future<void> _unlockStreakAchievements(int streakDays) async {
    if (streakDays >= 3) {
      await DBAchievement.unlock(
        key: 'streak_3',
        title: 'Daily Streak I',
        description: 'Watched 3 consecutive days',
      );
    }
    if (streakDays >= 7) {
      await DBAchievement.unlock(
        key: 'streak_7',
        title: 'Daily Streak II',
        description: 'Watched 7 consecutive days',
      );
    }
    if (streakDays >= 14) {
      await DBAchievement.unlock(
        key: 'streak_14',
        title: 'Daily Streak III',
        description: 'Watched 14 consecutive days',
      );
    }
  }

  static Future<void> _unlockRelapseAchievements(int relapseTotal) async {
    if (relapseTotal == 0) {
      await DBAchievement.unlock(
        key: 'relapse_zero',
        title: 'Pure Start',
        description: 'No relapse record yet',
      );
    }
  }
}
