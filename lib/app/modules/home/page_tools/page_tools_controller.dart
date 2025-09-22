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

  // ** part: duplicate video
  final duplicateVideoList = <Videos>[].obs;

  // ** part: todo
  final todoList = <Activity>[].obs;

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

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page tools ==> onInit called');
    await getTopLargeFileSize();
    await checkIsHasDataNotScanned();
    await onReset();
    await filterBySeries();

    change(200, status: RxStatus.success());
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

  // ────────────────────────────────────────────────────────────────
  // ** part: kTopLargeFile
  // ────────────────────────────────────────────────────────────────
  Future<void> getTopLargeFileSize() async {
    topLargeFileSizeList.clear();
    topLargeFileSizeList.value = await DBVideos.getAll(
      where: 'filesize > 0',
      orderBy: 'filesize DESC',
      limit: 100,
    );
  }

  Future<void> checkIsHasDataNotScanned() async {
    final vid = await DBVideos.getAll(where: 'quality IS NULL OR quality = ""');
    isHasDataNotScanned.value = vid.isEmpty;
  }

  Future<void> scanAndUpdateDBVideoQuality() async {
    HelperLoading.show(isDismissible: false);
    final home = Get.find<HomeController>();
    final videos = await DBVideos.getAll(where: 'quality IS NULL OR quality = ""');
    for (var video in videos) {
      final percentage = (videos.indexOf(video) + 1) * 100 / videos.length;
      home.footerText.value = 'Scanning ${videos.indexOf(video) + 1}/${videos.length} | (${percentage.toStringAsFixed(2)}%)';
      try {
        final medInfo = await VideoCompress.getMediaInfo(video.videoPath!);
        if (medInfo.width == null) continue;
        video.quality = '${medInfo.width}x${medInfo.height}';
        await DBVideos.update(video);
      } catch (e) {
        AppLog.logD('error, try (ffmpeg) way -> ${video.videoPath}');
        await FFprobeKit.getMediaInformation(video.videoPath!).then((medInfo) {
          if (medInfo.getMediaInformation() == null) return;
          final stream = medInfo.getMediaInformation()?.getStreams().first;
          video.quality = '${stream?.getWidth()}x${stream?.getHeight()}';
          DBVideos.update(video);
        });
      }
    }
    await Get.find<HomeController>().onRefreshAllContent();
    HelperLoading.dismiss();
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kFindDuplicate
  // ────────────────────────────────────────────────────────────────
  Future<void> getDuplicateVideos() async {
    duplicateVideoList.value = await DBVideos.getListDuplicateVideos();
  }

  // ────────────────────────────────────────────────────────────────
  // ** part: kTodo
  // ────────────────────────────────────────────────────────────────
  Future<void> getTodos() async {
    final todoo = await DBActivity.getAll(where: 'type = ?', whereArgs: [kActivityTypeTodo]);
    for (var todo in todoo) {
      try {
        final existVideo = await DBVideos.getByCode(todo.content ?? '');
        if (todo.content == existVideo.videoCode) todo.content = '✔︎ ${todo.content}';
      } catch (_) {}
    }
    todoList.value = todoo;
  }

  Future<void> deleteTodos(Activity todo) async {
    await DBActivity.delete(todo);
    await getTodos();
  }

  Future<void> addTodo() async {
    final tecTodo = TextEditingController();
    final fnTodo = FocusNode();

    fnTodo.requestFocus();

    ExAlert.adaptive(
      title: Text('New Todo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.left).pOnly(bottom: 16),
      content: CupertinoTextField(
        controller: tecTodo,
        focusNode: fnTodo,
        style: TextStyle(color: Vx.white, fontSize: 12),
        placeholder: 'TODO',
        onSubmitted: (value) async {
          final newTodo = Activity(type: kActivityTypeTodo, content: value);
          await DBActivity.add(newTodo);
          await getTodos();
          Get.back();
        },
      ).pOnly(bottom: 8),
      actions: [
        CupertinoDialogAction(
          child: Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: () async {
            final newTodo = Activity(type: kActivityTypeTodo, content: tecTodo.text);
            await DBActivity.add(newTodo);
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
    } catch (_) {}
  }

  void onLeftListKeyPressedArrowDown() {
    try {
      if (leftListSelectedIndex.value < leftList.length - 1) {
        leftListSelectedIndex.value++;
        final item = leftList[leftListSelectedIndex.value];
        onLeftListTap(item, leftListSelectedIndex.value);
        leftListFocusNode.requestFocus();
      }
    } catch (_) {}
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
  }

  Future<void> onReset() async {
    currentFilterBy.value = kSeries;
    leftListSelected.value = '';
    tecFilterSearchLeft.text = '';
    rightList.value = [];
  }
}

// ** filter type
const kDuplicate = 'Duplicate Videos';
const kTodo = 'Todo';
const kTopLargeFile = 'Large File';
const kAdvanceSearch = 'Advance Search (R18)';
