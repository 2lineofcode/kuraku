import 'dart:typed_data';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:video_compress/video_compress.dart';

import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';

class PageExploreController extends GetxController {
  final filterType = <String>[
    'Actress',
    'Category',
    'Path',
    'Label',
    'Series',
    'Studio',
    'Director',
  ];

  final Map<String, Uint8List> _thumbnailCache = {};

  final filterTypeSelected = 'Actress'.obs;
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearchText = 'Search...'.obs;

  final oList = <OListModel>[].obs;
  final oListFiltered = <OListModel>[].obs;
  final oListSelected = OListModel().obs;
  final vList = <Videos>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    await onFilterByChange(0);
    await 10.milliseconds.delay();
    phSearchText.value = 'Search (${oList.length})...';
  }

  void onOListSearch(String s) {
    final query = s.toLowerCase();
    if (query.isEmpty) {
      oListFiltered.assignAll(oList);
    } else {
      final result = oList.where((item) => item.name!.toLowerCase().contains(query)).toList();
      oListFiltered.assignAll(result);
    }
  }

  void onOListTap(OListModel item) {
    oListSelected.value = item;
    vList.value = item.videos ?? [];
  }

  void onVListTap() {}

  Future<void> onFilterByChange(int idx) async {
    vList.clear();
    filterTypeSelected.value = filterType[idx];
    switch (filterType[idx]) {
      case 'Actress':
        await getActressList();
        break;
      case 'Category':
        await getCategoryList();
        break;
      case 'Path':
        await getPathList();
        break;
      case 'Label':
        await getLabelList();
        break;
      case 'Series':
        await getSeriesList();
        break;
      case 'Studio':
        await getStudioList();
        break;
      case 'Director':
        await getDirectorList();
        break;
    }
    await 10.milliseconds.delay();
    phSearchText.value = 'Search (${oList.length})...';
    tecSearch.text = '';
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getActressList() async {
    oList.clear();
    await DBVideos.getAllActress().then((actress) async {
      for (var i = 0; i < actress.length; i++) {
        await DBVideos.getVideoByActress(actress[i].id ?? 0).then((v) {
          oList.add(OListModel(
            id: actress[i].id,
            name: actress[i].nameRomaji != '' ? actress[i].nameRomaji : KanaKit().toRomaji(actress[i].nameKana ?? ''),
            imgUrl: actress[i].imageUrl,
            videos: v,
          ));
        });
      }
      oListFiltered.assignAll(oList);
    });
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getCategoryList() async {
    oList.clear();
    await DBVideos.getAllCategories().then((category) async {
      for (var i = 0; i < category.length; i++) {
        await DBVideos.getVideoByCategories(category[i].id ?? 0).then((v) {
          oList.add(OListModel(id: category[i].id, name: category[i].category, imgUrl: null, videos: v));
        });
      }
      oListFiltered.assignAll(oList);
    });
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getPathList() async {
    oList.clear();
    await DBVideos.getAllVideoPath().then((videoPath) async {
      for (var i = 0; i < videoPath.length; i++) {
        await DBVideos.getVideoByVideoPath(videoPath[i]).then((v) {
          oList.add(OListModel(id: i, name: videoPath[i], imgUrl: null, videos: v));
        });
      }
      oListFiltered.assignAll(oList);
    });
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getLabelList() async {
    oList.clear();
    await DBVideos.getAllLabel().then((label) async {
      for (var i = 0; i < label.length; i++) {
        await DBVideos.getVideoByLabel(label[i]).then((v) {
          oList.add(OListModel(id: i, name: label[i], imgUrl: null, videos: v));
        });
      }
      oListFiltered.assignAll(oList);
    });
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getSeriesList() async {
    oList.clear();
    await DBVideos.getAllSeries().then((series) async {
      for (var i = 0; i < series.length; i++) {
        await DBVideos.getVideoBySeries(series[i]).then((v) {
          oList.add(OListModel(id: i, name: series[i], imgUrl: null, videos: v));
        });
      }
      oListFiltered.assignAll(oList);
    });
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getStudioList() async {
    oList.clear();
    await DBVideos.getAllStudio().then((studio) async {
      for (var i = 0; i < studio.length; i++) {
        await DBVideos.getVideoByStudio(studio[i]).then((v) {
          oList.add(OListModel(id: i, name: studio[i], imgUrl: null, videos: v));
        });
      }
      oListFiltered.assignAll(oList);
    });
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getDirectorList() async {
    oList.clear();
    await DBVideos.getAllDirector().then((director) async {
      for (var i = 0; i < director.length; i++) {
        await DBVideos.getVideoByDirector(director[i]).then((v) {
          oList.add(OListModel(id: i, name: director[i], imgUrl: null, videos: v));
        });
      }
      oListFiltered.assignAll(oList);
    });
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

// ────────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────────
class OListModel {
  num? id;
  String? name;
  String? imgUrl;
  List<Videos>? videos;

  OListModel({this.id, this.name, this.imgUrl, this.videos});
}
