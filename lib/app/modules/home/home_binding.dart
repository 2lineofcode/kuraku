import 'package:get/get.dart';

import '../../repository/network/repo_javit.dart';
import 'home_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_files/page_files_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_library/page_library_controller.dart';
import 'page_settings/page_settings_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<RepoJavit>(() => RepoJavit());

    Get.lazyPut<PageHomeController>(() => PageHomeController());
    Get.lazyPut<PageLibraryController>(() => PageLibraryController());
    Get.lazyPut<PageFilesController>(() => PageFilesController());
    Get.lazyPut<PageExploreController>(() => PageExploreController());
    Get.lazyPut<PageSettingsController>(() => PageSettingsController());

    Get.lazyPut<HomeController>(() => HomeController());
  }
}
