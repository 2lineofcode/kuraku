
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../page_search/page_search_overlay.dart';

class PageExploreController extends GetxController {
  final filterTypeSelected = 'Actress'.obs;
  final filterType = <String>[
    'Actress',
    'Category',
    'Path',
    'Label',
    'Series',
    'Studio',
    'Director',
    'Year',
  ];

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
    logS('page explore ==> onInit called');
    await onFilterByChange('Actress');
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

  Future<void> onOListTap(OListModel item) async {
    oListSelected.value = item;
    switch (filterTypeSelected.value) {
      case 'Actress': vList.value = await DBVideos.getAllLike('actress', item.name ?? ''); break;
      case 'Category': vList.value = await DBVideos.getAllLike('category', item.name ?? ''); break;
      case 'Path': vList.value = await DBVideos.getAllVideoPath('video_path', item.name ?? ''); break;
      case 'Label': vList.value = await DBVideos.getAll(where: 'label = ?', whereArgs: [item.name]); break;
      case 'Series': vList.value = await DBVideos.getAll(where: 'series = ?', whereArgs: [item.name]); break;
      case 'Studio': vList.value = await DBVideos.getAll(where: 'studio = ?', whereArgs: [item.name]); break;
      case 'Director': vList.value = await DBVideos.getAll(where: 'director = ?', whereArgs: [item.name]); break;
      case 'Year': vList.value = await DBVideos.getAllLike('release_date', item.name ?? ''); break;
    }
    
  }

  Future<void> onVListTap(Videos item) async {
    await PageSearchOverlay.onItemTap(item);
  }

  Future<void> onFilterByChange(String s) async {
    oList.clear(); vList.clear();
    filterTypeSelected.value = s;
    switch (s) {
      case 'Actress': await getActressList(); break;
      case 'Category': await getCategoryList(); break;
      case 'Path': await getPathList(); break;
      case 'Label': await getLabelList(); break;
      case 'Series': await getSeriesList(); break;
      case 'Studio': await getStudioList(); break;
      case 'Director': await getDirectorList(); break;
      case 'Year': await getYearList(); break;
    }
    await 10.milliseconds.delay();
    phSearchText.value = 'Search (${oList.length})...';
    tecSearch.text = '';
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getActressList() async {
    oList.clear();
    final items = await DBVideos.getAllActressWithCount();

    for (var item in items) {
      final id = item['id'];
      final nameRomaji = item['nameRomaji'];
      final nameKana = item['nameKana'];
      final imageUrl = item['imageUrl'];
      final count = item['count'] as int;

      if (id != null) {
        oList.add(OListModel(
          id: id,
          name: nameRomaji != null && nameRomaji.isNotEmpty ? nameRomaji : nameKana,
          imgUrl: imageUrl,
          count: count,
        ));
      }
    }
    oListFiltered.assignAll(oList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getCategoryList() async {
    oList.clear();
    final items = await DBVideos.getAllCategoryWithCount();

    for (var item in items) {
      final num? id = item['id'];
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        oList.add(OListModel(id: id, name: name, count: count));
      }
    }
    oListFiltered.assignAll(oList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getPathList() async {
    oList.clear();
    final directoryData = await DBVideos.getAllPathWithCount();

    for (var item in directoryData) {
      oList.add(OListModel(
        name: item['name'],
        count: item['count'],
      ));
    }
    oListFiltered.assignAll(oList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getLabelList() async {
    oList.clear();
    final items = await DBVideos.getAllLabelWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        oList.add(OListModel(id: id, name: name, count: count));
      }
    }
    oListFiltered.assignAll(oList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getSeriesList() async {
    oList.clear();
    final items = await DBVideos.getAllSeriesWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        oList.add(OListModel(id: id, name: name, count: count));
      }
    }
    oListFiltered.assignAll(oList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getStudioList() async {
    oList.clear();
    final items = await DBVideos.getAllStudioWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        oList.add(OListModel(id: id, name: name, count: count));
      }
    }
    oListFiltered.assignAll(oList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getDirectorList() async {
    oList.clear();
    final items = await DBVideos.getAllDirectorWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        oList.add(OListModel(id: id, name: name, count: count));
      }
    }
    oListFiltered.assignAll(oList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getYearList() async {
    oList.clear();
    final items = await DBVideos.getAllReleaseYearWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        oList.add(OListModel(id: id, name: name, count: count));
      }
    }
    oListFiltered.assignAll(oList);
  }

}

// ────────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────────
class OListModel {
  dynamic id;
  String? name;
  String? imgUrl;
  int? count;

  OListModel({this.id, this.name, this.imgUrl, this.count});
}
