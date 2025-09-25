import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../../../core/app_logging.dart';
import '../../../data/api/api_javit.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../page_search/page_search_overlay.dart';

class PageExploreController extends GetxController {
  // ** part: [top] Menu
  final menus = <String>[kActress, kCategory, kPath, kSeries, kLabel, kStudio, kDirector, kYear, kCustom];
  final currentMenuSelected = kActress.obs;

  // ** part: [left] List & Search
  final tecSearchLeft = TextEditingController();
  final fnSearchLeft = FocusNode();
  final phSearchLeft = 'Search...'.obs;

  final leftList = <LeftListModel>[].obs;
  final leftListFiltered = <LeftListModel>[].obs;
  final leftListSelected = LeftListModel().obs;
  final leftListHoveredIndex = (-1).obs;
  final leftListSelectedIndex = 0.obs;
  final leftListFocusNode = FocusNode();

  // ** part: [right] Videos
  final rightListViewMode = kLocal.obs;
  final rightListLocal = <Videos>[].obs;
  final rightListR18 = <Map<String, dynamic>>[].obs;
  final rightListR18Filtered = <Map<String, dynamic>>[].obs;
  final rightListR18TotalVideo = 0.obs;
  final tecSearchRight = TextEditingController();
  final fnSearchRight = FocusNode();
  final phSearchRight = 'Search...'.obs;

  final isFresh = true.obs;


  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page explore ==> onInit called');
    await onMenuChange(kActress);
    phSearchLeft.value = 'Search (${leftList.length})...';
    isFresh.value = await DBVideos.getCount() == 0;
  }

  Future<void> onMenuChange(String menu) async {
    leftList.clear();
    rightListLocal.clear();
    rightListR18.clear();
    currentMenuSelected.value = menu;

    switch (currentMenuSelected.value) {
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

    phSearchLeft.value = 'Search (${leftList.length})...';
    tecSearchLeft.text = '';
    rightListViewMode.value = kLocal;
  }


  // ────────────────────────────────────────────────────────────────
  // ** ⵌ [LEFT PART]
  // ────────────────────────────────────────────────────────────────
  void onLeftListDoSearch(String q) {
    final query = q.toLowerCase();
    if (query.isEmpty) {
      leftListFiltered.assignAll(leftList);
    } else {
      final result = leftList.where((item) => item.name!.toLowerCase().contains(query)).toList();
      leftListFiltered.assignAll(result);
    }
  }

  void onLeftListKeyPressedArrowUp() {
    if (leftListSelectedIndex.value > 0) {
      leftListSelectedIndex.value--;
      leftListSelected.value = leftListFiltered[leftListSelectedIndex.value];
      onLeftListTap(leftListSelected.value);
      leftListFocusNode.requestFocus();
    }
  }

  void onLeftListKeyPressedArrowDown() {
    if (leftListSelectedIndex.value < leftListFiltered.length - 1) {
      leftListSelectedIndex.value++;
      leftListSelected.value = leftListFiltered[leftListSelectedIndex.value];
      onLeftListTap(leftListSelected.value);
      leftListFocusNode.requestFocus();
    }
  }

  Future<void> onLeftListTap(LeftListModel item) async {
    leftListSelected.value = item;
    rightListViewMode.value = kLocal;
    leftListSelectedIndex.value = leftListFiltered.indexOf(item);
    leftListFocusNode.requestFocus();

    switch (currentMenuSelected.value) {
      case kActress:
        rightListLocal.value = await DBVideos.getAllLike('actress', item.id.toString());
        rightListR18TotalVideo.value = await DBR18.getCountAllVideosByActress(item.id!);
        break;
      case kCategory:
        rightListLocal.value = await DBVideos.getAllLike('category', item.name!, jsonObject: 'category');
        rightListR18TotalVideo.value = await DBR18.getCountAllVideosByCategory(HelperDecensor.censored(item.name));
        break;
      case kPath:
        rightListLocal.value = await DBVideos.getAllVideoPath('video_path', item.name!);
        rightListR18TotalVideo.value = 0;
        break;
      case kLabel:
        rightListLocal.value = await DBVideos.getAll(where: 'label = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        rightListR18TotalVideo.value = await DBR18.getCountAllVideosByLabel(item.name!);
        break;
      case kSeries:
        rightListLocal.value = await DBVideos.getAll(where: 'series = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        rightListR18TotalVideo.value = await DBR18.getCountAllVideosBySeries(HelperDecensor.censored(item.name!.trim()));
        break;
      case kStudio:
        rightListLocal.value = await DBVideos.getAll(where: 'studio = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        rightListR18TotalVideo.value = await DBR18.getCountAllVideosByStudio(item.name!.trim());
        break;
      case kDirector:
        rightListLocal.value = await DBVideos.getAll(where: 'director = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        rightListR18TotalVideo.value = await DBR18.getCountAllVideosByDirector(item.name!.trim());
        break;
      case kYear:
        rightListLocal.value = await DBVideos.getAllLike('release_date', item.name ?? '');
        rightListR18TotalVideo.value = await DBR18.getCountAllVideosByYear(item.name!.trim());
        break;
      case kCustom:
        switch (leftListSelected.value.name) {
          case 'New Release':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
            break;
          case 'Favorite':
            rightListLocal.value = await DBVideos.getAll(where: 'is_favorite = 1', orderBy: 'updated_at DESC');
            break;
          case 'Non Jav':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code IS NULL OR video_code = ""', orderBy: 'updated_at DESC');
            break;
          case 'Most Watch':
            rightListLocal.value = await DBVideos.getAll(where: 'view_count >= 3', orderBy: 'view_count DESC, updated_at DESC');
            break;
          case 'New Added':
            rightListLocal.value = await DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
            break;
          case 'Never Watch':
            rightListLocal.value = await DBVideos.getAll(where: 'view_count = 0', orderBy: 'updated_at DESC');
            break;
          case '🟢 Star Rank':
            await ApiJavit.ranking().then( (res) {
              rightListLocal.value.clear();
              final videos = <Videos>[];
              final result = res['result'] as List;
              for (var item in result) {
                videos.add(Videos(
                  id: item['avatar'].toString().allBetween('actress/', '-t.jpg'),
                  videoCode: item['rank'],
                  title: item['name'],
                  fanArt: item['avatar'],
                ));
              }
              rightListLocal.value = videos;
            });
            break;
        }
        rightListR18TotalVideo.value = 0;
        break;
    }
  }


  // ────────────────────────────────────────────────────────────────
  // ** ⵌ [ RIGHT PART ]
  // ────────────────────────────────────────────────────────────────
  void onRightListDoSearch(String q) {
    final query = q.toLowerCase();
    if (query.isEmpty) {
      rightListR18Filtered.assignAll(rightListR18);
    } else {
      final result = rightListR18.where((item) {
        final code = item['video_code'].toString().toLowerCase();
        final title = item['title'].toString().toLowerCase();
        final releaseDate = item['release_date'].toString().toLowerCase();
        return code.contains(query) || title.contains(query) || releaseDate.contains(query);
      }).toList();
      rightListR18Filtered.assignAll(result);
    }
  }

  Future<void> onRightListTap(Videos item) async {
    await PageSearchOverlay.onItemTap(item);
  }

  Future<void> onSectionLocalTap() async => rightListViewMode.value = kLocal;

  Future<void> onSectionR18Tap() async {
    if (rightListR18TotalVideo.value == 0) return;
    rightListViewMode.value = kR18;

    switch (currentMenuSelected.value) {
      case kActress: rightListR18.value = await DBR18.getAllVideosByActress(leftListSelected.value.id ?? 0); break;
      case kCategory: rightListR18.value = await DBR18.getAllVideosByCategory(HelperDecensor.censored(leftListSelected.value.name)); break;
      case kPath: break;
      case kLabel: rightListR18.value = await DBR18.getAllVideosByLabel(leftListSelected.value.name ?? ''); break;
      case kSeries: rightListR18.value = await DBR18.getAllVideosBySeries(HelperDecensor.censored(leftListSelected.value.name)); break;
      case kStudio: rightListR18.value = await DBR18.getAllVideosByStudio(leftListSelected.value.name ?? ''); break;
      case kDirector: rightListR18.value = await DBR18.getAllVideosByDirector(leftListSelected.value.name ?? ''); break;
      case kYear: rightListR18.value = await DBR18.getAllVideosByYear(leftListSelected.value.name ?? ''); break;
      case kCustom: break;
    }

    // Filter, sort, and match
    rightListR18.value = rightListR18.value.take(10000).toList();
    final _filtered = <Map<String, dynamic>>[].obs;
    for (int i = 0; i < rightListR18.length; i++) {
      final vidCode = rightListR18[i]['video_code'].toString();
      if (vidCode.isValidVideoCode()) {
        _filtered.add(rightListR18[i]);
      }
    }

    rightListR18.value = _filtered.value.take(100000).toList();
    rightListR18.value.unique((item) => item['video_code']);
    rightListR18TotalVideo.value = rightListR18.length;

    rightListR18.value.sort((a, b) => b['release_date'].compareTo(a['release_date']));

    // check has match video by code
    rightListR18.assignAll(rightListR18.map((r18) {
      final Map<String, dynamic> _mutableItem = Map.from(r18);
      final hasMatch = rightListLocal.any((vItem) => r18['video_code'].toString() == (vItem.videoCode!));
      _mutableItem['match'] = hasMatch;
      _mutableItem['is_clicked'] = false;

      final releaseDate = DateTime.parse(r18['release_date'] ?? '');
      _mutableItem['is_released'] = releaseDate.isBefore(DateTime.now());
      return _mutableItem;
    }).toList());

    rightListR18Filtered.assignAll(rightListR18);
    rightListR18.refresh();
  }

  // ────────────────────────────────────────────────────────────────
  // ** ⵌ Data Fetching
  // ────────────────────────────────────────────────────────────────
  Future<void> getActressList() async {
    leftList.clear();
    final items = await DBVideos.getAllActressWithCount();

    for (var item in items) {
      final id = item['id'];
      final nameRomaji = item['nameRomaji'];
      final nameKana = item['nameKana'];
      final imageUrl = item['imageUrl'];
      final count = item['count'] as int;

      if (id != null) {
        leftList.add(LeftListModel(
          id: id,
          name: nameRomaji != null && nameRomaji.isNotEmpty ? nameRomaji : nameKana,
          imgUrl: imageUrl,
          count: count,
        ));
      }
    }
    leftListFiltered.assignAll(leftList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getCategoryList() async {
    leftList.clear();
    final items = await DBVideos.getAllCategoryWithCount();

    for (var item in items) {
      final num? id = item['id'];
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        leftList.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    leftListFiltered.assignAll(leftList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getPathList() async {
    leftList.clear();
    final directoryData = await DBVideos.getAllPathWithCount();

    for (var item in directoryData) {
      leftList.add(LeftListModel(
        name: item['name'],
        count: item['count'],
      ));
    }
    leftListFiltered.assignAll(leftList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getLabelList() async {
    leftList.clear();
    final items = await DBVideos.getAllLabelWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        leftList.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    leftListFiltered.assignAll(leftList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getSeriesList() async {
    leftList.clear();
    final items = await DBVideos.getAllSeriesWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        leftList.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    leftListFiltered.assignAll(leftList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getStudioList() async {
    leftList.clear();
    final items = await DBVideos.getAllStudioWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        leftList.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    leftListFiltered.assignAll(leftList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getDirectorList() async {
    leftList.clear();
    final items = await DBVideos.getAllDirectorWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        leftList.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    leftListFiltered.assignAll(leftList);
  }

  // ────────────────────────────────────────────────────────────────
  Future<void> getYearList() async {
    leftList.clear();
    final items = await DBVideos.getAllReleaseYearWithCount();

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        leftList.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    leftListFiltered.assignAll(leftList);
  }

  Future<void> getCustomList() async {
    final cNewRelease = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
    final cFavorite = await DBVideos.getAll(where: 'is_favorite = 1', orderBy: 'updated_at DESC');
    final cNewAdded = await DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
    final cMostWatch = await DBVideos.getAll(where: 'view_count >= 3', orderBy: 'view_count DESC, updated_at DESC');
    final cNeverWatch = await DBVideos.getAll(where: 'view_count = 0', orderBy: 'updated_at DESC');
    final cNonJav = await DBVideos.getAll(where: 'video_code IS NULL OR video_code = ""', orderBy: 'updated_at DESC');

    leftList.clear();
    leftList.add(LeftListModel(name: 'New Release', count: cNewRelease.length));
    leftList.add(LeftListModel(name: 'Favorite', count: cFavorite.length));
    leftList.add(LeftListModel(name: 'Non Jav', count: cNonJav.length));
    leftList.add(LeftListModel(name: 'Most Watch', count: cMostWatch.length));
    leftList.add(LeftListModel(name: 'New Added', count: cNewAdded.length));
    leftList.add(LeftListModel(name: 'Never Watch', count: cNeverWatch.length));
    leftList.add(LeftListModel(name: '🟢 Star Rank', count: 0));
    leftListFiltered.assignAll(leftList);
  }

}

// ────────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────────
class LeftListModel {
  dynamic id;
  String? name;
  String? imgUrl;
  int? count;
  LeftListModel({this.id, this.name, this.imgUrl, this.count});
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

// view mode
const kLocal = 'Local';
const kR18 = 'R18';
