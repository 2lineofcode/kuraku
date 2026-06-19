import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:get/get.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/app_logging.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/activity_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../home_controller.dart';
import '../page_explore/page_explore_controller.dart';

class PageToolsController extends GetxController with StateMixin {
  // ** part: top menu
  final menus = [kTopLargeFile, kDuplicate, kAdvanceSearch, kTodo].obs;
  final currentMenuSelected = kTopLargeFile.obs;

  // ** part: large filesize
  final isHasDataNotScanned = true.obs; // is has data not scanned filesize & resolution
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
  final leftListScrollController = FlutterListViewController().obs;
  final leftListSelected = ''.obs;
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
    await filterBySeries();

    AppLog.logI('page tools ==> onInit called: ${sw.elapsedMilliseconds} ms');
    change(200, status: RxStatus.success());
  }

  @override
  void onClose() {
    tecFilterSearchLeft.dispose();
    fnFilterSearchLeft.dispose();
    leftListFocusNode.dispose();
    super.onClose();
  }

  Future<void> onMenuChange(String menu) async {
    currentMenuSelected.value = menu;
    switch (menu) {
      case kTopLargeFile: await getTopLargeFileSize(); await checkIsHasDataNotScanned(); break;
      case kDuplicate: await getDuplicateVideos(); break;
      case kAdvanceSearch: break;
      case kTodo: await getTodos(); break;
    }
  }

  Future<void> onReset() async {
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
    filter.isFiltered.value = false;
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
    final vid = await DBVideos.getAll(where: 'quality IS NULL OR quality = ""');
    for (var v in vid) {
      AppLog.logD('checkIsHasDataNotScanned: ${v.videoPath}');
    }
    isHasDataNotScanned.value = vid.isEmpty;
  }

  Future<void> scanAndUpdateDBVideoRes() async {
    final home = Get.find<HomeController>();
    final videos = await DBVideos.getAll(where: 'quality IS NULL OR quality = ""');
    if (videos.isEmpty) {
      home.footerText.value = 'Idle | All videos already have quality';
      return;
    }

    HelperLoading.show(isDismissible: false);
    final sw = Stopwatch()..start();
    final total = videos.length;

    try {
      for (var i = 0; i < total; i++) {
        final video = videos[i];
        final percentage = ((i + 1) * 100 / total).toStringAsFixed(2);
        home.footerText.value = 'Scanning ${i + 1}/$total | ($percentage%)';

        final quality = await _extractQuality(video.videoPath ?? '');
        if (quality != null) {
          video.quality = quality;
          await DBVideos.update(video);
        }

        // Yield to UI every few iterations to avoid visible freeze.
        if (i % 5 == 0) await Future.delayed(const Duration(milliseconds: 1));
      }

      await home.onRefreshAllContent();
      isHasDataNotScanned.value = true;
      AppLog.logI('scanAndUpdateDBVideoRes finished in ${sw.elapsedMilliseconds} ms');
    } finally {
      HelperLoading.dismiss();
    }
  }

  Future<String?> _extractQuality(String path) async {
    if (path.isEmpty) return null;

    try {
      final medInfo = await VideoCompress.getMediaInfo(path);
      if (medInfo.width != null && medInfo.height != null) {
        return '${medInfo.width}x${medInfo.height}';
      }
    } catch (e) {
      AppLog.logD('VideoCompress failed for $path => $e');
    }

    try {
      final probe = await FFprobeKit.getMediaInformation(path);
      final info = probe.getMediaInformation();
      final streams = info?.getStreams();

      if (streams != null) {
        for (final stream in streams) {
          final width = stream.getWidth();
          final height = stream.getHeight();
          if (width != null && height != null) {
            return '${width}x$height';
          }
        }
      }
    } catch (e) {
      AppLog.logE('FFprobeKit failed for $path => $e');
    }

    return null;
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
          style: TextStyle(color: Vx.white, fontSize: 12),
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
  Future<void> filterByActress({String? q}) async => leftList.value = await DBR18.getAllActress(q: q);
  Future<void> filterBySeries({String? q}) async => leftList.value = await DBR18.getAllSeries(q: q);
  Future<void> filterByCategories({String? q}) async => leftList.value = await DBR18.getAllCategories(q: q);
  Future<void> filterByYear({String? q}) async {
    final yearNow = DateTime.now().year;
    final sub30Year = yearNow - 40;
    leftList.value = [];
    for (var i = sub30Year; i <= yearNow; i++) {
      leftList.value.add({'id': i, 'name_en': i.toString()});
    }
    leftList.value.sort((a, b) => b['id'].compareTo(a['id']));
  }

  Future<void> onLeftListTap(dynamic item, int index) async {
    change(0, status: RxStatus.loading());

    leftListSelectedIndex.value = index;
    leftListFocusNode.requestFocus();

    leftListSelected.value = item['name_en'];
    final _selectedId = item['id'];
    var videos = <Map<String, dynamic>>[];

    switch (currentFilterBy.value) {
      case kActress: videos = await DBR18.getAllVideosByActress(_selectedId); break;
      case kSeries: videos = await DBR18.getAllVideosBySeries(leftListSelected.value); break;
      case kCategory: videos = await DBR18.getAllVideosByCategory(leftListSelected.value); break;
      case kYear: videos = await DBR18.getAllVideosByYear(leftListSelected.value); break;
    }

    // filter
    rightList.value = [];
    rightListFiltered.value = [];
    for (var i = 0; i < videos.length; i++) {
      final videoCode = videos[i]['video_code'].toString();
      if (videoCode.isValidVideoCode()) {
        rightList.value.add(videos[i]);
      }
    }

    // check has match video by code
    final vList = await DBVideos.getAll();
    rightList.assignAll(rightList.map((r18) {
      final Map<String, dynamic> _mutableItem = Map.from(r18);
      final hasMatch = vList.any((vItem) => r18['video_code'].toString() == (vItem.videoCode!));
      _mutableItem['match'] = hasMatch;
      _mutableItem['is_clicked'] = false;

      final releaseDate = DateTime.parse(r18['release_date'] ?? '');
      _mutableItem['is_released'] = releaseDate.isBefore(DateTime.now());
      return _mutableItem;
    }).toList());

    rightList.refresh();

    rightListFiltered.value = rightList.toList();
    rightListFiltered.refresh();

    if (rightList.isNotEmpty) {
      change(200, status: RxStatus.success());
    } else {
      change(200, status: RxStatus.empty());
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
    final prefix = HelperDecensor.censored(q.toTitleCase);
    switch (currentFilterBy.value) {
      case kActress: await filterByActress(q: q); break;
      case kSeries: await filterBySeries(q: q); break;
      case kCategory: await filterByCategories(q: prefix); break;
      case kYear: await filterByYear(q: q); break;
    }
    fnFilterSearchLeft.requestFocus();
    leftListScrollController.value.animToTop();
    if (filter.isFiltered.isTrue) await _applyFilter();
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
