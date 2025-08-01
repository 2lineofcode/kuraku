import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_setting.dart';
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

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page settings ==> onInit called');
    totalLibrary.value = await DBLibrary.getCount();
    totalVideos.value = await DBVideos.getCount();
    lastRelapse.value = await DBRelapse.getLastRelapse();
    r18TotalVideo.value = await DBR18.getCountAllVideos();
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

  Future<void> updateR18DB() async {
    await launchUrlString('https://r18.dev/dumps');
  }

  Future<void> openKeyboardShortcuts() async {
    final shortcuts = <Map<String, String>>[
      {'key': 'Esc', 'action': 'Close Dialog / Panel'},
      {'key': '⌘ + X', 'action': 'Close Dialog / Panel'},
      {'key': '⌘ + R', 'action': 'Reload All Page'},
      {'key': '⌘ + D', 'action': 'Open New Dialog Download'},
      {'key': '⌘ + T', 'action': 'Open New Add Todo'},
      {'key': '⌘ + B', 'action': 'Show/Hide Side Menu'},

      {'key': '⌘ + 1', 'action': 'Open Home Page'},
      {'key': '⌘ + 2', 'action': 'Open Library Page'},
      {'key': '⌘ + 3', 'action': 'Open Explore Page'},
      {'key': '⌘ + 4', 'action': 'Open Download Page'},
      {'key': '⌘ + 5', 'action': 'Open Tool Page'},
      {'key': '⌘ + ,', 'action': 'Open Setting Page'},
    ];
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.center,
        width: MediaQuery.of(Get.context!).size.width * 90 / 100,
        height: MediaQuery.of(Get.context!).size.width * 9.0 / 16.0,
        child: VStack(
          [
            'Keyboard Shortcuts'.text.bold.size(16).make().pOnly(bottom: 12),
            Table(
              border: TableBorder.all(color: AppColor.border),
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(4),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColor.container),
                  children: [
                    'Key'.text.bold.make().p8(),
                    'Action'.text.bold.make().p8(),
                  ],
                ),

                // items
                ...List.generate(
                  shortcuts.length,
                  (index) => TableRow(children: [
                    '${shortcuts[index]['key']}'.text.make().p4(),
                    '${shortcuts[index]['action']}'.text.make().p4(),
                  ]),
                ),
              ],
            ).p12(),
          ],
        ).scrollVertical().p12(),
      ),
    );
  }
}
