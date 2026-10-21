import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_test_database.dart';

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  final rows = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async { values[key] = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sections extends PageHomeController {
  final loaded = <String>[];
  @override
  Future<void> loadSection(String section) async { loaded.add(section); }
  @override
  Future<void> getImageAlbums() async {}
}

Videos video(String id, {List<String> cast = const [], List<String> tags = const []}) => Videos(
  id: id,
  actress: cast.map((name) => VideoActress(nameRomaji: name)).toList(),
  category: tags.map((name) => VideoCategory(category: name)).toList(),
);

void main() {
  test('Oldest uses release dates and excludes videos without a release date', () async {
    final db = await SqliteTestDatabase.open();
    addTearDown(() async { Get.reset(); await db.close(); });
    await db.execute('''CREATE TABLE videos (
      id TEXT, video_code TEXT, release_date TEXT, created_at TEXT, updated_at TEXT, is_deleted INTEGER DEFAULT 0
    )''');
    for (final row in [
      ['oldest', 'ABC-001', '1990-01-01', '2026-10-20', '2026-10-20', 0],
      ['newer', 'ABC-002', '2020-01-01', '2000-01-01', '2000-01-01', 0],
      ['missing', 'ABC-003', null, '1980-01-01', '1980-01-01', 0],
      ['empty', 'ABC-004', '', '1980-01-01', '1980-01-01', 0],
      ['blank', 'ABC-005', '   ', '1980-01-01', '1980-01-01', 0],
      ['deleted', 'ABC-006', '1970-01-01', '1980-01-01', '1980-01-01', 1],
    ]) {
      await db.execute('INSERT INTO videos VALUES (?, ?, ?, ?, ?, ?)', row);
    }
    Get.put<DBService>(_Service()..dbMain = db);
    final home = PageHomeController();
    await home.getListOldest();
    expect(home.listOldest.map((video) => video.id), ['oldest', 'newer']);
  });

  test('Home refresh skips hidden sections and loads them when expanded', () async {
    final pref = _Preferences();
    pref.values[AppPref.homeSecRecommendation] = true;
    Get.put(AppSettingService()..pref = pref);
    AppPref.setHomeOrderList([AppPref.homeSecRecommendation, AppPref.homeSecFavorite]);
    final db = _Database()..rows.add({'total': 10});
    Get.put<DBService>(_Service()..dbMain = db);
    addTearDown(Get.reset);
    final home = _Sections();
    await home.onRefresh();
    expect(home.loaded, [AppPref.homeSecRecommendation]);
    home.loaded.clear();
    await home.toggleSection(AppPref.homeSecFavorite);
    expect(home.loaded, [AppPref.homeSecFavorite]);
    await home.toggleSection(AppPref.homeSecFavorite);
    expect(home.loaded, [AppPref.homeSecFavorite]);
    await home.toggleSection(AppPref.homeSecFavorite);
    expect(home.loaded, [AppPref.homeSecFavorite]);
    await home.onRefresh();
    expect(home.loaded.where((section) => section == AppPref.homeSecFavorite), hasLength(2));
  });

  test('favorites and meaningful recent viewing outweigh opens and short previews', () async {
    final db = _Database();
    Get.put<DBService>(_Service()..dbMain = db);
    addTearDown(Get.reset);
    final now = DateTime.now();
    db.rows.addAll([
      {'id': 'favorite', 'is_favorite': 1, 'view_count': 0},
      {'id': 'recent', 'seconds': 1200, 'last_watched': now.toString()},
      {'id': 'old', 'seconds': 1200, 'last_watched': now.subtract(const Duration(days: 90)).toString()},
      {'id': 'preview', 'view_count': 100, 'seconds': 30, 'last_watched': now.toString()},
      {'id': 'legacy', 'view_count': 100},
    ]);
    final seeds = await DBVideos.getRecommendationSeeds();
    final weights = {for (final seed in seeds) seed.video.id: seed.weight};
    expect(weights.containsKey('preview'), isFalse);
    expect(weights['favorite'], greaterThan(weights['recent']!));
    expect(weights['recent'], greaterThan(weights['old']!));
    expect(weights['recent'], greaterThan(weights['legacy']!));
  });

  test('matches normalized favorites across the candidate pool without rewarding tag stuffing', () {
    final favoriteMatch = video('older-match', cast: [' FAVORITE  Actress '], tags: ['Specific']);
    final other = video('other', cast: ['Other actress']);
    final tagMatch = video('tag-match', tags: ['Specific']);
    final stuffed = video('stuffed', tags: ['Specific', 'Unrelated', 'Another']);
    final candidates = [other, stuffed, tagMatch, ...List.generate(300, (i) => video('$i')), favoriteMatch];
    final ranked = PageHomeController.rankRecommendations(candidates, [
      (video: video('liked', cast: ['favorite actress'], tags: ['specific']), weight: 5.0),
      (video: video('opened', cast: ['other actress']), weight: 0.3),
    ]);
    expect(ranked.first, same(favoriteMatch));
    expect(ranked.indexOf(tagMatch), lessThan(ranked.indexOf(stuffed)));
    expect(ranked.length, 20);
    expect(candidates.first, same(other));
  });

  test('common tags do not beat specific interests and missing metadata stays safe', () {
    final specific = video('specific', tags: ['Common', 'Interest']);
    final common = video('common', tags: ['Common', 'Common']);
    final ranked = PageHomeController.rankRecommendations([common, specific], [
      (video: video('liked', tags: ['Common', 'Interest']), weight: 5.0),
    ]);
    expect(ranked.first, same(specific));
    expect(PageHomeController.rankRecommendations([], []), isEmpty);
    final unknown = Videos(id: 'unknown');
    expect(PageHomeController.rankRecommendations([unknown], []), [unknown]);
  });
}
