import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../data/database/db_playlist.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/playlist_entity.dart';
import '../../../data/models/videos_entity.dart';

class PageHomeController extends GetxController {
  final listNewRelease = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;
  final listNewAdded = <Videos>[].obs;
  final listRandom = <Videos>[].obs;
  final listNeverWatch = <Videos>[].obs;
  final listOldest = <Videos>[].obs;
  final listPlaylistHeader = <PlaylistHeader>[].obs;
  final totalVideo = 0.obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page home ==> onInit called');
    await getListNewRelease();
    await getListMostWatch();
    await getListFavorite();
    await getListNewAdded();
    await getListRandom();
    await getListNeverWatch();
    await getListOldest();
    await getListPlaylistHeader();

    totalVideo.value = await DBVideos.getCount();
  }

  Future<void> getListNewRelease() async {
    listNewRelease.clear();
    listNewRelease.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
  }

  Future<void> getListMostWatch() async {
    listTop10Watch.clear();
    listTop10Watch.value = await DBVideos.getAll(where: 'view_count != 0', orderBy: 'view_count DESC, updated_at DESC', limit: 50);
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
    listOldest.value = await DBVideos.getAll(limit: 50, orderBy: 'created_at ASC');
  }

  Future<void> getListPlaylistHeader() async {
    listPlaylistHeader.clear();
    listPlaylistHeader.value = await DBPlaylist.getAllHeader();
    listPlaylistHeader.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    listPlaylistHeader.value = listPlaylistHeader.take(50).toList();
  }

  Future<void> addOrEditPlaylist({PlaylistHeader? header}) async {
    final tecName = TextEditingController();
    final tecCover = TextEditingController();

    if (header != null) {
      tecName.text = header.name ?? '';
      tecCover.text = header.cover ?? '';
    }

    ExAlert.adaptive(
      title: Text(header == null ? 'New Playlist' : 'Edit Playlist', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: VStack([
        CupertinoTextField(
          controller: tecName,
          style: TextStyle(color: Vx.white, fontSize: 12),
          placeholder: 'Name',
        ).pOnly(bottom: 8),
        CupertinoTextField(
          readOnly: true,
          controller: tecCover,
          placeholder: 'Cover',
          placeholderStyle: TextStyle(fontSize: 12, color: Vx.neutral500),
          prefix: Icon(CupertinoIcons.photo, size: 16).pOnly(left: 8),
          style: TextStyle(fontSize: 12, color: Vx.neutral500),
          onTap: () async {
            //
          },
        ),
      ]),
      actions: [
        if (header != null) ...[
          CupertinoDialogAction(
            child: Text('Delete', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              await DBPlaylist.deleteHeader(header);
              await getListPlaylistHeader();
              Get.back();
            },
          ),
        ],
        CupertinoDialogAction(
          child: Text('Submit', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            if (header == null) {
              final header = PlaylistHeader(name: tecName.text, cover: tecCover.text);
              await DBPlaylist.addHeader(header);
              await getListPlaylistHeader();
              Get.back();
            }
            // edit mode
            else {
              header.name = tecName.text;
              header.cover = tecCover.text;
              await DBPlaylist.updateHeader(header);
              await getListPlaylistHeader();
              Get.back();
            }
          },
        ),
      ],
    );
  }
}
