import 'dart:io';
import 'dart:math' as math;

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

class PageToolsController extends GetxController {
  final menus = [kAdvanceSearch, kDuplicate, kTopLargeFile, kTodo].obs;
  final toolSelected = ''.obs;

  // **
  final dupVideos = <Videos>[].obs;
  final totalDupVideos = 0.obs;

  // **
  final todos = <History>[].obs;

  // **
  final top100LargeFile = <Map<String, dynamic>>[].obs;

  // **
  final tecCategory = TextEditingController();
  final tecActressName = TextEditingController();
  final tecVideoCode = TextEditingController();
  final currentRange = RangeValues(2000, DateTime.now().year.toDouble()).obs;
  final actresses = <String>[].obs;
  final categories = <String>[].obs;
  final categoriesSelected = <String>[].obs;
  final videos = <Map<String, dynamic>>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page tools ==> onInit called');
    toolSelected.value = kAdvanceSearch;
    await getAllCategories();
    await getAllActresses();
  }

  Future<void> onMenuChange(String menu) async {
    toolSelected.value = menu;
    if (menu == kDuplicate) await getDuplicateVideos();
    if (menu == kTodo) await getTodos();
    if (menu == kTopLargeFile) await getTopLargeFile();
    if (menu == kAdvanceSearch) {
      await getAllCategories();
      await getAllActresses();
    }
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
  Future<void> getAllCategories() async {
    categories.clear();
    await DBR18.getAllCategories().then((cat) {
      for (var i = 0; i < cat.length; i++) {
        categories.add('${cat[i]['name_en']}');
      }
      categories.unique();
    });
  }

  Future<void> getAllActresses() async {
    actresses.clear();
    await DBR18.getAllActress().then((actress) {
      for (var i = 0; i < actress.length; i++) {
        actresses.add('${actress[i]['name_romaji']}');
      }
      actresses.unique();
    });
  }

  Future<void> onAdvanceSearch() async {
    videos.clear();
    HelperLoading.show();

    final data = await DBR18.advanceSearch(
      categories: categoriesSelected,
      startYear: currentRange.value.start.toInt().toString(),
      endYear: currentRange.value.end.toInt().toString(),
      actressName: '',
    );

    // Filter hanya valid video_code
    videos.addAll(data.where((item) => HelperMisc.isValidVideoCode(item['video_code'] ?? '')));

    // Filter berdasarkan input tecVideoCode
    if (tecVideoCode.text.isNotBlank) {
      videos.removeWhere((video) => !video['video_code'].toString().toLowerCase().contains(tecVideoCode.text.toLowerCase()));
    }

    if(tecActressName.text.isNotBlank) {
      videos.removeWhere((video) => !video['actresses'].toString().toLowerCase().contains(tecActressName.text.toLowerCase()));
    }

    // unique by `video_code`
    videos.unique((item) => item['video_code']);

    // Urutkan berdasarkan release_date
    videos.sort((a, b) => b['release_date'].compareTo(a['release_date']));

    // Tambah field is_clicked
    videos.assignAll(videos.map((r18Item) {
      final mutable = Map<String, dynamic>.from(r18Item);
      mutable['is_clicked'] = false;
      return mutable;
    }).toList());

    HelperLoading.dismiss();
    videos.refresh();

  }
}

// ** Constants ---
const kDuplicate = 'Duplicate Videos';
const kTodo = 'Todo';
const kTopLargeFile = 'Large File';
const kAdvanceSearch = 'Advance Search';
