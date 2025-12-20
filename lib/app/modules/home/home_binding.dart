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
    Get.put<PageSettingsController>(PageSettingsController());
    Get.put<PageToolsController>(PageToolsController());
    Get.put<PageDownloadController>(PageDownloadController());
    Get.put<PageExploreController>(PageExploreController());
    Get.put<PageSearchController>(PageSearchController());
    Get.put<PageHomeController>(PageHomeController());

    if (!Get.isRegistered<PlayerController>()) {
      Get.put<PlayerController>(PlayerController(), permanent: true);
    }

    Get.lazyPut<HomeController>(() => HomeController());
  }
}
