import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:uicons_pro/uicons_pro.dart';

import '../../core/app_logging.dart';
import '../../core/app_pref.dart';
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
import 'page_tools/page_tools_controller.dart';

class HomeController extends GetxController with StateMixin {
  final menus = <Map<String, dynamic>>[
    {'icon': UIconsPro.regularRounded.comet, 'name': kMenuHome},
    {'icon': UIconsPro.regularRounded.magnifying_glass_wave, 'name': kMenuSearch},
    {'icon': UIconsPro.regularRounded.book_alt, 'name': kMenuExplore},
    {'icon': UIconsPro.regularRounded.display_arrow_down, 'name': kMenuDownload},
    {'icon': UIconsPro.regularRounded.customization, 'name': kMenuTools},
    {'icon': UIconsPro.regularRounded.operating_system_upgrade, 'name': kMenuSetting},
  ];
  final currentMenuSelected = kMenuHome.obs;

  final loadingText = '...'.obs;
  final footerText = ''.obs;
  final sideMenuWidth = 180.0.obs;

  final library = <Library>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    change(200, status: RxStatus.loading());
    AppLog.logI('root home ==> onInit called');

    footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';

    sideMenuWidth.value = AppPref.getAppHideSideMenu() ? 65 : 180;
    change(200, status: RxStatus.success());
  }

  Future<void> onRefreshAllContent() async {
    try {
      footerText.value = 'Refreshing...';
      await Get.find<PageHomeController>().onInit();
      await Get.find<PageSearchController>().onInit();
      await Get.find<PageExploreController>().onInit();
      await Get.find<PageDownloadController>().onInit();
      await Get.find<PageToolsController>().onInit();
      await Get.find<PageSettingsController>().onInit();
      footerText.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
      change(200, status: RxStatus.success());
    } catch (e) {
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

  void onOpenLibrary() async {
    library.value = await DBLibrary.getAll();
    await HomeLibrary.openMenuLibrary(library);
  }

  Future<void> onMenuChange(String menu) async {
    currentMenuSelected.value = menu;
  }


  // ──────────────────────────────────────────────────────────────
  // onDropEvent
  // ──────────────────────────────────────────────────────────────
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
// # menu const
// ────────────────────────────────────────────────────────────────
const kMenuHome = 'Home';
const kMenuSearch = 'Search';
const kMenuExplore = 'Explore';
const kMenuDownload = 'Download';
const kMenuTools = 'Tools';
const kMenuSetting = 'Settings';