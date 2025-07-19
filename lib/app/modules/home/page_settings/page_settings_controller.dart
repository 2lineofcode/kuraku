import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqlite_api.dart';

import '../../../core/app_setting.dart';
import '../../../data/database/db_init.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_relapse.dart';
import '../../../data/database/db_videos.dart';
import '../home_controller.dart';

class PageSettingsController extends GetxController {
  final appSetting = Get.find<AppSettingService>();

  final totalLibrary = 0.obs;
  final totalVideos = 0.obs;
  final totalRelapse = 0.obs;
  final lastRelapse = ''.obs;
  final r18Version = 0.obs;
  final r18VersionText = ''.obs;

  @override
  Future<void> onInit() async {
    totalLibrary.value = await DBLibrary.getCount();
    totalVideos.value = await DBVideos.getCount();
    totalRelapse.value = await DBRelapse.getCount();
    lastRelapse.value = await DBRelapse.getLastRelapse();
    r18Version.value = await Get.find<DBService>().dbR18.getVersion();
    r18VersionText.value = '${r18Version.value.toString().reformatDate(from: 'yyyyMMdd', to: 'yyyy MM dd')}';
    print(r18Version.value.toString());

    super.onInit();
  }

  Future<void> onResetAll() async {
    await Get.find<DBService>().deleteAllData();
    await Get.find<HomeController>().onRefreshAllContent();
  }
}
