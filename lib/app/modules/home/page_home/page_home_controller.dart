import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_collection.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/collection_entity.dart';
import '../../../data/models/videos_entity.dart';

class PageHomeController extends GetxController {
  final listNewRelease = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;
  final listNewAdded = <Videos>[].obs;
  final listRandom = <Videos>[].obs;
  final listNeverWatch = <Videos>[].obs;
  final listOldest = <Videos>[].obs;
  final listCollection = <Collection>[].obs;
  final totalVideo = 0.obs;

  final homeSectionOrder = <String>[].obs;


  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page home ==> onInit called');
    homeSectionOrder.value = AppPref.getHomeOrderList();

    await getListNewRelease();
    await getListMostWatch();
    await getListFavorite();
    await getListNewAdded();
    await getListRandom();
    await getListNeverWatch();
    await getListOldest();
    await getListCollection();

    totalVideo.value = await DBVideos.getCount();
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

  Future<void> getListCollection() async {
    listCollection.clear();
    listCollection.value = await DBCollection.getAll();
    listCollection.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    listCollection.value = listCollection.take(50).toList();
  }

  Future<void> addOrEditCollection({Collection? header}) async {
    final tecName = TextEditingController();
    final tecCover = TextEditingController();

    if (header != null) {
      tecName.text = header.name ?? '';
      tecCover.text = header.cover ?? '';
    }

    ExAlert.adaptive(
      title: Text(header == null ? 'New Collection' : 'Edit Collection', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: VStack([
        CupertinoTextField(
          controller: tecName,
          placeholder: 'Name',
          prefix: Icon(CupertinoIcons.tag, size: 16).pOnly(left: 8),
          style: TextStyle(color: Vx.white, fontSize: 12),
        ).pOnly(bottom: 8),
        CupertinoTextField(
          controller: tecCover,
          placeholder: 'https://xyz.com/cover.jpg',
          prefix: Icon(CupertinoIcons.photo, size: 16).pOnly(left: 8),
          style: TextStyle(fontSize: 12, color: Vx.white),
        ),
      ]),
      actions: [
        if (header != null) ...[
          CupertinoDialogAction(
            child: Text('Delete', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              await DBCollection.delete(header);
              await getListCollection();
              Get.back();
              update();
            },
          ),
        ],
        CupertinoDialogAction(
          child: Text('Submit', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            if (header == null) {
              final header = Collection(name: tecName.text, cover: tecCover.text);
              await DBCollection.add(header);
              await getListCollection();
              Get.back();
            }
            // edit mode
            else {
              header.name = tecName.text;
              header.cover = tecCover.text;
              await DBCollection.update(header);
              await getListCollection();
              Get.back();
            }
            update();
          },
        ),
      ],
    );
  }
}
