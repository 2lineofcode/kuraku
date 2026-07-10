import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';

class PageHomeController extends GetxController {
  final listNewRelease = <Videos>[].obs;
  final listRecommendation = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;
  final listNewAdded = <Videos>[].obs;
  final listRandom = <Videos>[].obs;
  final listNeverWatch = <Videos>[].obs;
  final listOldest = <Videos>[].obs;
  final totalVideo = 0.obs;
  // final recommendationSubtitle = 'Fresh picks from your library'.obs;

  final homeSectionOrder = <String>[].obs;


  @override
  Future<void> onInit() async {
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();

    homeSectionOrder.value = AppPref.getHomeOrderList();
    await getListNewRelease();
    await getListRecommendation();
    await getListMostWatch();
    await getListFavorite();
    await getListNewAdded();
    await getListRandom();
    await getListNeverWatch();
    await getListOldest();
    totalVideo.value = await DBVideos.getCount();

    AppLog.logI('page home ==> onInit called: ${sw.elapsedMilliseconds} ms');
  }

  Future<void> getListNewRelease() async {
    listNewRelease.clear();
    listNewRelease.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
  }

  Future<void> getListRecommendation() async {
    final watched = await DBVideos.getAll(where: 'view_count > 0', orderBy: 'view_count DESC, updated_at DESC', limit: 100);
    final candidates = await DBVideos.getAll(where: 'view_count = 0', orderBy: 'created_at DESC', limit: 300);

    if (candidates.isEmpty) {
      listRecommendation.clear();
      // recommendationSubtitle.value = 'No unwatched videos available';
      return;
    }

    if (watched.isEmpty) {
      candidates.shuffle();
      listRecommendation.value = candidates.take(20).toList();
      // recommendationSubtitle.value = 'Fresh picks from your library';
      return;
    }

    final actressWeight = <String, int>{};
    final categoryWeight = <String, int>{};

    for (final video in watched) {
      final weight = (video.viewCount ?? 1).toInt().clamp(1, 10);
      for (final actress in video.actress ?? <VideoActress>[]) {
        final name = (actress.nameRomaji ?? '').trim();
        if (name.isNotEmpty) actressWeight[name] = (actressWeight[name] ?? 0) + weight;
      }
      for (final category in video.category ?? <VideoCategory>[]) {
        final name = (category.category ?? '').trim();
        if (name.isNotEmpty) categoryWeight[name] = (categoryWeight[name] ?? 0) + weight;
      }
    }

    final scored = candidates.map((video) {
      var score = 0;
      for (final actress in video.actress ?? <VideoActress>[]) {
        score += (actressWeight[(actress.nameRomaji ?? '').trim()] ?? 0) * 3;
      }
      for (final category in video.category ?? <VideoCategory>[]) {
        score += categoryWeight[(category.category ?? '').trim()] ?? 0;
      }
      return (video: video, score: score);
    }).toList();

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (b.video.createdAt ?? '').compareTo(a.video.createdAt ?? '');
    });

    listRecommendation.value = scored.take(20).map((item) => item.video).toList();

    // final topActress = actressWeight.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    // final topCategory = categoryWeight.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    // if (topActress.isNotEmpty) {
    //   recommendationSubtitle.value = 'Because you watched ${topActress.first.key}';
    // } else if (topCategory.isNotEmpty) {
    //   recommendationSubtitle.value = 'Based on ${topCategory.first.key}';
    // } else {
    //   recommendationSubtitle.value = 'Fresh picks from your library';
    // }
  }

  Future<void> getListMostWatch() async {
    listTop10Watch.clear();
    listTop10Watch.value = await DBVideos.getAll(where: 'view_count >= 3', orderBy: 'view_count DESC, updated_at DESC', limit: 50);
  }

  Future<void> getListFavorite() async {
    listFavorite.clear();
    listFavorite.value = await DBVideos.getAll(where: 'is_favorite = 1', orderBy: 'updated_at DESC');
  }

  Future<void> getListNewAdded() async {
    listNewAdded.clear();
    listNewAdded.value = await DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
  }

  Future<void> getListRandom() async {
    listRandom.clear();
    listRandom.value = await DBVideos.getAll(limit: 20, orderBy: 'RANDOM()');
  }

  Future<void> getListNeverWatch() async {
    listNeverWatch.clear();
    listNeverWatch.value = await DBVideos.getAll(where: 'view_count = 0', limit: 50, orderBy: 'RANDOM()');
  }

  Future<void> getListOldest() async {
    listOldest.clear();
    listOldest.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date ASC, updated_at ASC', limit: 50);
  }

}
