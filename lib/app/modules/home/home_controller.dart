import 'dart:async';

import 'package:get/get.dart';

import '../../core/const.dart';
import '../../models/library_entity.dart';
import '../../repository/local/db_library.dart';
import '../../repository/local/db_videos.dart';
import '../../utils/helper_overlay.dart';

class HomeController extends GetxController with StateMixin {
  final currentMenuSelected = '...'.obs;
  final footerSum = ''.obs;
  final library = <Library>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();

    currentMenuSelected.value = kMenuHome;

    // every 1 second refresh footer
    // Timer.periodic(const Duration(seconds: 1), (timer) async {
    //   footerSum.value = '${await DBVideos.getCount()} Videos';
    // });

    change(200, status: RxStatus.success());
  }

  void onOpenLibrary() async {
    library.value = await DBLibrary.getAll();
    await HelperOverlay.openMenuLibrary(library);
  }

  Future<void> onMenuChange(String menu) async {
    currentMenuSelected.value = menu;
  }
}
