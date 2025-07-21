
import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';

import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';

class PageHomeController extends GetxController {
  final listNewRelease = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    logS('page home ==> onInit called');
    await getListNewRelease();
    await getListTop10Watch();
    await getListFavorite();
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


}
