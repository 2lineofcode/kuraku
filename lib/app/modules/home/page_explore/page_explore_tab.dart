import 'dart:convert';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../home_panel/home_panel_video_info.dart';

class PageExploreTab {
  PageExploreTab(this.id, {RxSet<String>? pins, RxBool? savingPin})
      : _leftPins = pins ?? AppPref.getExplorePins().toSet().obs,
        isSavingPin = savingPin ?? false.obs {
    r18ScrollController.addListener(_onScroll);
    _pinWorker = ever(_leftPins, (_) => _applyLeftSort());
  }

  final int id;
  bool isClosed = false;
  final isLoading = false.obs;
  final isLoadingSelection = false.obs;
  final error = ''.obs;
  bool Function()? isActive;
  Worker? _pinWorker;
  Worker? _preferenceWorker;
  String get title => leftListSelected.value.name ?? currentMenuSelected.value;
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
  final RxSet<String> _leftPins;
  final RxBool isSavingPin;

  // ** part: [right] Videos
  final rightListViewMode = kLocal.obs;
  final rightListLocal = <Videos>[].obs;
  num get rightListLocalTotalSize => rightListLocal.fold<num>(0, (total, video) => total + (video.filesize ?? 0));
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


  Map<String, dynamic> toPreferences() => {
    'menu': currentMenuSelected.value,
    'selectedId': currentMenuSelected.value == kActress ? leftListSelected.value.id : null,
    'selectedName': leftListSelected.value.name,
    'leftQuery': tecSearchLeft.text,
    'rightQuery': tecSearchRight.text,
    'sort': leftSortSelected.value,
    'mode': rightListViewMode.value,
    'singleActress': singleActressMode.value,
    'filtered': filter.isFiltered.value,
    'videoCode': filter.tecVideoCode.text,
    'categoryDraft': filter.tecCategory.text,
    'categories': filter.categoriesSelected.toList(),
    'yearStart': filter.currentRange.value.start,
    'yearEnd': filter.currentRange.value.end,
  };

  void restorePreferences(Map<String, dynamic> value) {
    if (menus.contains(value['menu'])) currentMenuSelected.value = value['menu'];
    leftListSelected.value = LeftListModel(
      id: value['selectedId'] is num || value['selectedId'] is String ? value['selectedId'] : null,
      name: value['selectedName'] is String ? value['selectedName'] : null,
    );
    tecSearchLeft.text = value['leftQuery'] is String ? value['leftQuery'] : '';
    tecSearchRight.text = value['rightQuery'] is String ? value['rightQuery'] : '';
    if (leftSortOptions.contains(value['sort'])) leftSortSelected.value = value['sort'];
    rightListViewMode.value = value['mode'] == kR18 ? kR18 : kLocal;
    singleActressMode.value = value['singleActress'] != false;
    filter.isFiltered.value = value['filtered'] == true;
    filter.tecVideoCode.text = value['videoCode'] is String ? value['videoCode'] : '';
    filter.tecCategory.text = value['categoryDraft'] is String ? value['categoryDraft'] : '';
    if (value['categories'] is List) filter.categoriesSelected.assignAll((value['categories'] as List).whereType<String>().toSet());
    final start = value['yearStart'];
    final end = value['yearEnd'];
    final year = DateTime.now().year.toDouble();
    if (start is num && end is num && start.isFinite && end.isFinite && start <= end) {
      filter.currentRange.value = RangeValues(start.toDouble().clamp(2000, year), end.toDouble().clamp(2000, year));
    }
  }

  void watchPreferences(VoidCallback onChanged) {
    for (final field in [tecSearchLeft, tecSearchRight, filter.tecVideoCode, filter.tecCategory]) {
      field.addListener(onChanged);
    }
    _preferenceWorker = everAll([
      currentMenuSelected, leftListSelected, leftSortSelected, rightListViewMode, singleActressMode,
      filter.isFiltered, filter.categoriesSelected, filter.currentRange,
    ], (_) => onChanged());
  }

  Future<bool> loadIsFresh() async => await DBVideos.getCount() == 0;

  Future<void> onRefresh() async {
    if (isClosed) return;
    final freshness = loadIsFresh().then((fresh) {
      if (!isClosed) isFresh.value = fresh;
    }).catchError((Object e) {
      AppLog.logE('Explore refresh failed: $e');
    });
    final selected = leftListSelected.value;
    final mode = rightListViewMode.value;
    final pending = onMenuChange(currentMenuSelected.value, preserveState: true);
    final request = _menuRequest;
    final selectionRequest = _selectionRequest;
    await pending;
    await freshness;
    if (isClosed || request != _menuRequest || selectionRequest != _selectionRequest || error.value.isNotEmpty) return;
    final match = leftList.firstWhereOrNull((item) => currentMenuSelected.value == kActress && selected.id != null
        ? item.id.toString() == selected.id.toString() : item.name == selected.name);
    if (match != null) {
      final selection = onLeftListTap(match, preserveMode: true);
      final revision = _selectionRequest;
      await selection;
      if (isClosed || revision != _selectionRequest || error.value.isNotEmpty) return;
      if (mode == kR18 && rightListViewMode.value == kR18) await onSectionR18Tap();
    }
  }

  Future<void> openSelection(String menu, String name) async {
    final pending = onMenuChange(menu);
    final request = _menuRequest;
    await pending;
    if (isClosed || request != _menuRequest || error.value.isNotEmpty) return;
    tecSearchLeft.text = name;
    onLeftListDoSearch(name);
    final item = leftListFiltered.firstWhereOrNull((item) => item.name == name) ?? (leftListFiltered.isEmpty ? null : leftListFiltered.first);
    if (item != null) await onLeftListTap(item);
  }

  void close() {
    isClosed = true;
    _menuRequest++;
    _selectionRequest++;
    _r18Request++;
    _preferenceWorker?.dispose();
    _pinWorker?.dispose();
  }

  void dispose() {
    close();
    r18ScrollController.dispose();
    tecSearchLeft.dispose();
    fnSearchLeft.dispose();
    leftListFocusNode.dispose();
    tecSearchRight.dispose();
    fnSearchRight.dispose();
    filter.tecVideoCode.dispose();
    filter.tecActressName.dispose();
    filter.tecCategory.dispose();
  }

  Future<void> onMenuChange(String menu, {bool preserveState = false}) async {
    if (isClosed) return;
    final request = ++_menuRequest;
    _selectionRequest++;
    isLoadingSelection.value = false;
    leftList.clear();
    leftListFiltered.clear();
    rightListLocal.clear();
    _resetR18Pagination();
    currentMenuSelected.value = menu;
    rightListR18TotalVideo.value = 0;
    if (!preserveState) {
      leftListSelected.value = LeftListModel();
      rightListViewMode.value = kLocal;
      tecSearchLeft.clear();
    }
    isLoading.value = true;
    error.value = '';

    try {
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
      onLeftListDoSearch(tecSearchLeft.text);
    } catch (e) {
      if (!isClosed && request == _menuRequest) error.value = 'Failed to load Explore. Please refresh.';
      AppLog.logE('Explore menu failed: $e');
    } finally {
      if (!isClosed && request == _menuRequest) isLoading.value = false;
    }
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
    leftListFiltered.sort((a, b) {
      final pinned = (isLeftPinned(b) ? 1 : 0).compareTo(isLeftPinned(a) ? 1 : 0);
      if (pinned != 0) return pinned;
      if (leftSortSelected.value == 'Count') {
        final count = (b.count ?? 0).compareTo(a.count ?? 0);
        if (count != 0) return count;
      }
      return (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
    });
    leftListHoveredIndex.value = -1;
    _syncLeftSelectionIndex();
    leftListFiltered.refresh();
  }

  String _leftPinKey(LeftListModel item) => jsonEncode([
    currentMenuSelected.value,
    currentMenuSelected.value == kActress && item.id != null ? item.id.toString() : item.name ?? '',
  ]);

  bool isLeftPinned(LeftListModel item) => _leftPins.contains(_leftPinKey(item));

  Future<void> toggleLeftPin(LeftListModel item) async {
    if (isSavingPin.value) return;
    final key = _leftPinKey(item);
    final pins = _leftPins.toSet();
    if (!pins.remove(key)) pins.add(key);
    isSavingPin.value = true;
    try {
      await AppPref.setExplorePins(pins.toList());
      _leftPins.value = pins;
      _applyLeftSort();
    } catch (e) {
      AppLog.logE('Failed to save Explore pin: $e');
      if (!isClosed) Get.snackbar('Pin', 'Failed to save pin. Please try again.');
    } finally {
      isSavingPin.value = false;
    }
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

  Future<void> onLeftListTap(LeftListModel item, {bool preserveMode = false}) async {
    if (isClosed) return;
    final request = ++_selectionRequest;
    final menu = currentMenuSelected.value;
    leftListSelected.value = item;
    if (!preserveMode) rightListViewMode.value = kLocal;
    leftListSelectedIndex.value = leftListFiltered.indexOf(item);
    if (!preserveMode && (isActive?.call() ?? true)) leftListFocusNode.requestFocus();
    _resetR18Pagination();
    rightListLocal.clear();
    rightListR18TotalVideo.value = 0;
    error.value = '';
    isLoadingSelection.value = true;
    try {
      final result = await loadSelection(menu, item);
      if (request != _selectionRequest || isClosed) return;
      rightListLocal.assignAll(result.$1);
      rightListR18TotalVideo.value = result.$2;
    } catch (e) {
      if (!isClosed && request == _selectionRequest) error.value = 'Failed to load videos. Please select the item again.';
      AppLog.logE('Explore selection failed: $e');
    } finally {
      if (!isClosed && request == _selectionRequest) isLoadingSelection.value = false;
    }
  }

  Future<(List<Videos>, int)> loadSelection(String menu, LeftListModel item) async {

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
    return (result[0] as List<Videos>, result[1] as int);
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
      isAvailable: () => !isClosed && request == _r18Request && (isActive?.call() ?? true),
    );
  }

  Future<void> onSectionLocalTap() async => rightListViewMode.value = kLocal;

  Future<void> onSectionR18Tap() async {
    if (isClosed || rightListR18TotalVideo.value == 0) return;
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
    if (isClosed || !r18ScrollController.hasClients) return;
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
