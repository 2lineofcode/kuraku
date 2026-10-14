import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/data/database/_init_db.dart';
import 'package:kuraku/app/data/database/db_videos.dart';
import 'package:kuraku/app/data/models/videos_entity.dart';
import 'package:kuraku/app/modules/home/page_home/page_home_controller.dart';
import 'package:sqflite/sqflite.dart';

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

Videos video(String id, {List<String> cast = const [], List<String> tags = const []}) => Videos(
  id: id,
  actress: cast.map((name) => VideoActress(nameRomaji: name)).toList(),
  category: tags.map((name) => VideoCategory(category: name)).toList(),
);

void main() {
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
