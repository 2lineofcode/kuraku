import 'package:get/get.dart';

import '../player/player_controller.dart';
import 'home_controller.dart';
import 'page_download/page_download_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';
import 'page_tools/page_tools_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    // Home pages share the app lifetime, even when first accessed from a dialog.
    GetInstance().lazyPut<PageSettingsController>(() => PageSettingsController(), permanent: true);
    GetInstance().lazyPut<PageToolsController>(() => PageToolsController(), permanent: true);
    GetInstance().lazyPut<PageDownloadController>(() => PageDownloadController(), permanent: true);
    GetInstance().lazyPut<PageExploreController>(() => PageExploreController(), permanent: true);
    GetInstance().lazyPut<PageSearchController>(() => PageSearchController(), permanent: true);
    GetInstance().lazyPut<PageHomeController>(() => PageHomeController(), permanent: true);

    if (!Get.isRegistered<PlayerController>()) {
      Get.put<PlayerController>(PlayerController(), permanent: true);
    }

    Get.lazyPut<HomeController>(() => HomeController());
  }
}
