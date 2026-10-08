import 'dart:math' as math;

import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../local_video_selection.dart';

class PageHomeController extends GetxController with LocalVideoSelection {
  final listNewRelease = <Videos>[].obs;
  final listRecommendation = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;
  final listNewAdded = <Videos>[].obs;
  final listRandom = <Videos>[].obs;
  final listNeverWatch = <Videos>[].obs;
  final listOldest = <Videos>[].obs;
  final totalVideo = 0.obs;
  int _recommendationRequest = 0;

  int _selectionRevision = 0;
  Worker? _selectionWorker;
  @override
  int get selectionRevision => _selectionRevision;
  @override
  Iterable<Videos> get selectionSource sync* {
    final sections = {
      AppPref.homeSecNewRelease: listNewRelease,
      AppPref.homeSecRecommendation: listRecommendation,
      AppPref.homeSecMostWatch: listTop10Watch,
      AppPref.homeSecFavorite: listFavorite,
      AppPref.homeSecNewAdd: listNewAdded,
      AppPref.homeSecRandom: listRandom,
      AppPref.homeSecNeverWatch: listNeverWatch,
      AppPref.homeSecOldest: listOldest,
    };
    for (final section in homeSectionOrder) {
      if (AppPref.getBool(section)) yield* sections[section] ?? <Videos>[];
    }
  }
  @override
  Future<void> refreshSelectionFiles() => onRefresh();

  void clearVideoSelection() {
    _selectionRevision++;
    selectedVideos.clear();
  }

  @override
  void onClose() {
    _selectionWorker?.dispose();
    clearVideoSelection();
    super.onClose();
  }

  final homeSectionOrder = <String>[].obs;


  @override
  Future<void> onInit() async {
    _selectionWorker = everAll([listNewRelease, listRecommendation, listTop10Watch, listFavorite, listNewAdded, listRandom, listNeverWatch, listOldest], (_) => clearVideoSelection());
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    clearVideoSelection();
    final sw = Stopwatch()..start();

    homeSectionOrder.value = AppPref.getHomeOrderList();
    final count = DBVideos.getCount();
    await Future.wait([
      getListNewRelease(),
      getListRecommendation(),
      getListMostWatch(),
      getListFavorite(),
      getListNewAdded(),
      getListRandom(),
      getListNeverWatch(),
      getListOldest(),
    ]);
    totalVideo.value = await count;

    AppLog.logI('page home ==> onInit called: ${sw.elapsedMilliseconds} ms');
  }

  Future<void> getListNewRelease() async {
    clearVideoSelection();
    listNewRelease.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
  }

  Future<void> getListRecommendation() async {
    clearVideoSelection();
    final request = ++_recommendationRequest;
    final (seeds, candidates) = await (
      DBVideos.getRecommendationSeeds(),
      DBVideos.getAll(where: 'COALESCE(view_count, 0) = 0 AND COALESCE(is_favorite, 0) = 0'),
    ).wait;
    if (isClosed || request != _recommendationRequest) return;
    listRecommendation.value = rankRecommendations(candidates, seeds);
  }

  static List<Videos> rankRecommendations(List<Videos> candidates, List<({Videos video, double weight})> seeds) {
    String normalize(String? value) => (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    Set<String> actresses(Videos video) => (video.actress ?? <VideoActress>[])
        .map((item) => normalize(item.nameRomaji)).where((name) => name.isNotEmpty).toSet();
    Set<String> categories(Videos video) => (video.category ?? <VideoCategory>[])
        .map((item) => normalize(item.category)).where((name) => name.isNotEmpty).toSet();

    final actressWeight = <String, double>{};
    final categoryWeight = <String, double>{};
    for (final seed in seeds) {
      final cast = actresses(seed.video);
      final tags = categories(seed.video);
      for (final name in cast) {
        actressWeight[name] = (actressWeight[name] ?? 0) + seed.weight / cast.length;
      }
      for (final name in tags) {
        categoryWeight[name] = (categoryWeight[name] ?? 0) + seed.weight / tags.length;
      }
    }

    final categoryFrequency = <String, int>{};
    for (final video in candidates) {
      for (final name in categories(video)) {
        categoryFrequency[name] = (categoryFrequency[name] ?? 0) + 1;
      }
    }
    final maxActress = actressWeight.values.fold(0.0, math.max);
    final maxCategory = categoryWeight.values.fold(0.0, math.max);
    final scored = candidates.map((video) {
      final castScore = actresses(video).fold(0.0, (score, name) => math.max(score, actressWeight[name] ?? 0));
      final tags = categories(video);
      final tagScore = tags.fold(0.0, (score, name) => score + (categoryWeight[name] ?? 0)
          * math.log((candidates.length + 1) / (categoryFrequency[name]! + 1)) / math.log(candidates.length + 1));
      final score = (maxActress == 0 ? 0.0 : 3 * castScore / maxActress)
          + (maxCategory == 0 || tags.isEmpty ? 0.0 : tagScore / (maxCategory * tags.length));
      return (video: video, score: score);
    }).toList()..shuffle();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(20).map((item) => item.video).toList();
  }

  Future<void> getListMostWatch() async {
    clearVideoSelection();
    listTop10Watch.value = await DBVideos.getAll(where: 'view_count >= 3', orderBy: 'view_count DESC, updated_at DESC', limit: 50);
  }

  Future<void> getListFavorite() async {
    clearVideoSelection();
    listFavorite.value = await DBVideos.getAll(where: 'is_favorite = 1', orderBy: 'updated_at DESC');
  }

  Future<void> getListNewAdded() async {
    clearVideoSelection();
    listNewAdded.value = await DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
  }

  Future<void> getListRandom() async {
    clearVideoSelection();
    listRandom.value = await DBVideos.getAll(limit: 20, orderBy: 'RANDOM()');
  }

  Future<void> getListNeverWatch() async {
    clearVideoSelection();
    listNeverWatch.value = await DBVideos.getAll(where: 'view_count = 0', limit: 50, orderBy: 'RANDOM()');
  }

  Future<void> getListOldest() async {
    clearVideoSelection();
    listOldest.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date ASC, updated_at ASC', limit: 50);
  }

}
