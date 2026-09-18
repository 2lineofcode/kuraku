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
import '../home_panel/home_panel_video_info.dart';

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
  int _menuRequest = 0;
  int _selectionRequest = 0;
  int _r18Request = 0;

  // filter
  final filter = VideoFilterState();


  @override
  Future<void> onInit() async {
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();

    r18ScrollController.removeListener(_onScroll);
    r18ScrollController.addListener(_onScroll);
    await onMenuChange(kActress);
    phSearchLeft.value = 'Search (${leftList.length})...';
    isFresh.value = await DBVideos.getCount() == 0;
    
    AppLog.logI('page explore ==> onInit called: ${sw.elapsedMilliseconds} ms');
  }

  @override
  void onClose() {
    _menuRequest++;
    _selectionRequest++;
    _r18Request++;
    r18ScrollController.removeListener(_onScroll);
    r18ScrollController.dispose();
    tecSearchLeft.dispose();
    fnSearchLeft.dispose();
    tecSearchRight.dispose();
    fnSearchRight.dispose();
    super.onClose();
  }

  Future<void> onMenuChange(String menu) async {
    final request = ++_menuRequest;
    _selectionRequest++;
    leftList.clear();
    leftListFiltered.clear();
    rightListLocal.clear();
    _resetR18Pagination();
    currentMenuSelected.value = menu;
    tecSearchLeft.text = '';

    late final List<LeftListModel> items;
    switch (menu) {
      case kActress: items = await getActressList(); break;
      case kCategory: items = await getCategoryList(); break;
      case kPath: items = await getPathList(); break;
      case kLabel: items = await getLabelList(); break;
      case kSeries: items = await getSeriesList(); break;
      case kStudio: items = await getStudioList(); break;
      case kDirector: items = await getDirectorList(); break;
      case kYear: items = await getYearList(); break;
      case kCustom: items = await getCustomList(); break;
      default: items = [];
    }
    if (request != _menuRequest || isClosed) return;

    leftList.assignAll(items);
    phSearchLeft.value = 'Search (${leftList.length})...';
    rightListViewMode.value = kLocal;
    onLeftListDoSearch(tecSearchLeft.text);
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
    final request = ++_selectionRequest;
    final menu = currentMenuSelected.value;
    leftListSelected.value = item;
    rightListViewMode.value = kLocal;
    leftListSelectedIndex.value = leftListFiltered.indexOf(item);
    leftListFocusNode.requestFocus();
    _resetR18Pagination();

    late final Future<List<Videos>> localVideos;
    Future<int> r18Count = Future.value(0);
    switch (menu) {
      case kActress:
        localVideos = DBVideos.getAllLike('actress', item.id.toString());
        r18Count = DBR18.getCountAllVideosByActress(item.id!);
        break;
      case kCategory:
        localVideos = DBVideos.getAllLike('category', item.name!, jsonObject: 'category');
        r18Count = DBR18.getCountAllVideosByCategory(HelperDecensor.censored(item.name));
        break;
      case kPath:
        localVideos = DBVideos.getAllVideoPath('video_path', item.name!);
        break;
      case kLabel:
        localVideos = DBVideos.getAll(where: 'label = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        r18Count = DBR18.getCountAllVideosByLabel(item.name!);
        break;
      case kSeries:
        localVideos = DBVideos.getAll(where: 'series = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        r18Count = DBR18.getCountAllVideosBySeries(HelperDecensor.censored(item.name!.trim()));
        break;
      case kStudio:
        localVideos = DBVideos.getAll(where: 'studio = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        r18Count = DBR18.getCountAllVideosByStudio(item.name!.trim());
        break;
      case kDirector:
        localVideos = DBVideos.getAll(where: 'director = ?', whereArgs: [item.name], orderBy: 'release_date DESC');
        r18Count = DBR18.getCountAllVideosByDirector(item.name!.trim());
        break;
      case kYear:
        localVideos = DBVideos.getAllLike('release_date', item.name ?? '');
        r18Count = DBR18.getCountAllVideosByYear(item.name!.trim());
        break;
      case kCustom:
        localVideos = _getCustomVideos(item.name);
        break;
      default:
        localVideos = Future.value([]);
    }

    final result = await Future.wait<dynamic>([localVideos, r18Count]);
    if (request != _selectionRequest || isClosed) return;
    rightListLocal.assignAll(result[0] as List<Videos>);
    rightListR18TotalVideo.value = result[1] as int;
  }

  Future<List<Videos>> _getCustomVideos(String? name) {
    switch (name) {
      case 'New Release': return DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != ""', orderBy: 'release_date DESC, updated_at DESC', limit: 50);
      case 'Favorite': return DBVideos.getAll(where: 'is_favorite = 1', orderBy: 'updated_at DESC');
      case 'Most Watch': return DBVideos.getAll(where: 'view_count >= 3', orderBy: 'view_count DESC, updated_at DESC');
      case 'New Added': return DBVideos.getAll(orderBy: 'created_at DESC', limit: 50);
      case 'Never Watch': return DBVideos.getAll(where: 'view_count = 0', orderBy: 'updated_at DESC');
      case '🇮🇩 Sub Indonesia': return DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-id%" OR video_path LIKE "%indo%")', orderBy: 'updated_at DESC');
      case '🇬🇧 Sub English': return DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-en%" OR video_path LIKE "%-sub%")', orderBy: 'updated_at DESC');
      case '✨ Reduce Mosaic': return DBVideos.getAll(where: 'video_code != "" AND (video_path LIKE "%-un%" OR video_path LIKE "%-rm%" OR video_path LIKE "%reducing mosaic%")', orderBy: 'updated_at DESC');
      case '🚫 Non Jav': return DBVideos.getAll(where: 'video_code IS NULL OR video_code = ""', orderBy: 'updated_at DESC');
      case '💿 FHD': return DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != "" AND quality = "1920x1080"', orderBy: 'updated_at DESC');
      case '📺 HD': return DBVideos.getAll(where: 'video_code IS NOT NULL AND video_code != "" AND quality != "1920x1080"', orderBy: 'updated_at DESC');
      default: return Future.value([]);
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
    await HomePanelVideoInfo.open(item);
  }

  // ~ Filters ────────────────────────────────────────────────────────────────
  static Iterable<String> _splitCsvField(dynamic value) {
    if (value == null) return const <String>[];
    if (value is Iterable) {
      return value.map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty);
    }
    final raw = '$value'.trim();
    if (raw.isEmpty) return const <String>[];
    return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
  }

  final _filterAdapter = VideoFilterAdapter<Map<String, dynamic>>(
    videoCode: (video) => video['video_code'] ?? '',
    actresses: (video) => _splitCsvField(video['actresses']),
    categories: (video) => _splitCsvField(video['categories']),
    releaseDate: (video) => video['release_date'] ?? '',
    categoryMatch: (videoCategories, selected) => videoCategories.toSet().containsAll(selected),
  );

  Future<void> _applyFilter() async {
    final filtered = filter.apply(rightListR18.toList(), _filterAdapter);
    rightListR18Filtered.value = filtered;
  }

  Future<void> openDialogFilter() async {
    final request = _r18Request;
    final videos = rightListR18.toList();
    final codesWithoutCategories = videos
        .where((video) => _splitCsvField(video['categories']).isEmpty)
        .map((video) => '${video['video_code'] ?? ''}'.trim())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();

    if (codesWithoutCategories.isNotEmpty) {
      final categoriesByCode = await DBR18.getCategoriesByVideoCodes(codesWithoutCategories);
      if (request != _r18Request || isClosed) return;
      if (categoriesByCode.isNotEmpty) {
        for (final video in videos) {
          final code = '${video['video_code'] ?? ''}'.trim();
          final categories = categoriesByCode[code];
          if (categories == null || categories.isEmpty) continue;
          video['categories'] = categories.join(', ');
        }
      }
    }

    final categories = <String>[];
    for (final video in videos) {
      categories.addAll(_splitCsvField(video['categories']));
    }

    if (categories.isNotEmpty) {
      filter.categories
        ..assignAll(categories.toSet().toList()..sort())
        ..refresh();
    }

    await HelperOpener.openFilterDialog<Map<String, dynamic>>(
      state: filter,
      allVideos: videos,
      videos: rightListR18Filtered,
      adapter: _filterAdapter,
      showActressName: false,
      showCategories: true,
    );
  }

  Future<void> onSectionLocalTap() async => rightListViewMode.value = kLocal;

  Future<void> onSectionR18Tap() async {
    if (rightListR18TotalVideo.value == 0) return;
    final request = ++_r18Request;
    rightListViewMode.value = kR18;
    currentPage.value = 1;
    hasNextPage.value = true;
    isLoadingR18More.value = false;
    rightListR18.clear();
    rightListR18Filtered.clear();

    isLoadingR18.value = true;
    try {
      await _loadR18Page(isLoadMore: false, request: request, page: 1);
      if (request == _r18Request && r18ScrollController.hasClients) {
        await r18ScrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
    } finally {
      if (request == _r18Request) isLoadingR18.value = false;
    }
  }

  Future<void> _loadR18Page({required bool isLoadMore, required int request, required int page}) async {
    if (isLoadMore && hasNextPage.isFalse) return;
    if (isLoadMore) isLoadingR18More.value = true;
    final menu = currentMenuSelected.value;
    final selected = leftListSelected.value;
    final isSingleActress = singleActressMode.value;

    try {
      final List<Map<String, dynamic>> r18videos;
      switch (menu) {
        case kActress: r18videos = await DBR18.getAllVideosByActress(selected.id ?? 0, singleActressMode: isSingleActress, page: page, perPage: _perPage + 1); break;
        case kCategory: r18videos = await DBR18.getAllVideosByCategory(HelperDecensor.censored(selected.name), page: page, perPage: _perPage + 1); break;
        case kPath: r18videos = []; break;
        case kLabel: r18videos = await DBR18.getAllVideosByLabel(selected.name ?? '', page: page, perPage: _perPage + 1); break;
        case kSeries: r18videos = await DBR18.getAllVideosBySeries(HelperDecensor.censored(selected.name), page: page, perPage: _perPage + 1); break;
        case kStudio: r18videos = await DBR18.getAllVideosByStudio(selected.name ?? '', page: page, perPage: _perPage + 1); break;
        case kDirector: r18videos = await DBR18.getAllVideosByDirector(selected.name ?? '', page: page, perPage: _perPage + 1); break;
        case kYear: r18videos = await DBR18.getAllVideosByYear(selected.name ?? '', page: page, perPage: _perPage + 1); break;
        case kCustom: r18videos = []; break;
        default: r18videos = []; break;
      }
      if (request != _r18Request || isClosed) return;

      hasNextPage.value = r18videos.length > _perPage;
      currentPage.value = page;
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
      if (isLoadMore && request == _r18Request) isLoadingR18More.value = false;
    }
  }

  void _onScroll() {
    if (r18ScrollController.position.pixels >= r18ScrollController.position.maxScrollExtent - 240) {
      if (hasNextPage.isTrue && isLoadingR18More.isFalse && isLoadingR18.isFalse) {
        _loadR18Page(isLoadMore: true, request: _r18Request, page: currentPage.value + 1);
      }
    }
  }

  void _resetR18Pagination() {
    _r18Request++;
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
  Future<List<LeftListModel>> getActressList() async {
    final items = await DBVideos.getAllActressWithCount();
    final result = <LeftListModel>[];

    for (var item in items) {
      final id = item['id'];
      final nameRomaji = item['nameRomaji'];
      final nameKana = item['nameKana'];
      final imageUrl = item['imageUrl'];
      final count = item['count'] as int;

      if (id != null) {
        result.add(LeftListModel(
          id: id,
          name: nameRomaji != null && nameRomaji.isNotEmpty ? nameRomaji : nameKana,
          imgUrl: imageUrl,
          count: count,
        ));
      }
    }
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  Future<List<LeftListModel>> getCategoryList() async {
    final items = await DBVideos.getAllCategoryWithCount();
    final result = <LeftListModel>[];

    for (var item in items) {
      final num? id = item['id'];
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        result.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  Future<List<LeftListModel>> getPathList() async {
    final directoryData = await DBVideos.getAllPathWithCount();

    return directoryData.map((item) {
      return LeftListModel(
        name: item['name'],
        count: item['count'],
      );
    }).toList();
  }

  // ────────────────────────────────────────────────────────────────
  Future<List<LeftListModel>> getLabelList() async {
    final items = await DBVideos.getAllLabelWithCount();
    final result = <LeftListModel>[];

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        result.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  Future<List<LeftListModel>> getSeriesList() async {
    final items = await DBVideos.getAllSeriesWithCount();
    final result = <LeftListModel>[];

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        result.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  Future<List<LeftListModel>> getStudioList() async {
    final items = await DBVideos.getAllStudioWithCount();
    final result = <LeftListModel>[];

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        result.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  Future<List<LeftListModel>> getDirectorList() async {
    final items = await DBVideos.getAllDirectorWithCount();
    final result = <LeftListModel>[];

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        result.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  Future<List<LeftListModel>> getYearList() async {
    final items = await DBVideos.getAllReleaseYearWithCount();
    final result = <LeftListModel>[];

    for (var item in items) {
      final String? id = item['id'] ?? UuidV4().generate();
      final String? name = item['name'];
      final int count = item['count'] as int;

      if (id != null) {
        result.add(LeftListModel(id: id, name: name, count: count));
      }
    }
    return result;
  }

  Future<List<LeftListModel>> getCustomList() async {
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


    return [
      LeftListModel(name: 'New Release', count: cNewRelease.length),
      LeftListModel(name: 'Favorite', count: cFavorite.length),
      LeftListModel(name: 'Most Watch', count: cMostWatch.length),
      LeftListModel(name: 'New Added', count: cNewAdded.length),
      LeftListModel(name: 'Never Watch', count: cNeverWatch.length),
      LeftListModel(name: '📺 HD', count: cHD.length),
      LeftListModel(name: '💿 FHD', count: cFHD.length),
      LeftListModel(name: '🇮🇩 Sub Indonesia', count: cSubId.length),
      LeftListModel(name: '🇬🇧 Sub English', count: cSubEn.length),
      LeftListModel(name: '✨ Reduce Mosaic', count: cRM.length),
      LeftListModel(name: '🚫 Non Jav', count: cNonJav.length),
    ];
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
