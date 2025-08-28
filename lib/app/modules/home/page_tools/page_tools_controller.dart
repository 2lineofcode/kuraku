import 'dart:io';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

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
  final menus = [kDuplicate, kTopLargeFile, kTodo, kAdvanceSearch].obs;
  final toolSelected = ''.obs;

  // **
  final dupVideos = <Videos>[].obs;
  final totalDupVideos = 0.obs;

  // **
  final todos = <History>[].obs;

  // **
  final top100LargeFile = <Map<String, dynamic>>[].obs;

  // **
  final filterBy = ''.obs;
  final listFilter = <Map<String, dynamic>>[].obs;
  final listFilterScrollController = FlutterListViewController().obs;
  final filterItemSelected = ''.obs;
  final tecFilterSearch = TextEditingController();
  final fnFilterSearch = FocusNode();
  final r18ListVideo = <Map<String, dynamic>>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page tools ==> onInit called');
    await getDuplicateVideos();
    toolSelected.value = kDuplicate;
    await onResetFilter();
    await filterBySeries();
    change(200, status: RxStatus.success());
  }

  Future<void> onMenuChange(String menu) async {
    toolSelected.value = menu;
    if (menu == kDuplicate) await getDuplicateVideos();
    if (menu == kTodo) await getTodos();
    if (menu == kTopLargeFile) await getTopLargeFile();
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
    final videos = await DBVideos.getAll();

    List<Map<String, dynamic>> tempFileList = [];

    for (var i = 0; i < videos.length; i++) {
      final path = videos[i].videoPath ?? '';

      final file = File(path);

      if (await file.exists()) {
        try {
          final int sizeInBytes = await file.length();

          tempFileList.add({
            'code': videos[i].videoCode != null && videos[i].videoCode!.isNotEmpty ? videos[i].videoCode : videos[i].title ?? '',
            'title': videos[i].title ?? '',
            'path': path,
            'sizeInBytes': sizeInBytes,
          });
        } catch (e) {
          print('Error getting file size for $path: $e');
        }
      }
    }

    if (tempFileList.isNotEmpty) {
      tempFileList.sort((a, b) => b['sizeInBytes'].compareTo(a['sizeInBytes']));
      final top100 = tempFileList.take(100).toList();
      final formattedList = top100.map((fileData) {
        return {
          'code': fileData['code'],
          'title': fileData['title'],
          'path': fileData['path'],
          'size': _formatFileSize(fileData['sizeInBytes']),
        };
      }).toList();

      top100LargeFile.value = formattedList;
      top100LargeFile.refresh();
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  // ** kAdvanceSearch Part ---
  Future<void> filterByActress({String? q}) async => listFilter.value = await DBR18.getAllActress(q: q);
  Future<void> filterBySeries({String? q}) async => listFilter.value = await DBR18.getAllSeries(q: q);
  Future<void> filterByCategories({String? q}) async => listFilter.value = await DBR18.getAllCategories(q: q);
  Future<void> filterByYear({String? q}) async {
    final yearNow = DateTime.now().year;
    final sub30Year = yearNow - 40;
    listFilter.value = [];
    for (var i = sub30Year; i <= yearNow; i++) {
      listFilter.value.add({'id': i, 'name_en': i.toString()});
    }
    listFilter.value.sort((a, b) => b['id'].compareTo(a['id']));
  }

  Future<void> onFilterItemSelected(dynamic item) async {
    change(0, status: RxStatus.loading());

    filterItemSelected.value = item['name_en'];
    final _selectedId = item['id'];
    var videos = <Map<String, dynamic>>[];

    switch (filterBy.value) {
      case kActress: videos = await DBR18.getAllVideosByActress(_selectedId); break;
      case kSeries: videos = await DBR18.getAllVideosBySeries(filterItemSelected.value); break;
      case kCategory: videos = await DBR18.getAllVideosByCategory(filterItemSelected.value); break;
      case kYear: videos = await DBR18.getAllVideosByYear(filterItemSelected.value); break;
    }

    // filter
    r18ListVideo.value = [];
    for (var i = 0; i < videos.length; i++) {
      if (HelperMisc.isValidVideoCode(videos[i]['video_code'].toString())) {
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

  Future<void> onResetFilter() async {
    filterBy.value = kSeries;
    filterItemSelected.value = '';
    tecFilterSearch.text = '';
    r18ListVideo.value = [];
  }
}

// ** Constants ---
const kDuplicate = 'Duplicate Videos';
const kTodo = 'Todo';
const kTopLargeFile = 'Large File';
const kAdvanceSearch = 'Advance Search (R18)';
