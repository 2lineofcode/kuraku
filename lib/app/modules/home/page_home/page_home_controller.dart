import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import '../../../data/database/db_playlist.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/playlist_entity.dart';
import '../../../data/models/videos_entity.dart';

class PageHomeController extends GetxController {
  final listNewRelease = <Videos>[].obs;
  final listTop10Watch = <Videos>[].obs;
  final listFavorite = <Videos>[].obs;
  final listRandom = <Videos>[].obs;
  final listPlaylistHeader = <PlaylistHeader>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    logS('page home ==> onInit called');
    await getListNewRelease();
    await getListTop10Watch();
    await getListFavorite();
    await getListRandom();
    await getListPlaylistHeader();
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

  Future<void> getListRandom() async {
    listRandom.clear();
    listRandom.value = await DBVideos.getAll();
    listRandom.shuffle();
    listRandom.value = listRandom.take(10).toList();
  }

  Future<void> getListPlaylistHeader() async {
    listPlaylistHeader.clear();
    listPlaylistHeader.value = await DBPlaylist.getAllHeader();
    listPlaylistHeader.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    listPlaylistHeader.value = listPlaylistHeader.take(10).toList();
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
