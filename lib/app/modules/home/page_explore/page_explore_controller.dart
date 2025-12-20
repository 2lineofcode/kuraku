import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../../../core/app_logging.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../page_search/page_search_overlay.dart';

class PageExploreController extends GetxController {
  final isFresh = true.obs;

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
  final leftSortOptions = <String>['Name', 'Count'];
  final leftSortSelected = 'Name'.obs;

  // ** part: [right] Videos
  final rightListViewMode = kLocal.obs;
  final rightListLocal = <Videos>[].obs;
  final rightListR18 = <Map<String, dynamic>>[].obs;
  final rightListR18Filtered = <Map<String, dynamic>>[].obs;
  final rightListR18TotalVideo = 0.obs;
  final r18ScrollController = ScrollController();
  final hasNextPage = false.obs;
  final currentPage = 0.obs;
  final isLoadingR18 = false.obs;
  final isLoadingR18More = false.obs;
  final tecSearchRight = TextEditingController();
  final fnSearchRight = FocusNode();
  final phSearchRight = 'Search...'.obs;
  final singleActressMode = true.obs;
  final _perPage = 500;

  // filter
  final filter = VideoFilterState();


  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page explore ==> onInit called');
    r18ScrollController.addListener(_onScroll);
    await onMenuChange(kActress);
    phSearchLeft.value = 'Search (${leftList.length})...';
    isFresh.value = await DBVideos.getCount() == 0;
  }

  @override
  void onClose() {
    r18ScrollController.removeListener(_onScroll);
    r18ScrollController.dispose();
    tecSearchLeft.dispose();
    fnSearchLeft.dispose();
    tecSearchRight.dispose();
    fnSearchRight.dispose();
    super.onClose();
  }

  Future<void> onMenuChange(String menu) async {
    leftList.clear();
    rightListLocal.clear();
    rightListR18.clear();
    _resetR18Pagination();
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
    _applyLeftSort();
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
    _applyLeftSort();
  }

  void onLeftSortChange(String value) {
    leftSortSelected.value = value;
    _applyLeftSort();
  }

  void _applyLeftSort() {
    if (leftListFiltered.isEmpty) return;
    if (leftSortSelected.value == 'Count') {
      leftListFiltered.sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
    } else {
      leftListFiltered.sort(
        (a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()),
      );
    }
    _syncLeftSelectionIndex();
    leftListFiltered.refresh();
  }

  void _syncLeftSelectionIndex() {
    final selected = leftListSelected.value;
    if (selected.name == null && selected.id == null) return;
    final index = leftListFiltered.indexWhere(
      (item) => item.name == selected.name && item.id == selected.id,
    );
    if (index >= 0) leftListSelectedIndex.value = index;
  }

  int _getSafeLeftSelectedIndex() {
    if (leftListFiltered.isEmpty) return -1;
    final selected = leftListSelected.value;
    final index = leftListFiltered.indexWhere(
      (item) => item.name == selected.name && item.id == selected.id,
    );
    if (index >= 0) return index;
    final fallback = leftListSelectedIndex.value;
    if (fallback >= 0 && fallback < leftListFiltered.length) return fallback;
    return 0;
  }

  void onLeftListKeyPressedArrowUp() {
    final currentIndex = _getSafeLeftSelectedIndex();
    if (currentIndex > 0) {
      final nextIndex = currentIndex - 1;
      leftListSelectedIndex.value = nextIndex;
      leftListSelected.value = leftListFiltered[nextIndex];
      onLeftListTap(leftListSelected.value);
      leftListFocusNode.requestFocus();
    }
  }

  void onLeftListKeyPressedArrowDown() {
    final currentIndex = _getSafeLeftSelectedIndex();
    if (currentIndex >= 0 && currentIndex < leftListFiltered.length - 1) {
      final nextIndex = currentIndex + 1;
      leftListSelectedIndex.value = nextIndex;
      leftListSelected.value = leftListFiltered[nextIndex];
      onLeftListTap(leftListSelected.value);
      leftListFocusNode.requestFocus();
    }
  }

  Future<void> onLeftListTap(LeftListModel item) async {
    leftListSelected.value = item;
    rightListViewMode.value = kLocal;
    leftListSelectedIndex.value = leftListFiltered.indexOf(item);
    leftListFocusNode.requestFocus();
    _resetR18Pagination();

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
          case 'Most Watch':
            rightListLocal.value = await DBVideos.getAll(where: 'view_count >= 3', orderBy: 'view_count DESC, updated_at DESC');
            break;
          case 'New Added':
            rightListLocal.value = await DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
            break;
          case 'Never Watch':
            rightListLocal.value = await DBVideos.getAll(where: 'view_count = 0', orderBy: 'updated_at DESC');
            break;
          case '🇮🇩 Sub Indonesia':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-id%" OR video_path LIKE "%indo%")', orderBy: 'updated_at DESC');
            break;
          case '🇬🇧 Sub English':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-en%" OR video_path LIKE "%-sub%")', orderBy: 'updated_at DESC');
            break;
          case '✨ Reduce Mosaic':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-un%" OR video_path LIKE "%-rm%" OR video_path LIKE "%reducing mosaic%")', orderBy: 'updated_at DESC');
            break;
          case '🚫 Non Jav':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code IS NULL OR video_code = ""', orderBy: 'updated_at DESC');
            break;
          case '💿 FHD':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != "" AND quality = "1920x1080"', orderBy: 'updated_at DESC');
            break;
          case '📺 HD':
            rightListLocal.value = await DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != "" AND quality != "1920x1080"', orderBy: 'updated_at DESC');
            break;
        }
        rightListR18TotalVideo.value = 0;
        break;
    }
  }


  // ────────────────────────────────────────────────────────────────
  // ** ⵌ [ RIGHT PART ]
  // ────────────────────────────────────────────────────────────────
  Future<void> onRightListDoSearch(String q) async {
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

    if (filter.isFiltered.isTrue) await _applyFilter();
  }

  Future<void> onRightListTap(Videos item) async {
    await PageSearchOverlay.onItemTap(item);
  }

  // ~ Filters ────────────────────────────────────────────────────────────────
  final _filterAdapter = VideoFilterAdapter<Map<String, dynamic>>(
    videoCode: (video) => video['video_code'] ?? '',
    actresses: (video) => video['actresses'] ?? <String>[],
    categories: (video) => video['categories'] ?? <String>[],
    releaseDate: (video) => video['release_date'] ?? '',
    categoryMatch: (videoCategories, selected) => videoCategories.toSet().containsAll(selected),
  );

  Future<void> _applyFilter() async {
    final filtered = filter.apply(rightListR18.toList(), _filterAdapter);
    rightListR18Filtered.value = filtered;
  }

  Future<void> openDialogFilter() async {
    await HelperOpener.openFilterDialog<Map<String, dynamic>>(
      state: filter,
      allVideos: rightListR18.toList(),
      videos: rightListR18Filtered,
      adapter: _filterAdapter,
      showActressName: false,
      showCategories: false,
    );
  }

  Future<void> onSectionLocalTap() async => rightListViewMode.value = kLocal;

  Future<void> onSectionR18Tap() async {
    
    if (rightListR18TotalVideo.value == 0) return;
    rightListViewMode.value = kR18;
    currentPage.value = 1;
    hasNextPage.value = true;
    rightListR18.clear();
    rightListR18Filtered.clear();

    isLoadingR18.value = true;
    try {
      await _loadR18Page(isLoadMore: false);
      if (r18ScrollController.hasClients) {
        await r18ScrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
    } finally {
      isLoadingR18.value = false;
    }
  }

  Future<void> _loadR18Page({required bool isLoadMore}) async {
    if (isLoadMore && hasNextPage.isFalse) return;
    if (isLoadMore) isLoadingR18More.value = true;

    try {
      final List<Map<String, dynamic>> r18videos;
      switch (currentMenuSelected.value) {
        case kActress: r18videos = await DBR18.getAllVideosByActress(leftListSelected.value.id ?? 0, singleActressMode: singleActressMode.value, page: currentPage.value, perPage: _perPage + 1); break;
        case kCategory: r18videos = await DBR18.getAllVideosByCategory(HelperDecensor.censored(leftListSelected.value.name), page: currentPage.value, perPage: _perPage + 1); break;
        case kPath: r18videos = []; break;
        case kLabel: r18videos = await DBR18.getAllVideosByLabel(leftListSelected.value.name ?? '', page: currentPage.value, perPage: _perPage + 1); break;
        case kSeries: r18videos = await DBR18.getAllVideosBySeries(HelperDecensor.censored(leftListSelected.value.name), page: currentPage.value, perPage: _perPage + 1); break;
        case kStudio: r18videos = await DBR18.getAllVideosByStudio(leftListSelected.value.name ?? '', page: currentPage.value, perPage: _perPage + 1); break;
        case kDirector: r18videos = await DBR18.getAllVideosByDirector(leftListSelected.value.name ?? '', page: currentPage.value, perPage: _perPage + 1); break;
        case kYear: r18videos = await DBR18.getAllVideosByYear(leftListSelected.value.name ?? '', page: currentPage.value, perPage: _perPage + 1); break;
        case kCustom: r18videos = []; break;
        default: r18videos = []; break;
      }

      hasNextPage.value = r18videos.length > _perPage;
      final pageItems = r18videos.take(_perPage).toList();

      final output = <Map<String, dynamic>>[];
      for (final item in pageItems) {
        final vidCode = item['video_code'].toString();
        if (vidCode.isValidVideoCode() == false) continue;
        final mutableItem = Map<String, dynamic>.from(item);
        final hasMatch = rightListLocal.any((vItem) => vidCode == (vItem.videoCode ?? ''));
        mutableItem['match'] = hasMatch;
        mutableItem['is_clicked'] = false;

        final releaseDate = DateTime.tryParse(item['release_date'] ?? '');
        mutableItem['is_released'] = releaseDate?.isBefore(DateTime.now()) ?? true;
        output.add(mutableItem);
      }

      if (isLoadMore) {
        rightListR18.addAll(output);
      } else {
        rightListR18.value = output;
      }

      rightListR18.value.unique((item) => item['video_code']);
      await _syncRightFilters();
      rightListR18.refresh();
    } catch (e) {
      AppLog.logE('_loadR18Page e -> $e');
    } finally {
      if (isLoadMore) isLoadingR18More.value = false;
    }
  }

  void _onScroll() {
    if (r18ScrollController.position.pixels >= r18ScrollController.position.maxScrollExtent - 240) {
      if (hasNextPage.isTrue && isLoadingR18More.isFalse && isLoadingR18.isFalse) {
        currentPage.value += 1;
        _loadR18Page(isLoadMore: true);
      }
    }
  }

  void _resetR18Pagination() {
    currentPage.value = 0;
    hasNextPage.value = false;
    isLoadingR18.value = false;
    isLoadingR18More.value = false;
    rightListR18.clear();
    rightListR18Filtered.clear();
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
    final cSubId = await DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-id%" OR video_path LIKE "%indo%")', orderBy: 'updated_at DESC');
    final cSubEn = await DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-en%" OR video_path LIKE "%-sub%")', orderBy: 'updated_at DESC');
    final cRM = await DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-un%" OR video_path LIKE "%-rm%" OR video_path LIKE "%reducing mosaic%")', orderBy: 'updated_at DESC');
    final cHD = await DBVideos.getAll(where: 'video_code != "" AND (quality != "1920x1080")', orderBy: 'updated_at DESC');
    final cFHD = await DBVideos.getAll(where: 'video_code != "" AND (quality = "1920x1080")', orderBy: 'updated_at DESC');


    leftList.clear();
    leftList.add(LeftListModel(name: 'New Release', count: cNewRelease.length));
    leftList.add(LeftListModel(name: 'Favorite', count: cFavorite.length));
    leftList.add(LeftListModel(name: 'Most Watch', count: cMostWatch.length));
    leftList.add(LeftListModel(name: 'New Added', count: cNewAdded.length));
    leftList.add(LeftListModel(name: 'Never Watch', count: cNeverWatch.length));
    leftList.add(LeftListModel(name: '📺 HD', count: cHD.length));
    leftList.add(LeftListModel(name: '💿 FHD', count: cFHD.length));
    leftList.add(LeftListModel(name: '🇮🇩 Sub Indonesia', count: cSubId.length));
    leftList.add(LeftListModel(name: '🇬🇧 Sub English', count: cSubEn.length));
    leftList.add(LeftListModel(name: '✨ Reduce Mosaic', count: cRM.length));
    leftList.add(LeftListModel(name: '🚫 Non Jav', count: cNonJav.length));
    leftListFiltered.assignAll(leftList);
  }

  Future<void> _syncRightFilters() async {
    final query = tecSearchRight.text.toLowerCase();
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

    if (filter.isFiltered.isTrue) await _applyFilter();
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
