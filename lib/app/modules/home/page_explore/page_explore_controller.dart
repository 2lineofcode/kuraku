import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../../../core/app_logging.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../page_search/page_search_overlay.dart';

class PageExploreController extends GetxController {
  final filterTypeSelected = kActress.obs;
  final filterType = <String>[
    kActress,
    kCategory,
    kPath,
    kSeries,
    kLabel,
    kStudio,
    kDirector,
    kYear,
    kCustom,
  ];

  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearchText = 'Search...'.obs;

  // olist
  final oList = <OListModel>[].obs;
  final oListFiltered = <OListModel>[].obs;
  final oListSelected = OListModel().obs;

  final oListHoveredIndex = (-1).obs;
  final oListSelectedIndex = 0.obs;
  final oListFocusNode = FocusNode();

  // vlist
  final vList = <Videos>[].obs;
  final vListViewMode = kLocal.obs;

  // r18
  final r18TotalVideo = 0.obs;
  final r18ListVideo = <Map<String, dynamic>>[].obs;


  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page explore ==> onInit called');

    await onFilterByChange(kActress);
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

  void onOListMoveSelectionUp() {
    if (oListSelectedIndex.value > 0) {
      oListSelectedIndex.value--;
      oListSelected.value = oListFiltered[oListSelectedIndex.value];

      oListFocusNode.requestFocus();
      onOListTap(oListSelected.value);
    }
  }

  void onOListMoveSelectionDown() {
    if (oListSelectedIndex.value < oListFiltered.length - 1) {
      oListSelectedIndex.value++;
      oListSelected.value = oListFiltered[oListSelectedIndex.value];

      oListFocusNode.requestFocus();
      onOListTap(oListSelected.value);
    }
  }

  Future<void> onOListTap(OListModel item) async {
    oListSelected.value = item;
    vListViewMode.value = kLocal;

    oListSelectedIndex.value = oListFiltered.indexOf(item);
    oListFocusNode.requestFocus();
    switch (filterTypeSelected.value) {
      case kActress:
        vList.value = await DBVideos.getAllLike('actress', item.id.toString());
        r18TotalVideo.value = await DBR18.getCountAllVideosByActress(item.id!);
        break;
      case kCategory:
        vList.value = await DBVideos.getAllLike('category', item.name!, jsonObject: 'category');
        r18TotalVideo.value = await DBR18.getCountAllVideosByCategory(HelperDecensor.censored(item.name));
        break;
      case kPath:
        vList.value = await DBVideos.getAllVideoPath('video_path', item.name!);
        r18TotalVideo.value = 0;
        break;
      case kLabel:
        vList.value = await DBVideos.getAll(where: 'label = ?', whereArgs: [item.name]);
        r18TotalVideo.value = await DBR18.getCountAllVideosByLabel(item.name!);
        break;
      case kSeries:
        vList.value = await DBVideos.getAll(where: 'series = ?', whereArgs: [item.name]);
        r18TotalVideo.value = await DBR18.getCountAllVideosBySeries(HelperDecensor.censored(item.name!.trim()));
        break;
      case kStudio:
        vList.value = await DBVideos.getAll(where: 'studio = ?', whereArgs: [item.name]);
        r18TotalVideo.value = await DBR18.getCountAllVideosByStudio(item.name!.trim());
        break;
      case kDirector:
        vList.value = await DBVideos.getAll(where: 'director = ?', whereArgs: [item.name]);
        r18TotalVideo.value = await DBR18.getCountAllVideosByDirector(item.name!.trim());
        break;
      case kYear:
        vList.value = await DBVideos.getAllLike('release_date', item.name ?? '');
        r18TotalVideo.value = await DBR18.getCountAllVideosByYear(item.name!.trim());
        break;
      case kCustom:
        if (oListSelected.value.name == 'New Release') {
          vList.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
        } else if (oListSelected.value.name == 'Favorite') {
          vList.value = await DBVideos.getAll(where: 'is_favorite = 1', orderBy: 'updated_at DESC');
        } else if (oListSelected.value.name == 'Non Jav') {
          vList.value = await DBVideos.getAll(where: 'video_code IS NULL OR video_code = ""', orderBy: 'updated_at DESC', limit: 50);
        } else if (oListSelected.value.name == 'Most Watch') {
          vList.value = await DBVideos.getAll(where: 'view_count != 0', orderBy: 'view_count DESC, updated_at DESC', limit: 50);
        } else if (oListSelected.value.name == 'New Added') {
          vList.value = await DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
        } else if (oListSelected.value.name == 'Never Watch') {
          vList.value = await DBVideos.getAll(where: 'view_count = 0', limit: 50, orderBy: 'RANDOM()');
        }
        r18TotalVideo.value = 0;
        break;
    }
  }

  Future<void> onVListTap(Videos item) async {
    await PageSearchOverlay.onItemTap(item);
  }

  Future<void> onHeaderLocalTap() async => vListViewMode.value = 'Local';

  Future<void> onHeaderR18Tap() async {
    if (r18TotalVideo.value == 0) return;
    vListViewMode.value = kR18;
    switch (filterTypeSelected.value) {
      case kActress: r18ListVideo.value = await DBR18.getAllVideosByActress(oListSelected.value.id ?? 0); break;
      case kCategory: r18ListVideo.value = await DBR18.getAllVideosByCategory(HelperDecensor.censored(oListSelected.value.name)); break;
      case kPath: break;
      case kLabel: r18ListVideo.value = await DBR18.getAllVideosByLabel(oListSelected.value.name ?? ''); break;
      case kSeries: r18ListVideo.value = await DBR18.getAllVideosBySeries(HelperDecensor.censored(oListSelected.value.name)); break;
      case kStudio: r18ListVideo.value = await DBR18.getAllVideosByStudio(oListSelected.value.name ?? ''); break;
      case kDirector: r18ListVideo.value = await DBR18.getAllVideosByDirector(oListSelected.value.name ?? ''); break;
      case kYear: r18ListVideo.value = await DBR18.getAllVideosByYear(oListSelected.value.name ?? ''); break;
      case kCustom: break;
    }

    // sort
    r18ListVideo.value = r18ListVideo.value.take(10000).toList();
    final r18ValidList = <Map<String, dynamic>>[].obs;
    for (int i = 0; i < r18ListVideo.length; i++) {
      final vcode = HelperMisc.getVideoCode(r18ListVideo[i]['video_code'] ?? '');
      if (vcode.isNotEmpty && HelperMisc.isValidVideoCode(r18ListVideo[i]['video_code'] ?? '')) {
        r18ValidList.add(r18ListVideo[i]);
      }
    }

    // r18TotalVideo.value = r18ValidList.length;
    r18ListVideo.value = r18ValidList.value.take(100000).toList();
    r18ListVideo.value.unique((item) => item['video_code']);
    r18TotalVideo.value = r18ListVideo.length;

    r18ListVideo.value.sort((a, b) => b['release_date'].compareTo(a['release_date']));

    // check has match video by code
    r18ListVideo.assignAll(r18ListVideo.map((r18Item) {
      final Map<String, dynamic> mutableR18Item = Map.from(r18Item);
      final hasMatch = vList.any((vItem) => r18Item['video_code'].toString() == (vItem.videoCode!));
      mutableR18Item['match'] = hasMatch;
      mutableR18Item['is_clicked'] = false;

      final releaseDate = DateTime.parse(r18Item['release_date'] ?? '');
      mutableR18Item['is_released'] = releaseDate.isBefore(DateTime.now());
      return mutableR18Item;
    }).toList());

    r18ListVideo.refresh();
  }

  Future<void> onFilterByChange(String s) async {
    oList.clear(); vList.clear();
    filterTypeSelected.value = s;
    switch (filterTypeSelected.value) {
      case kActress: await getActressList(); break;
      case kCategory: await getCategoryList(); break;
      case kPath: await getPathList(); break;
      case kLabel: await getLabelList(); break;
      case kSeries: await getSeriesList(); break;
      case kStudio: await getStudioList(); break;
      case kDirector: await getDirectorList(); break;
      case kYear: await getYearList(); break;
      case kCustom: await getCustomList(); break;

    }
    await 10.milliseconds.delay();
    phSearchText.value = 'Search (${oList.length})...';
    tecSearch.text = '';
    vListViewMode.value = 'Local';
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

  Future<void> getCustomList() async {
    final cNewRelease = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
    final cFavorite = await DBVideos.getAll(where: 'is_favorite = 1', orderBy: 'updated_at DESC');
    final cNewAdded = await DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
    final cMostWatch = await DBVideos.getAll(where: 'view_count != 0', orderBy: 'view_count DESC, updated_at DESC', limit: 50);
    final cNeverWatch = await DBVideos.getAll(where: 'view_count = 0', orderBy: 'updated_at DESC', limit: 50);
    final cNonJav = await DBVideos.getAll(where: 'video_code IS NULL OR video_code = ""', orderBy: 'updated_at DESC', limit: 50);

    oList.clear();
    oList.add(OListModel(name: 'New Release', count: cNewRelease.length));
    oList.add(OListModel(name: 'Favorite', count: cFavorite.length));
    oList.add(OListModel(name: 'Non Jav', count: cNonJav.length));
    oList.add(OListModel(name: 'Most Watch', count: cMostWatch.length));
    oList.add(OListModel(name: 'New Added', count: cNewAdded.length));
    oList.add(OListModel(name: 'Never Watch', count: cNeverWatch.length));
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

// filter type
const kActress = 'Actress';
const kCategory = 'Category';
const kPath = 'Path';
const kLabel = 'Label';
const kSeries = 'Series';
const kStudio = 'Studio';
const kDirector = 'Director';
const kYear = 'Year';
const kCustom = 'Custom';

// viewMode
const kLocal = 'Local';
const kR18 = 'R18';