import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:video_compress/video_compress.dart';

import '../../../data/database/db_init.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../home_controller.dart';

class PageHomeController extends GetxController {
  final listNewRelease = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;

  final Map<String, Uint8List> _thumbnailCache = {};

  @override
  Future<void> onInit() async {
    await getListNewRelease();
    await getListTop10Watch();
    await getListFavorite();
    super.onInit();
  }

  Future<void> getListNewRelease() async {
    listNewRelease.clear();
    listNewRelease.value = await DBVideos.getAll();
    listNewRelease.sort((a, b) => b.releaseDate!.compareTo(a.releaseDate!));
    listNewRelease.value = listNewRelease.take(10).toList();
  }

  Future<void> getListTop10Watch() async {
    listTop10Watch.clear();
    listTop10Watch.value = await DBVideos.getAll(where: 'view_count != 0');
    listTop10Watch.sort((a, b) => b.viewCount!.compareTo(a.viewCount!));
    listTop10Watch.value = listTop10Watch.take(10).toList();
  }

  Future<void> getListFavorite() async {
    listFavorite.clear();
    listFavorite.value = await DBVideos.getAll(where: 'is_favorite = ?', whereArgs: [1]);
    listFavorite.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    listFavorite.value = listFavorite.take(10).toList();
  }

  void test() {
    Get.find<DBService>().deleteAllData();
    Get.find<HomeController>().onRefreshAllContent();
  }


  // ────────────────────────────────────────────────────────────────
  // ⵌ helper
  // ────────────────────────────────────────────────────────────────
  Future<Uint8List?> getThumbnail(String videopath) async {
    if (_thumbnailCache.containsKey(videopath)) return _thumbnailCache[videopath];
    try {
      final uint8list = await VideoCompress.getByteThumbnail(videopath, quality: 10, position: 10);
      if (uint8list != null) _thumbnailCache[videopath] = uint8list;
      return uint8list;
    } catch (_) {
      return null;
    }
  }
}
