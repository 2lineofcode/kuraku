import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../data/database/db_library.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/library_entity.dart';
import '../../utils/helper_file_picker.dart';
import '../../utils/helper_misc.dart';
import 'home_library.dart';
import 'page_download/page_download_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';

class HomeController extends GetxController with StateMixin {
  final currentMenuSelected = kMenuHome.obs;
  final loadingText = 'Please wait...'.obs;
  final footerText = ''.obs;
  final library = <Library>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    change(200, status: RxStatus.loading());
    logS('root home ==> onInit called');

    footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
    change(200, status: RxStatus.success());
  }

  void onOpenLibrary() async {
    library.value = await DBLibrary.getAll();
    await HomeLibrary.openMenuLibrary(library);
  }

  Future<void> onRefreshAllContent() async {
    try {
      footerText.value = 'Refreshing...';
      // await onInit();
      await Get.find<PageHomeController>().onInit();
      await Get.find<PageSearchController>().onInit();
      await Get.find<PageExploreController>().onInit();
      await Get.find<PageSettingsController>().onInit();
      await Get.find<PageDownloadController>().onInit();
      footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
      change(200, status: RxStatus.success());
    } catch (e) {
      // footerSum.value = 'Error: $e';
      ExAlert.adaptive(
        title: Text('Ups'),
        content: Text('${e.toString()}'),
        actions: [
          CupertinoDialogAction(
            child: Text('Refresh', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              await onRefreshAllContent();
              Get.back();
            },
          ),
        ],
      );
    }
  }

  Future<void> onMenuChange(String menu) async {
    currentMenuSelected.value = menu;
  }

  Future<void> onDropEvent(PerformDropEvent event) async {
    final item = event.session.items.first;
    final reader = item.dataReader!;

    // type folder
    reader.getValue<Uri>(Formats.fileUri, (data) async {
      if (data == null) return;
      final isFolder = await FileSystemEntity.isDirectory(data.path);
      if (isFolder) {
        final _path = data.path.removeLast(1)!;

        final newLibrary = await HelperFilePicker.scanFolderAndSubFolder(_path);
        newLibrary?.alias = newLibrary.rootFolder?.getLastPath();

        await HomeLibrary.openDialogAddorEditLibrary(library: newLibrary, isFromDrop: true);
      }
    });
  }
}

// ────────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────────
// # menus
const kMenuHome = 'Home';
const kMenuSearch = 'Search';
const kMenuExplore = 'Explore';
const kMenuDownload = 'Download';
const kMenuSetting = 'Settings';