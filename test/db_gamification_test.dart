import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/_update_db.dart';
import 'package:kuraku/app/data/database/db_achievement.dart';
import 'package:kuraku/app/data/database/db_gamification.dart';
import 'package:kuraku/app/data/database/db_playlist.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/database/db_watch_session.dart';
import 'package:kuraku/app/data/models/playlist_entity.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/home_controller.dart';

import 'sqlite_test_database.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  void onReady() {}
  @override
  void onClose() {
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteTestDatabase db;
  setUp(() async {
    db = await SqliteTestDatabase.open();
    await db.transaction((_) => DBService.onCreate(db, DBUpdate.version));
    Get.put<DBService>(_Service()..dbMain = db);
  });
  tearDown(() async {
    Get.reset();
    await db.close();
  });

  Future<void> video(String id, {String studio = '', bool favorite = false, bool deleted = false,
    List<Object?> actresses = const [], List<Object?> categories = const []}) => db.insert('videos', {
    'id': id, 'root_path': '/videos', 'video_path': '/videos/$id.mp4', 'studio': studio,
    'is_favorite': favorite ? 1 : 0, 'is_deleted': deleted ? 1 : 0,
    'actress': jsonEncode(actresses), 'category': jsonEncode(categories),
  }).then((_) {});

  test('An empty profile earns no XP and does not unlock Pure Start', () async {
    final summary = await DBGamification.syncAndGetSummary();
    expect(summary.progress, hasLength(31));
    expect(summary.achievementCount, 0);
    expect(summary.xp, 0);
    expect(summary.level, 1);
    expect(summary.rank, 'New Explorer');
    expect(summary.newAchievementTitles, isEmpty);
    expect(summary.progress.first.key, 'collection_1');
    expect(summary.progress.any((item) => item.key == 'relapse_zero'), isFalse);
    expect(await DBAchievement.countUnlocked(), 0);
  });

  test('Exploration normalizes metadata, ignores deleted rows and counts unique playlist videos', () async {
    await video('a', studio: ' Studio A ', favorite: true,
      actresses: [{'id': 1, 'name_romaji': 'Jane'}, {'id': 0, 'name_romaji': ' New Face '}, 'bad item', 1, null],
      categories: [{'id': 1, 'category': 'Drama'}, {'id': 0, 'category': ' Action '}]);
    await video('b', studio: 'studio a', favorite: true,
      actresses: [{'id': '01', 'name_romaji': 'Jane Alias'}, {'name_romaji': 'new face'}, {'id': 2, 'name_romaji': ''}],
      categories: [{'id': 1, 'category': 'Drama alias'}, {'category': 'action'}, {'category': 'null'}]);
    await video('c', studio: 'null');
    await video('gone', studio: 'Other', favorite: true, deleted: true,
      actresses: [{'id': 99, 'name_romaji': 'Deleted'}], categories: [{'id': 99, 'category': 'Deleted'}]);
    for (final id in ['one', 'two', 'empty', 'deleted-only']) {
      await db.insert('playlist', {'id': id, 'name': id});
    }
    for (final item in [('one', 'a'), ('one', 'b'), ('two', 'a'), ('deleted-only', 'gone')]) {
      await db.insert('playlist_item', {'playlist_id': item.$1, 'video_id': item.$2});
    }
    final summary = await DBGamification.syncAndGetSummary();
    expect(summary.stats, containsPair('videos', 3));
    expect(summary.stats, containsPair('favorites', 2));
    expect(summary.stats, containsPair('studios', 1));
    expect(summary.stats, containsPair('actresses', 2));
    expect(summary.stats, containsPair('categories', 2));
    expect(summary.stats, containsPair('playlists', 2));
    expect(summary.stats, containsPair('curated', 2));
    expect(summary.xp, 200);
    expect(summary.progress.singleWhere((item) => item.key == 'playlist_3').currentValue, 2);
  });

  test('XP and old unlocks survive deletion and repeated concurrent syncs', () async {
    await DBAchievement.unlock(key: 'relapse_zero', title: 'Pure Start', description: 'No relapse record yet');
    for (var i = 0; i < 25; i++) { await video('$i', favorite: true); }
    final summary = await DBGamification.syncAndGetSummary();
    expect(summary.xp, 350);
    expect(summary.achievementCount, 5);
    expect(summary.latestAchievements.map((item) => item.title), ['Good Taste', 'A Personal Pick', 'Growing Shelf']);
    final legacy = summary.progress.singleWhere((item) => item.key == 'relapse_zero');
    expect(legacy.group, 'Legacy');
    expect(legacy.xp, 0);
    await db.update('videos', {'is_deleted': 1});
    final repeated = await Future.wait(List.generate(2, (_) => DBGamification.syncAndGetSummary()));
    for (final result in repeated) {
      expect(result.xp, summary.xp);
      expect(result.newAchievementTitles, isEmpty);
      expect(result.progress.singleWhere((item) => item.key == 'collection_25').percent, 100);
    }
    await video('new', favorite: true);
    expect((await DBGamification.syncAndGetSummary()).xp, summary.xp);
    expect(await DBAchievement.countUnlocked(), 5);
  });

  test('Watch exploration and streak require a minute, sum clips and preserve earned streaks', () async {
    final today = DateTime.now();
    for (var day = 0; day < 3; day++) {
      await DBWatchSession.saveSessions([
        WatchSession(id: 'day-$day-a', videoId: 'a', startedAt: today.subtract(Duration(days: day)), duration: const Duration(seconds: 30)),
        WatchSession(id: 'day-$day-b', videoId: 'b', startedAt: today.subtract(Duration(days: day)), duration: Duration(seconds: day == 0 ? 29 : 30)),
      ]);
    }
    var summary = await DBGamification.syncAndGetSummary();
    expect(summary.streakDays, 2);
    expect(summary.stats['explored'], 2);
    expect(summary.stats['watch_minutes'], 2);
    expect(summary.progress.singleWhere((item) => item.key == 'streak_3').isUnlocked, isFalse);
    await DBWatchSession.saveSessions([
      WatchSession(id: 'day-0-b', videoId: 'b', startedAt: today, duration: const Duration(seconds: 30)),
    ]);
    summary = await DBGamification.syncAndGetSummary();
    expect(summary.streakDays, 3);
    expect(summary.progress.singleWhere((item) => item.key == 'streak_3').isUnlocked, isTrue);
    await db.delete('watch_session');
    summary = await DBGamification.syncAndGetSummary();
    expect(summary.streakDays, 0);
    expect(summary.progress.singleWhere((item) => item.key == 'streak_3').isUnlocked, isTrue);
  });

  test('Concurrent first sync awards each milestone once and reports each unlock once', () async {
    await video('a', favorite: true);
    final results = await Future.wait(List.generate(3, (_) => DBGamification.syncAndGetSummary()));
    expect(await DBAchievement.countUnlocked(), 2);
    expect(results.expand((item) => item.newAchievementTitles), hasLength(2));
    expect((await DBGamification.syncAndGetSummary()).xp, 100);
  });

  test('Profile refresh publishes one coherent summary including achievement progress', () async {
    final home = Get.put<HomeController>(_Home());
    await home.refreshProfile();
    expect(home.gamification.value!.xp, 0);
    await video('a', favorite: true);
    await DBWatchSession.saveSessions([
      WatchSession(id: 'watch-a', videoId: 'a', startedAt: DateTime.now(), duration: const Duration(seconds: 60)),
    ]);
    await Future.wait([home.refreshProfile(), home.refreshProfile()]);
    expect(home.profile.value.totalWatchDuration, 60);
    expect(home.totalVideo.value, 1);
    expect(home.streakDays.value, 1);
    expect(home.achievementCount.value, 3);
    expect(home.gamification.value!.xp, 150);
    expect(home.achievementProgress.where((item) => item.isUnlocked).map((item) => item.key).toSet(),
      {'collection_1', 'favorite_1', 'explored_1'});
    expect(home.latestAchievementTitles.first, 'Press Play');
  });

  test('Level progress advances at 500 XP without losing the remainder', () {
    GamificationSummary summary(int xp) => GamificationSummary(streakDays: 0, stats: {}, latestAchievements: [], newAchievementTitles: [],
      progress: [AchievementProgress(key: 'a', title: 'A', description: '', group: 'Collection', currentValue: 1,
        targetValue: 1, isUnlocked: true, unlockedAt: '', xp: xp)]);
    expect([summary(499).level, summary(499).levelXp], [1, 499]);
    expect([summary(500).level, summary(500).levelXp, summary(500).rank], [2, 0, 'Rising Curator']);
    expect([summary(1510).level, summary(1510).levelXp, summary(1510).rank], [4, 10, 'Collection Expert']);
  });

  test('Playlist, favorite and watch revisions publish only after successful writes', () async {
    await video('a');
    final favoriteRevision = DBVideos.revision.value;
    await DBVideos.addToFavorite(Videos(id: 'a'));
    expect(DBVideos.revision.value, favoriteRevision + 1);
    await DBVideos.addToFavorite(Videos(id: 'missing'));
    expect(DBVideos.revision.value, favoriteRevision + 1);
    final playlist = Playlist(name: 'My picks');
    await DBPlaylist.addPlaylist(playlist);
    final playlistRevision = DBPlaylist.revision.value;
    await expectLater(DBPlaylist.addPlaylistItemBulk('missing', [Videos(id: 'a')]), throwsStateError);
    expect(DBPlaylist.revision.value, playlistRevision);
    await DBPlaylist.addPlaylistItemBulk(playlist.id!, [Videos(id: 'a')]);
    expect(DBPlaylist.revision.value, playlistRevision + 1);
    final watchRevision = DBWatchSession.revision.value;
    final session = WatchSession(id: 'a', startedAt: DateTime.now(), duration: const Duration(seconds: 60));
    await DBWatchSession.saveSessions([session]);
    await DBWatchSession.saveSessions([session]);
    expect(DBWatchSession.revision.value, watchRevision + 1);
    await db.delete('profile');
    await expectLater(DBWatchSession.saveSessions([
      WatchSession(id: 'b', startedAt: DateTime.now(), duration: const Duration(seconds: 60)),
    ]), throwsStateError);
    expect(DBWatchSession.revision.value, watchRevision + 1);
  });
}
