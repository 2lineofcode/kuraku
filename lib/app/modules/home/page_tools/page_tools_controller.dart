import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';
import 'package:video_compress/video_compress.dart';

import '../../../core/app_logging.dart';
import '../../../data/database/db_history.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/history_entity.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper.dart';
import '../home_controller.dart';
import '../page_download/page_download_controller.dart';
import '../page_explore/page_explore_controller.dart';

class PageToolsController extends GetxController with StateMixin {
  final menus = [kTopLargeFile, kDuplicate, kAdvanceSearch, kTodo].obs;
  final menuSelected = ''.obs;

  // **
  final dupVideos = <Videos>[].obs;
  final totalDupVideos = 0.obs;

  // **
  final todos = <History>[].obs;

  // **
  final isHasDataNonHaveQuality = true.obs;
  final top100LargeFile = <Videos>[].obs;

  // **
  final filterBy = ''.obs;
  final oList = <Map<String, dynamic>>[].obs;
  final oListScrollController = FlutterListViewController().obs;
  final oListSelected = ''.obs;

  final oListHoveredIndex = (-1).obs;
  final oListSelectedIndex = 0.obs;
  final oListFocusNode = FocusNode();

  final tecFilterSearch = TextEditingController();
  final fnFilterSearch = FocusNode();
  final r18ListVideo = <Map<String, dynamic>>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page tools ==> onInit called');
    await getTopLargeFile();
    await checkIsHasDataNonHaveVideoQuality();
    menuSelected.value = kTopLargeFile;
    await onResetFilter();
    await filterBySeries();

    change(200, status: RxStatus.success());
  }

  Future<void> onMenuChange(String menu) async {
    menuSelected.value = menu;
    if (menu == kDuplicate) await getDuplicateVideos();
    if (menu == kTodo) await getTodos();
    if (menu == kTopLargeFile) {
      await getTopLargeFile();
      await checkIsHasDataNonHaveVideoQuality();
    }
    if (menu == kAdvanceSearch) { }
  }

  // ** kFindDuplicate Part ---
  Future<void> getDuplicateVideos() async {
    dupVideos.value = await DBVideos.getListDuplicateVideos();
    totalDupVideos.value = (dupVideos.length / 2).toInt();
  }

  // ** kTodo Part ---
  Future<void> getTodos() async {
    final todoo = await DBHistory.getAll(where: 'type = ?', whereArgs: ['todo']);
    for (var todo in todoo) {
      try {
        final xvid = await DBVideos.getByCode(todo.message ?? '');
        if (todo.message == xvid.videoCode) todo.message = '✔︎ ${todo.message}';
      } catch (_) {}
    }
    todos.value = todoo;
  }

  Future<void> itemTodosSearch(String s) async {
    await Get.find<HomeController>().onMenuChange(kMenuDownload);
    Get.find<PageDownloadController>().tecSearch.text = s;
    await Get.find<PageDownloadController>().onSearch(s);
  }

  Future<void> deleteTodos(History todo) async {
    await DBHistory.delete(todo);
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
          final newTodo = History(id: UuidV4().generate(), type: 'todo', message: value);
          await DBHistory.add(newTodo);
          await getTodos();
          Get.back();
        },
      ).pOnly(bottom: 8),
      actions: [
        CupertinoDialogAction(
          child: Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: () async {
            final newTodo = History(id: UuidV4().generate(), type: 'todo', message: tecTodo.text);
            await DBHistory.add(newTodo);
            await getTodos();
            Get.back();
          },
        ),
      ],
    );
  }

  // ** kTopLargeFile Part ---
  Future<void> getTopLargeFile() async {
    top100LargeFile.clear();
    top100LargeFile.value = await DBVideos.getAll(
      where: 'filesize > 0',
      orderBy: 'filesize DESC',
      limit: 100,
    );
  }

  Future<void> checkIsHasDataNonHaveVideoQuality() async {
    final vid = await DBVideos.getAll(where: 'quality IS NULL OR quality = ""');
    isHasDataNonHaveQuality.value = vid.isEmpty;
  }

  Future<void> updateDBVideoQuality() async {
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
        AppLog.logD('(ffmpeg) -> ${video.videoPath}');
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

  // ** kAdvanceSearch Part ---
  Future<void> filterByActress({String? q}) async => oList.value = await DBR18.getAllActress(q: q);
  Future<void> filterBySeries({String? q}) async => oList.value = await DBR18.getAllSeries(q: q);
  Future<void> filterByCategories({String? q}) async => oList.value = await DBR18.getAllCategories(q: q);
  Future<void> filterByYear({String? q}) async {
    final yearNow = DateTime.now().year;
    final sub30Year = yearNow - 40;
    oList.value = [];
    for (var i = sub30Year; i <= yearNow; i++) {
      oList.value.add({'id': i, 'name_en': i.toString()});
    }
    oList.value.sort((a, b) => b['id'].compareTo(a['id']));
  }

  Future<void> onOListTap(dynamic item, int index) async {
    change(0, status: RxStatus.loading());

    oListSelectedIndex.value = index;
    oListFocusNode.requestFocus();

    oListSelected.value = item['name_en'];
    final _selectedId = item['id'];
    var videos = <Map<String, dynamic>>[];

    switch (filterBy.value) {
      case kActress: videos = await DBR18.getAllVideosByActress(_selectedId); break;
      case kSeries: videos = await DBR18.getAllVideosBySeries(oListSelected.value); break;
      case kCategory: videos = await DBR18.getAllVideosByCategory(oListSelected.value); break;
      case kYear: videos = await DBR18.getAllVideosByYear(oListSelected.value); break;
    }

    // filter
    r18ListVideo.value = [];
    for (var i = 0; i < videos.length; i++) {
      final videoCode = videos[i]['video_code'].toString();
      if (videoCode.isValidVideoCode()) {
        r18ListVideo.value.add(videos[i]);
      }
    }

    // check has match video by code
    final vList = await DBVideos.getAll();
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

    if (r18ListVideo.isNotEmpty) {
      change(200, status: RxStatus.success());
    } else {
      change(200, status: RxStatus.empty());
    }
  }


  void onOListMoveSelectionUp() {
    try {
      if (oListSelectedIndex.value > 0) {
        oListSelectedIndex.value--;
        final item = oList[oListSelectedIndex.value];
        onOListTap(item, oListSelectedIndex.value);
        oListFocusNode.requestFocus();
      }
    } catch (_) {}
  }

  void onOListMoveSelectionDown() {
    try {
      if (oListSelectedIndex.value < oList.length - 1) {
        oListSelectedIndex.value++;
        final item = oList[oListSelectedIndex.value];
        onOListTap(item, oListSelectedIndex.value);
        oListFocusNode.requestFocus();
      }
    } catch (_) {}
  }

  Future<void> onSearchFilter(String s) async {
    final prefix = HelperDecensor.censored(s.toTitleCase);
    switch (filterBy.value) {
      case kActress: await filterByActress(q: s); break;
      case kSeries: await filterBySeries(q: s); break;
      case kCategory: await filterByCategories(q: prefix); break;
      case kYear: await filterByYear(q: s); break;
    }
    fnFilterSearch.requestFocus();
    oListScrollController.value.animToTop();
  }

  Future<void> onResetFilter() async {
    filterBy.value = kSeries;
    oListSelected.value = '';
    tecFilterSearch.text = '';
    r18ListVideo.value = [];
  }
}

// ** Constants ---
const kDuplicate = 'Duplicate Videos';
const kTodo = 'Todo';
const kTopLargeFile = 'Large File';
const kAdvanceSearch = 'Advance Search (R18)';
