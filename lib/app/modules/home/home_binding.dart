import 'package:get/get.dart';

import '../../data/api/api_javit.dart';
import 'home_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiJavit>(() => ApiJavit());

    Get.lazyPut<PageHomeController>(() => PageHomeController());
    Get.lazyPut<PageSearchController>(() => PageSearchController());
    Get.lazyPut<PageExploreController>(() => PageExploreController());
    Get.lazyPut<PageSettingsController>(() => PageSettingsController());

    Get.lazyPut<HomeController>(() => HomeController());
  }
}
