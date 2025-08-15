import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_setting.dart';
import '../../../core/const.dart';
import '../../../data/database/db_init.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_relapse.dart';
import '../../../data/database/db_videos.dart';
import '../home_controller.dart';

class PageSettingsController extends GetxController {
  final appSetting = Get.find<AppSettingService>();

  final totalLibrary = 0.obs;
  final totalVideos = 0.obs;
  final lastRelapse = ''.obs;
  final r18TotalVideo = 0.obs;

  // **
  final tecApiUrl = TextEditingController();
  final tecProxyUrl = TextEditingController();
  final tecImgUrl = TextEditingController();
  final tecVidUrl = TextEditingController();
  final tecActressAvatarUrl = TextEditingController();

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page settings ==> onInit called');
    totalLibrary.value = await DBLibrary.getCount();
    totalVideos.value = await DBVideos.getCount();
    r18TotalVideo.value = await DBR18.getCountAllVideos();
    lastRelapse.value = await DBRelapse.getLastRelapse();
    lastRelapse.value = lastRelapse.value.ago(format: kYMd);
  }

  Future<void> onResetRelapse() async {
    await _openDialogConfirm(
      onYes: () async {
        await DBRelapse.deleteAll();
        Get.back();
      },
    );
  }

  Future<void> onResetAll() async {
    await _openDialogConfirm(
      onYes: () async {
        await Get.find<DBService>().deleteAllData();
        await Get.find<HomeController>().onRefreshAllContent();
        Get.back();
      },
    );
  }

  Future<void> updateR18DB() async {
    await launchUrlString('https://r18.dev/dumps');
  }

  Future<void> _openDialogConfirm({
    void Function()? onYes,
    String? title,
    String? message,
  }) async {
    ExAlert.adaptive(
      title: Text(title ?? 'Are you sure?', style: TextStyle(fontSize: 14)),
      content: message != null ? Text(message, style: TextStyle(fontSize: 12)).pOnly(top: 8) : null,
      actions: [
        CupertinoDialogAction(
          onPressed: onYes,
          child: Text('Yes', style: TextStyle(color: Vx.red500, fontSize: 13)),
        ),
        CupertinoDialogAction(
          child: Text('No', style: TextStyle(fontSize: 13)),
          onPressed: () {
            Get.back();
          },
        ),
      ],
    );
  }
}
