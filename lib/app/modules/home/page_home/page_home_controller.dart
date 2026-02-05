import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';

class PageHomeController extends GetxController {
  final listNewRelease = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;
  final listNewAdded = <Videos>[].obs;
  final listRandom = <Videos>[].obs;
  final listNeverWatch = <Videos>[].obs;
  final listOldest = <Videos>[].obs;
  final totalVideo = 0.obs;

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
