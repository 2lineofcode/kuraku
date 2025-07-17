import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/const.dart';
import '../../data/database/db_library.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/library_entity.dart';
import '../../utils/helper_file_picker.dart';
import '../../utils/helper_library.dart';
import '../../utils/helper_misc.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';

class HomeController extends GetxController with StateMixin {
  final currentMenuSelected = '...'.obs;
  final footerSum = ''.obs;
  final library = <Library>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();

    currentMenuSelected.value = kMenuHome;

    footerSum.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';

    change(200, status: RxStatus.success());
  }

  void onOpenLibrary() async {
    library.value = await DBLibrary.getAll();
    await HelperLibrary.openMenuLibrary(library);
  }

  Future<void> onRefreshAllContent() async {
    footerSum.value = 'Refreshing...';
    await Get.find<PageHomeController>().onInit();
    await Get.find<PageSearchController>().onInit();
    await Get.find<PageExploreController>().onInit();
    await Get.find<PageSettingsController>().onInit();
    footerSum.value = 'Iddle | Total Video: ${await DBVideos.getCount()}';
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

        HelperLibrary.dialogAddorEditLibrary(library: newLibrary, isFromDrop: true);
      }
    });
  }
}
