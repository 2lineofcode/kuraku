import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/activity_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../../widgets/widget_controls.dart';
import '../../widgets/widget_surfaces.dart';
import '../page_explore/page_explore_controller.dart';

class PageToolsController extends GetxController with StateMixin {
  // ** part: top menu
  final menus = [kTopLargeFile, kDuplicate, kAdvanceSearch, kTodo].obs;
  final currentMenuSelected = kTopLargeFile.obs;
  int _deletedMenuRequest = 0;

  Future<void> refreshDeletedItemsMenu() async {
    final request = ++_deletedMenuRequest;
    try {
      final deleted = await DBVideos.getAll(includeDeleted: true, where: 'is_deleted = 1', limit: 1);
      if (isClosed || request != _deletedMenuRequest) return;
      if (deleted.isNotEmpty) {
        if (!menus.contains(kDeletedItems)) menus.insert(2, kDeletedItems);
      } else {
        menus.remove(kDeletedItems);
        if (currentMenuSelected.value == kDeletedItems) currentMenuSelected.value = kTopLargeFile;
      }
    } catch (e) {
      AppLog.logE('Refreshing deleted items menu failed: $e');
    }
  }

  // ** part: large filesize
  final missingQualityCount = 0.obs;
  final qualityScanRunning = false.obs;
  final qualityScanStopping = false.obs;
  final qualityScanFailed = false.obs;
  final qualityScanTotal = 0.obs;
  final qualityScanChecked = 0.obs;
  final qualityScanUpdated = 0.obs;
  final qualityScanSkipped = 0.obs;
  final qualityScanStatus = ''.obs;
  final qualityScanFile = ''.obs;
  bool _qualityScanCancelled = false;
  MediaInformationSession? _qualityProbe;
  Completer<String?>? _qualityProbeResult;
  final topLargeFileSizeList = <Videos>[].obs;
  final topLargeFilterMode = 'all'.obs; // all | internal | external
  final topLargeLoading = false.obs;
  final topLargeError = ''.obs;
  int _topLargeRequest = 0;

  // ** part: duplicate video
  final duplicateModes = ['exact', 'probable'].obs;
  final duplicateMode = 'exact'.obs;
  final duplicateGroups = <List<Videos>>[].obs;
  final duplicateLoading = false.obs;
  final duplicateError = ''.obs;
  final duplicateQuery = ''.obs;
  final tecDuplicateSearch = TextEditingController();
  final duplicateFileAvailable = <String, bool>{}.obs;
  int _duplicateRequest = 0;

  int get duplicateVideoCount => duplicateGroups.fold(0, (count, group) => count + group.length);
  List<List<Videos>> get filteredDuplicateGroups {
    final query = duplicateQuery.value.trim().toLowerCase();
    return duplicateGroups.where((group) => group.any((video) =>
      [video.videoCode, video.title, video.videoPath, video.quality].any((value) => (value ?? '').toLowerCase().contains(query))
    )).toList();
  }

  // ** part: todo
  final todoList = <Activity>[].obs;
  final todoPosterByCode = <String, String>{}.obs;

  // ** part: advance search
  // -> left part
  final currentFilterBy = kSeries.obs;
  final tecFilterSearchLeft = TextEditingController();
  final fnFilterSearchLeft = FocusNode();

  final leftList = <Map<String, dynamic>>[].obs;
  final leftListScrollController = FlutterListViewController().obs;
  final leftListSelected = ''.obs;
  final leftListSelectedId = ''.obs;
  final leftListLoading = false.obs;
  final leftListError = ''.obs;
  int _leftRequest = 0;
  int _selectionRequest = 0;
  Timer? _groupSearchTimer;
  final leftListHoveredIndex = (-1).obs;
  final leftListSelectedIndex = 0.obs;
  final leftListFocusNode = FocusNode();

  // -> right part
  final rightList = <Map<String, dynamic>>[].obs;
  final rightListFiltered = <Map<String, dynamic>>[].obs;
  final filter = VideoFilterState();
  final tecResultSearch = TextEditingController();
  final resultQuery = ''.obs;
  final releaseFilter = 'all'.obs;
  final libraryFilter = 'all'.obs;
  final resultSort = 'newest'.obs;

  bool get hasAdvancedFilters => resultQuery.value.isNotEmpty || releaseFilter.value != 'all' || libraryFilter.value != 'all' || filter.isFiltered.value;

  @override
  Future<void> onInit() async {
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();

    await refreshDeletedItemsMenu();
    await getTopLargeFileSize();
    await checkIsHasDataNotScanned();
    await onReset();
    if (currentMenuSelected.value == kAdvanceSearch) await filterBySeries();
    if (currentMenuSelected.value == kDuplicate) await getDuplicateVideos();

    AppLog.logI('page tools ==> onInit called: ${sw.elapsedMilliseconds} ms');
    change(200, status: RxStatus.success());
  }

  @override
  void onClose() {
    _groupSearchTimer?.cancel();
    _topLargeRequest++;
    _duplicateRequest++;
    tecDuplicateSearch.dispose();
    tecResultSearch.dispose();
    _leftRequest++;
    _selectionRequest++;
    stopQualityScan();
    tecFilterSearchLeft.dispose();
    fnFilterSearchLeft.dispose();
    leftListFocusNode.dispose();
    leftListScrollController.value.dispose();
    super.onClose();
  }

  Future<void> onMenuChange(String menu) async {
    if (menu != kDuplicate) {
      _duplicateRequest++;
      duplicateLoading.value = false;
    }
    currentMenuSelected.value = menu;
    switch (menu) {
      case kTopLargeFile: await getTopLargeFileSize(mode: topLargeFilterMode.value); await checkIsHasDataNotScanned(); break;
      case kDuplicate: await getDuplicateVideos(); break;
      case kAdvanceSearch:
        if (leftList.isEmpty && !leftListLoading.value) await _loadAdvancedGroups(currentFilterBy.value, tecFilterSearchLeft.text);
        break;
      case kTodo: await getTodos(); break;
    }
  }

  Future<void> onReset() async {
    _groupSearchTimer?.cancel();
    _leftRequest++;
    _selectionRequest++;
    leftListSelectedId.value = '';
    leftListSelectedIndex.value = -1;
    leftListHoveredIndex.value = -1;
    leftList.clear();
    leftListLoading.value = false;
    leftListError.value = '';
    currentFilterBy.value = kSeries;
    leftListSelected.value = '';
    tecFilterSearchLeft.text = '';
    topLargeFilterMode.value = 'all';
    _duplicateRequest++;
    duplicateGroups.clear();
    duplicateFileAvailable.clear();
    duplicateLoading.value = false;
    duplicateError.value = '';
    duplicateQuery.value = '';
    tecDuplicateSearch.clear();
    todoPosterByCode.clear();
    rightList.value = [];
    rightListFiltered.value = [];
    filter.reset();
    tecResultSearch.clear();
    resultQuery.value = '';
    releaseFilter.value = 'all';
    libraryFilter.value = 'all';
    resultSort.value = 'newest';
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kTopLargeFile
  // ────────────────────────────────────────────────────────────────
  Future<void> getTopLargeFileSize({String mode = 'all'}) async {
    final request = ++_topLargeRequest;
    topLargeFilterMode.value = mode;
    topLargeLoading.value = true;
    topLargeError.value = '';
    topLargeFileSizeList.clear();

    var whereQ = 'filesize > 0';
    switch (mode) {
      case 'internal': whereQ = 'filesize > 0 AND video_path NOT LIKE "/Volumes%"'; break;
      case 'external': whereQ = 'filesize > 0 AND video_path LIKE "/Volumes%"'; break;
    }

    try {
      final items = await DBVideos.getAll(where: whereQ, orderBy: 'filesize DESC', limit: 200);
      if (request == _topLargeRequest) topLargeFileSizeList.value = items;
    } catch (e) {
      AppLog.logE('[LargeFiles] Load failed: $e');
      if (request == _topLargeRequest) topLargeError.value = 'Could not load videos. Please retry.';
    } finally {
      if (request == _topLargeRequest) topLargeLoading.value = false;
    }
  }

  Future<void> checkIsHasDataNotScanned() async {
    missingQualityCount.value = await DBVideos.countMissingQuality();
  }

  Future<List<Videos>> loadMissingQuality() => DBVideos.getMissingQuality();
  Future<int> saveMissingQuality(Videos video, String quality) => DBVideos.updateMissingQuality(video, quality);

  void stopQualityScan() {
    if (!qualityScanRunning.value) return;
    _qualityScanCancelled = true;
    qualityScanStopping.value = true;
    qualityScanStatus.value = 'Stopping… Saved results will be kept.'.tr;
    AppLog.logI('Resolution scan: stop requested');
    unawaited(_cancelQualityProbe());
  }

  Future<void> _cancelQualityProbe() async {
    final result = _qualityProbeResult;
    try { await _qualityProbe?.cancel(); }
    catch (e) { AppLog.logW('Resolution scan: cancel failed: $e'); }
    if (result != null && !result.isCompleted) result.complete(null);
  }

  Future<void> scanAndUpdateDBVideoRes() async {
    if (qualityScanRunning.value || isClosed) return;
    qualityScanRunning.value = true;
    _qualityScanCancelled = false;
    qualityScanStopping.value = false;
    qualityScanFailed.value = false;
    qualityScanTotal.value = 0;
    qualityScanChecked.value = 0;
    qualityScanUpdated.value = 0;
    qualityScanSkipped.value = 0;
    qualityScanStatus.value = 'Finding videos with missing resolution…'.tr;
    final sw = Stopwatch()..start();
    AppLog.logI('Resolution scan: started');
    try {
      final videos = await loadMissingQuality();
      qualityScanTotal.value = videos.length;
      for (final video in videos) {
        if (_qualityScanCancelled || isClosed) break;
        qualityScanFile.value = p.basename(video.videoPath ?? '');
        qualityScanStatus.value = 'Reading video metadata…'.tr;
        try {
          final quality = await extractQuality(video.videoPath ?? '');
          if (_qualityScanCancelled || isClosed) break;
          if (quality != null && await saveMissingQuality(video, quality) > 0) {
            qualityScanUpdated.value++;
          } else {
            qualityScanSkipped.value++;
            AppLog.logW('Resolution scan: skipped ${video.id} (${qualityScanFile.value})');
          }
        } catch (e) {
          if (_qualityScanCancelled || isClosed) break;
          qualityScanSkipped.value++;
          AppLog.logW('Resolution scan: ${qualityScanFile.value}: $e');
        }
        qualityScanChecked.value++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      qualityScanStatus.value = '@{Finished} · @{value} updated · @{value2} skipped'.trNamed({'Finished': '${_qualityScanCancelled ? 'Stopped'.tr : 'Finished'.tr}', 'value': '${qualityScanUpdated.value}', 'value2': '${qualityScanSkipped.value}'});
      AppLog.logI('Resolution scan: ${qualityScanStatus.value} in ${sw.elapsedMilliseconds} ms');
      if (!isClosed) {
        await checkIsHasDataNotScanned();
        await getTopLargeFileSize(mode: topLargeFilterMode.value);
      }
    } catch (e) {
      qualityScanFailed.value = true;
      qualityScanStatus.value = 'Scan failed. Saved results are kept. Please retry.'.tr;
      AppLog.logE('Resolution scan failed: $e');
    } finally {
      qualityScanFile.value = '';
      qualityScanRunning.value = false;
      qualityScanStopping.value = false;
    }
  }

  Future<String?> extractQuality(String path) async {
    if (path.isEmpty) return null;
    final localPath = path.startsWith('file:') ? Uri.parse(path).toFilePath() : path;
    final stat = await File(localPath).stat().timeout(const Duration(seconds: 5));
    if (stat.type != FileSystemEntityType.file || _qualityScanCancelled || isClosed) return null;
    final result = Completer<String?>();
    _qualityProbeResult = result;
    try {
      _qualityProbe = await FFprobeKit.getMediaInformationFromCommandArgumentsAsync([
        '-v', 'error', '-select_streams', 'V:0', '-show_entries', 'stream=width,height',
        '-print_format', 'json', '-i', localPath,
      ], (session) {
        if (result.isCompleted) return;
        final streams = session.getMediaInformation()?.getStreams();
        final stream = streams == null || streams.isEmpty ? null : streams.first;
        final width = stream?.getWidth() ?? 0;
        final height = stream?.getHeight() ?? 0;
        result.complete(width > 0 && height > 0 ? '${width}x$height' : null);
      });
      if (_qualityScanCancelled || isClosed) await _cancelQualityProbe();
      return await result.future.timeout(const Duration(seconds: 15), onTimeout: () async {
        await _cancelQualityProbe();
        throw TimeoutException('Metadata probe exceeded 15 seconds'.tr);
      });
    } finally {
      _qualityProbe = null;
      _qualityProbeResult = null;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kFindDuplicate
  // ────────────────────────────────────────────────────────────────
  Future<void> setDuplicateMode(String mode) async {
    if (!duplicateModes.contains(mode) || duplicateMode.value == mode) return;
    duplicateMode.value = mode;
    await getDuplicateVideos();
  }

  Future<List<List<Videos>>> loadDuplicateGroups(String mode) => DBVideos.getDuplicateVideoGroups(mode: mode);

  Future<Map<String, bool>> checkDuplicateFiles(List<List<Videos>> groups) async {
    final available = <String, bool>{};
    for (final path in groups.expand((group) => group).map((video) => video.videoPath ?? '').toSet()) {
      try {
        available[path] = path.isNotEmpty && await File(path).exists();
      } catch (_) {
        available[path] = false;
      }
    }
    return available;
  }

  Future<void> getDuplicateVideos() async {
    final request = ++_duplicateRequest;
    duplicateLoading.value = true;
    duplicateError.value = '';
    duplicateGroups.clear();
    duplicateFileAvailable.clear();
    try {
      final groups = await loadDuplicateGroups(duplicateMode.value);
      if (isClosed || request != _duplicateRequest) return;
      final available = await checkDuplicateFiles(groups);
      if (isClosed || request != _duplicateRequest) return;
      duplicateFileAvailable.assignAll(available);
      duplicateGroups.assignAll(groups);
    } catch (e) {
      if (isClosed || request != _duplicateRequest) return;
      AppLog.logE('Duplicate scan failed: $e');
      duplicateError.value = 'Could not load duplicate videos. Please retry.'.tr;
    } finally {
      if (!isClosed && request == _duplicateRequest) duplicateLoading.value = false;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kTodo
  // ────────────────────────────────────────────────────────────────
  Future<void> getTodos() async {
    final todos = await DBActivity.getTodos();
    for (var todo in todos) {
      try {
        final existVideo = await DBVideos.getByCode(todo.content ?? '');
        if (todo.content == existVideo.videoCode) todo.content = '✔︎ ${todo.content}';
      } catch (e) {
        AppLog.logD('Todo match check failed for "${todo.content}": $e');
      }
    }
    await _refreshTodoPosterCache(todos);
    todoList.value = todos;
  }

  Future<void> _refreshTodoPosterCache(List<Activity> todos) async {
    final codes = <String>{};
    for (final todo in todos) {
      final code = (todo.content ?? '').replaceAll('✔︎', '').trim();
      if (code.isValidVideoCode()) codes.add(code);
    }

    if (codes.isEmpty) {
      todoPosterByCode.clear();
      return;
    }

    final posterMap = await DBR18.getPosterByCodes(codes.toList());
    todoPosterByCode.clear();
    todoPosterByCode.addAll(posterMap);
    todoPosterByCode.refresh();
  }

  Future<void> deleteTodos(Activity todo) async {
    await DBActivity.deleteTodo(todo.id ?? '');
    await getTodos();
  }

  Future<void> addTodo() async {
    final tecTodo = TextEditingController();
    final fnTodo = FocusNode();

    fnTodo.requestFocus();

    AppConfirmDialog.show(
      title: Text('New Todo'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 30),
        child: AppTextField(
          controller: tecTodo,
          focusNode: fnTodo,
          style: TextStyle(color: AppColor.text),
          placeholder: 'TODO'.tr,
          onSubmitted: (value) async {
            final newTodo = Activity(type: kActivityTypeTodo, content: value);
            await DBActivity.addTodo(newTodo.content ?? '');
            await getTodos();
            Get.back();
          },
        ).pOnly(bottom: 8),
      ),
      actions: [
        AppDialogAction(
          child: Text('Save'.tr, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: () async {
            final newTodo = Activity(type: kActivityTypeTodo, content: tecTodo.text);
            await DBActivity.addTodo(newTodo.content ?? '');
            await getTodos();
            Get.back();
          },
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kAdvanceSearch
  // ────────────────────────────────────────────────────────────────
  Future<void> filterByActress({String? q}) => _loadAdvancedGroups(kActress, q);
  Future<void> filterBySeries({String? q}) => _loadAdvancedGroups(kSeries, q);
  Future<void> filterByCategories({String? q}) => _loadAdvancedGroups(kCategory, q);
  Future<void> filterByYear({String? q}) => _loadAdvancedGroups(kYear, q);

  Future<void> _loadAdvancedGroups(String kind, String? q) async {
    _groupSearchTimer?.cancel();
    final request = ++_leftRequest;
    _selectionRequest++;
    currentFilterBy.value = kind;
    if (tecFilterSearchLeft.text != (q ?? '')) tecFilterSearchLeft.text = q ?? '';
    leftListSelected.value = '';
    leftListSelectedId.value = '';
    leftListSelectedIndex.value = -1;
    leftListHoveredIndex.value = -1;
    leftList.clear();
    rightList.clear();
    rightListFiltered.clear();
    leftListLoading.value = true;
    leftListError.value = '';
    try {
      final query = kind == kCategory && q != null ? HelperDecensor.censored(q.toTitleCase) : q;
      final items = await DBR18.getAdvancedSearchGroups(kind, q: query);
      if (isClosed || request != _leftRequest) return;
      leftList.assignAll(items);
    } catch (e) {
      if (!isClosed && request == _leftRequest) leftListError.value = 'Could not load catalog. Please retry.'.tr;
      AppLog.logE('R18 groups failed: $e');
    } finally {
      if (!isClosed && request == _leftRequest) leftListLoading.value = false;
    }
  }

  Future<void> onLeftListTap(dynamic item, int index) async {
    final request = ++_selectionRequest;
    final kind = currentFilterBy.value;
    change(0, status: RxStatus.loading());
    leftListSelectedIndex.value = index;
    leftListSelected.value = item['name_en'];
    leftListSelectedId.value = '${item['id']}';
    leftListFocusNode.requestFocus();
    rightList.clear();
    rightListFiltered.clear();
    try {
      final (videos, owned) = await (
        DBR18.getAdvancedSearchVideos(kind, item['id']), DBVideos.getAll(),
      ).wait;
      if (isClosed || request != _selectionRequest) return;
      final codes = owned.map((video) => (video.videoCode ?? '').toUpperCase()).toSet();
      final now = DateTime.now();
      rightList.assignAll(videos.map((video) {
        final released = DateTime.tryParse('${video['release_date'] ?? ''}');
        return {
          ...video,
          'match': codes.contains('${video['video_code']}'.toUpperCase()),
          'is_clicked': false,
          'is_released': released == null ? null : !released.isAfter(now),
        };
      }));
      await applyAdvancedFilters();
      change(200, status: RxStatus.success());
    } catch (e) {
      if (!isClosed && request == _selectionRequest) change(0, status: RxStatus.error('Could not load videos. Please retry.'.tr));
      AppLog.logE('R18 selection failed: $e');
    }
  }

  void onLeftListKeyPressedArrowUp() {
    try {
      if (leftListSelectedIndex.value > 0) {
        leftListSelectedIndex.value--;
        final item = leftList[leftListSelectedIndex.value];
        onLeftListTap(item, leftListSelectedIndex.value);
        leftListFocusNode.requestFocus();
      }
    } catch (e) {
      AppLog.logD('Arrow up navigation failed: $e');
    }
  }

  void onLeftListKeyPressedArrowDown() {
    try {
      if (leftListSelectedIndex.value < leftList.length - 1) {
        leftListSelectedIndex.value++;
        final item = leftList[leftListSelectedIndex.value];
        onLeftListTap(item, leftListSelectedIndex.value);
        leftListFocusNode.requestFocus();
      }
    } catch (e) {
      AppLog.logD('Arrow down navigation failed: $e');
    }
  }

  Future<void> onLeftListDoSearch(String q) async {
    await _loadAdvancedGroups(currentFilterBy.value, q);
    if (isClosed) return;
    fnFilterSearchLeft.requestFocus();
    if (leftListScrollController.value.hasClients) leftListScrollController.value.jumpTo(0);
  }

  void searchAdvancedGroups(String q) {
    _groupSearchTimer?.cancel();
    _groupSearchTimer = Timer(const Duration(milliseconds: 250), () => onLeftListDoSearch(q));
  }


  // ~ Filters ────────────────────────────────────────────────────────────────
  final _filterAdapter = VideoFilterAdapter<Map<String, dynamic>>(
    videoCode: (video) => video['video_code'] ?? '',
    title: (video) => video['title'],
    actresses: (video) => video['actresses'] ?? <String>[],
    categories: (video) => video['categories'] ?? <String>[],
    releaseDate: (video) => video['release_date'] ?? '',
    durationMinutes: (video) => num.tryParse('${video['duration'] ?? video['runtime_mins'] ?? ''}'),
    actressCount: (video) => video['actress_count'] as int?,
    series: (video) => video['series'] as String?,
  );

  Future<void> applyAdvancedFilters() async {
    final query = resultQuery.value.trim().toLowerCase();
    final filtered = filter.apply(rightList.toList(), _filterAdapter).where((video) {
      return (query.isEmpty || '${video['video_code']} ${video['title'] ?? ''}'.toLowerCase().contains(query))
          && (releaseFilter.value == 'all' || (releaseFilter.value == 'released' ? video['is_released'] == true : video['is_released'] == false))
          && (libraryFilter.value == 'all' || (libraryFilter.value == 'owned' ? video['match'] == true : video['match'] != true));
    }).toList();
    filtered.sort((a, b) {
      if (resultSort.value == 'code') return '${a['video_code']}'.compareTo('${b['video_code']}');
      final aDate = DateTime.tryParse('${a['release_date'] ?? ''}');
      final bDate = DateTime.tryParse('${b['release_date'] ?? ''}');
      if (aDate == null || bDate == null) return aDate == bDate ? 0 : aDate == null ? 1 : -1;
      if (resultSort.value == 'newest' && (a['is_released'] == false) != (b['is_released'] == false)) return a['is_released'] == false ? 1 : -1;
      final order = aDate.compareTo(bDate);
      return order == 0 ? '${a['video_code']}'.compareTo('${b['video_code']}') : resultSort.value == 'oldest' ? order : -order;
    });
    rightListFiltered.value = filtered;
  }

  Future<void> clearAdvancedFilters() async {
    tecResultSearch.clear();
    resultQuery.value = '';
    releaseFilter.value = 'all';
    libraryFilter.value = 'all';
    filter.reset();
    await applyAdvancedFilters();
  }

  Future<void> openDialogFilter() async {
    await HelperOpener.openFilterDialog<Map<String, dynamic>>(
      state: filter,
      allVideos: rightList.toList(),
      videos: rightListFiltered,
      adapter: _filterAdapter,
      showCategories: false,
      showActressName: false,
      applyLocalFilter: false,
      onReset: applyAdvancedFilters,
      onApplied: (_) => applyAdvancedFilters(),
      isAvailable: () => !isClosed,
    );
  }
}

// ** filter type
const kDuplicate = 'Duplicate Videos';
const kDeletedItems = 'Deleted Items';
const kTodo = 'Todo';
const kTopLargeFile = 'Large File';
const kAdvanceSearch = 'Advanced Search (R18)';
