import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/activity_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../page_explore/page_explore_controller.dart';

class PageToolsController extends GetxController with StateMixin {
  // ** part: top menu
  final menus = [kTopLargeFile, kDuplicate, kAdvanceSearch, kTodo].obs;
  final currentMenuSelected = kTopLargeFile.obs;

  // ** part: large filesize
  final missingQualityCount = 0.obs;
  final qualityScanRunning = false.obs;
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
  final topLargeHoveredIndex = (-1).obs;

  // ** part: duplicate video
  final duplicateModes = ['exact', 'probable'].obs;
  final duplicateMode = 'exact'.obs;
  final duplicateVideoList = <Videos>[].obs;
  final duplicateGroupCount = 0.obs;
  final duplicateHoveredIndex = (-1).obs;

  // ** part: todo
  final todoList = <Activity>[].obs;
  final todoHoveredIndex = (-1).obs;
  final todoPosterByCode = <String, String>{}.obs;

  // ** part: advance search
  // -> left part
  final currentFilterBy = kSeries.obs;
  final tecFilterSearchLeft = TextEditingController();
  final fnFilterSearchLeft = FocusNode();

  final leftList = <Map<String, dynamic>>[].obs;
  final leftListScrollController = ScrollController().obs;
  final leftListSelected = ''.obs;
  final leftListSelectedId = ''.obs;
  final leftListLoading = false.obs;
  final leftListError = ''.obs;
  int _leftRequest = 0;
  int _selectionRequest = 0;
  final leftListHoveredIndex = (-1).obs;
  final leftListSelectedIndex = 0.obs;
  final leftListFocusNode = FocusNode();

  // -> right part
  final rightList = <Map<String, dynamic>>[].obs;
  final rightListFiltered = <Map<String, dynamic>>[].obs;
  final filter = VideoFilterState();

  @override
  Future<void> onInit() async {
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();

    await getTopLargeFileSize();
    await checkIsHasDataNotScanned();
    await onReset();
    if (currentMenuSelected.value == kAdvanceSearch) await filterBySeries();

    AppLog.logI('page tools ==> onInit called: ${sw.elapsedMilliseconds} ms');
    change(200, status: RxStatus.success());
  }

  @override
  void onClose() {
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
    currentMenuSelected.value = menu;
    switch (menu) {
      case kTopLargeFile: await getTopLargeFileSize(); await checkIsHasDataNotScanned(); break;
      case kDuplicate: await getDuplicateVideos(); break;
      case kAdvanceSearch:
        if (leftList.isEmpty && !leftListLoading.value) await _loadAdvancedGroups(currentFilterBy.value, tecFilterSearchLeft.text);
        break;
      case kTodo: await getTodos(); break;
    }
  }

  Future<void> onReset() async {
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
    topLargeHoveredIndex.value = -1;
    duplicateMode.value = 'exact';
    duplicateGroupCount.value = 0;
    duplicateHoveredIndex.value = -1;
    todoHoveredIndex.value = -1;
    todoPosterByCode.clear();
    rightList.value = [];
    rightListFiltered.value = [];
    filter.reset();
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kTopLargeFile
  // ────────────────────────────────────────────────────────────────
  Future<void> getTopLargeFileSize({String mode = 'all'}) async {
    topLargeFileSizeList.clear();
    topLargeHoveredIndex.value = -1;
    
    var whereQ = 'filesize > 0';
    switch (mode) {
      case 'all': whereQ = 'filesize > 0'; break;
      case 'internal': whereQ = 'filesize > 0 AND video_path NOT LIKE "/Volumes%"'; break;
      case 'external': whereQ = 'filesize > 0 AND video_path LIKE "/Volumes%"'; break;
    }

    topLargeFileSizeList.value = await DBVideos.getAll(
      where: whereQ,
      orderBy: 'filesize DESC',
      limit: 200,
    );
  }

  void onTopLargeHover(int index, bool isHover) {
    if (isHover) {
      if (topLargeHoveredIndex.value != index) topLargeHoveredIndex.value = index;
      return;
    }

    if (topLargeHoveredIndex.value == index) topLargeHoveredIndex.value = -1;
  }

  Future<void> checkIsHasDataNotScanned() async {
    missingQualityCount.value = await DBVideos.countMissingQuality();
  }

  Future<List<Videos>> loadMissingQuality() => DBVideos.getMissingQuality();
  Future<int> saveMissingQuality(Videos video, String quality) => DBVideos.updateMissingQuality(video, quality);

  void stopQualityScan() {
    if (!qualityScanRunning.value) return;
    _qualityScanCancelled = true;
    qualityScanStatus.value = 'Stopping… Saved results will be kept.';
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
    qualityScanTotal.value = 0;
    qualityScanChecked.value = 0;
    qualityScanUpdated.value = 0;
    qualityScanSkipped.value = 0;
    qualityScanStatus.value = 'Finding videos with missing resolution…';
    final sw = Stopwatch()..start();
    AppLog.logI('Resolution scan: started');
    try {
      final videos = await loadMissingQuality();
      qualityScanTotal.value = videos.length;
      for (final video in videos) {
        if (_qualityScanCancelled || isClosed) break;
        qualityScanFile.value = p.basename(video.videoPath ?? '');
        qualityScanStatus.value = 'Reading video metadata…';
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
      qualityScanStatus.value = '${_qualityScanCancelled ? 'Stopped' : 'Finished'} · ${qualityScanUpdated.value} updated · ${qualityScanSkipped.value} skipped';
      AppLog.logI('Resolution scan: ${qualityScanStatus.value} in ${sw.elapsedMilliseconds} ms');
      if (!isClosed) {
        await checkIsHasDataNotScanned();
        await getTopLargeFileSize(mode: topLargeFilterMode.value);
      }
    } catch (e) {
      qualityScanStatus.value = 'Scan failed. Saved results are kept. Please retry.';
      AppLog.logE('Resolution scan failed: $e');
    } finally {
      qualityScanFile.value = '';
      qualityScanRunning.value = false;
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
        throw TimeoutException('Metadata probe exceeded 15 seconds');
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
    if (duplicateMode.value == mode) return;
    duplicateMode.value = mode;
    await getDuplicateVideos();
  }

  Future<void> getDuplicateVideos() async {
    duplicateHoveredIndex.value = -1;
    final groups = await DBVideos.getDuplicateVideoGroups(mode: duplicateMode.value);
    duplicateGroupCount.value = groups.length;
    duplicateVideoList.value = groups.expand((items) => items).toList();
  }

  void onDuplicateHover(int index, bool isHover) {
    if (isHover) {
      if (duplicateHoveredIndex.value != index) duplicateHoveredIndex.value = index;
      return;
    }

    if (duplicateHoveredIndex.value == index) duplicateHoveredIndex.value = -1;
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kTodo
  // ────────────────────────────────────────────────────────────────
  Future<void> getTodos() async {
    todoHoveredIndex.value = -1;
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

  void onTodoHover(int index, bool isHover) {
    if (isHover) {
      if (todoHoveredIndex.value != index) todoHoveredIndex.value = index;
      return;
    }

    if (todoHoveredIndex.value == index) todoHoveredIndex.value = -1;
  }

  Future<void> deleteTodos(Activity todo) async {
    await DBActivity.deleteTodo(todo.id ?? '');
    await getTodos();
  }

  Future<void> addTodo() async {
    final tecTodo = TextEditingController();
    final fnTodo = FocusNode();

    fnTodo.requestFocus();

    ExAlert.adaptive(
      title: Text('New Todo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 30),
        child: CupertinoTextField(
          controller: tecTodo,
          focusNode: fnTodo,
          style: TextStyle(color: AppColor.text, fontSize: 12),
          placeholder: 'TODO',
          onSubmitted: (value) async {
            final newTodo = Activity(type: kActivityTypeTodo, content: value);
            await DBActivity.addTodo(newTodo.content ?? '');
            await getTodos();
            Get.back();
          },
        ).pOnly(bottom: 8),
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
    final request = ++_leftRequest;
    _selectionRequest++;
    currentFilterBy.value = kind;
    tecFilterSearchLeft.text = q ?? '';
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
      if (!isClosed && request == _leftRequest) leftListError.value = 'Could not load catalog. Please retry.';
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
      await _applyFilter();
      change(200, status: RxStatus.success());
    } catch (e) {
      if (!isClosed && request == _selectionRequest) change(0, status: RxStatus.error('Could not load videos. Please retry.'));
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


  // ~ Filters ────────────────────────────────────────────────────────────────
  final _filterAdapter = VideoFilterAdapter<Map<String, dynamic>>(
    videoCode: (video) => video['video_code'] ?? '',
    actresses: (video) => video['actresses'] ?? <String>[],
    categories: (video) => video['categories'] ?? <String>[],
    releaseDate: (video) => video['release_date'] ?? '',
    durationMinutes: (video) => num.tryParse('${video['duration'] ?? video['runtime_mins'] ?? ''}'),
  );

  Future<void> _applyFilter() async {
    final filtered = filter.apply(rightList.toList(), _filterAdapter);
    rightListFiltered.value = filtered;
  }

  Future<void> openDialogFilter() async {
    await HelperOpener.openFilterDialog<Map<String, dynamic>>(
      state: filter,
      allVideos: rightList.toList(),
      videos: rightListFiltered,
      adapter: _filterAdapter,
      showCategories: false,
      showActressName: false,
    );
  }
}

// ** filter type
const kDuplicate = 'Duplicate Videos';
const kTodo = 'Todo';
const kTopLargeFile = 'Large File';
const kAdvanceSearch = 'Advance Search (R18)';
