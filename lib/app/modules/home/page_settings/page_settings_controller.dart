import 'package:dio/dio.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:process_run/process_run.dart' as shell;
import 'package:sqflite/sqlite_api.dart';

import '../../../core/app_color.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_setting.dart';
import '../../../core/const.dart';
import '../../../data/database/_init_db.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';

class PageSettingsController extends GetxController {
  final appSetting = Get.find<AppSettingService>();
  final dbR18Version = 0.obs;

  final totalLibrary = 0.obs;
  final totalVideos = 0.obs;
  final totalFilesize = Rx<num>(0);
  final lastRelapse = ''.obs;
  final r18TotalVideo = 0.obs;

  // ** config
  final tecDefaultPlayer = '${AppPref.getDefaultPlayer()}'.obs;
  final tecAppMaxColi = TextEditingController(text: AppPref.getAppMaxColi().toString());
  final tecPlayerSeekShort = TextEditingController(text: AppPref.getPlayerSeekShort().toString());
  final tecPlayerSeekMid = TextEditingController(text: AppPref.getPlayerSeekMid().toString());
  final tecPlayerSeekLong = TextEditingController(text: AppPref.getPlayerSeekLong().toString());

  // **
  final appMiniMode = false.obs;
  final applogText = ''.obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page settings ==> onInit called');
    dbR18Version.value = await Get.find<DBService>().dbR18.getVersion();
    totalLibrary.value = await DBLibrary.getCount();
    totalVideos.value = await DBVideos.getCount();
    totalFilesize.value = await DBVideos.getTotalFileSizeAllVideo() ?? 0;
    r18TotalVideo.value = await DBR18.getCountAllVideos();


    final current = Get.find<HomeController>().sideMenuWidth.value;
    if (current == 65) {
      appMiniMode.value = true;
    } else {
      appMiniMode.value = false;
    }
    
    final _last = await DBActivity.getAll(
      where: 'type = ?',
      whereArgs: [kActivityTypeRelapse],
      orderBy: 'created_at DESC',
    );
    if (_last.isNotEmpty) {
      lastRelapse.value = _last[0].createdAt?.reformatDate(to: 'MMM, d y HH:mm') ?? '';
    } else {
      lastRelapse.value = '-';
    }

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
    try {
      DateTime _getNextUpdate(DateTime lastUpdate, int intervalDays, DateTime today) {
        final diffDays = today.difference(lastUpdate).inDays;
        final times = diffDays ~/ intervalDays;
        return lastUpdate.add(Duration(days: times * intervalDays));
      }

      final lastUpdate = DateTime(2025, 9, 2);
      final intervalDays = 7;
      final today = DateTime.now();

      final lastUpdFromNow = _getNextUpdate(lastUpdate, intervalDays, today);
      final lastUpdFromNowStr = lastUpdFromNow.toStringEx(format: kYMd);

      final dbVersionDate = DateTime.parse(dbR18Version.string);
      final isOutdated = dbVersionDate.isBefore(lastUpdFromNow);


      ExAlert.adaptive(
        title: Text('Information', textAlign: TextAlign.left),
        content: VStack([
          12.heightBox,
          Text('Current Version\t: ${DateTime.parse(dbR18Version.string).toStringEx(format: kYMd)}').pOnly(bottom: 4),
          Text('Last Update\t\t\t\t\t\t\t: $lastUpdFromNowStr'),
          isOutdated
              ? Text(
                  '🔥 New Version Database R18 is avaiable',
                  textAlign: TextAlign.left,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ).pOnly(top: 24)
              : Text('🔥 You are using the latest version', textAlign: TextAlign.left).pOnly(top: 24),
        ]).p4(),
        actions: [
          isOutdated
              ? CupertinoDialogAction(
                  child: Text('Update', style: TextStyle(color: Vx.red500, fontSize: 13)),
                  onPressed: () async {
                    Get.back();
                    final appSetting = Get.find<AppSettingService>();
                    final home = Get.find<HomeController>();

                    final serverUrl = 'https://r18dotdev.s3.eu-west-1.wasabisys.com/dumps';
                    final outputFileName = 'r18dotdev_dump_$lastUpdFromNowStr.sql.gz';

                    await Dio().download(
                      '$serverUrl/$outputFileName',
                      '${appSetting.appPath}/$outputFileName',
                      onReceiveProgress: (received, total) {
                        final percent = ((received / total) * 100).toStringAsFixed(0);
                        home.footerText.value = 'DO NOT CLOSE APP | Downloading ($percent%) ...';
                      },
                    );

                    home.footerText.value = 'DO NOT CLOSE APP | Extracting...';
                    await shell.run('gunzip "${appSetting.appPath}/$outputFileName"');

                    home.footerText.value = 'DO NOT CLOSE APP | Importing... will take 4-15 minutes..';
                    await shell.run(
                      'python3 ${appSetting.appPath}/r18_to_javit.py -d "${appSetting.appPath}"',
                      onProcess: (process) async {
                        await process.exitCode.then((code) async {
                          if (code == 1) {
                            home.footerText.value = 'Task Failed. Please restart app...';
                            home.change(0, status: RxStatus.error('Task Failed. Please restart app...'));
                          }

                          if (code == 0) {
                            await HelperToast.success('Task Done. Please restart app...');
                            home.footerText.value = 'Task Done. Please restart app...';
                            home.change(0, status: RxStatus.error('Update completed. Please restart app...'));
                          }
                        });
                      },
                    );
                  },
                )
              : 0.heightBox,
        ],
      );

    } catch (e) {
      await HelperToast.error(e.toString());
    }
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

  Future<void> openAppLog() async {
    await Overlayment.show(
      context: Get.context,
      OverPanel(
        alignment: Alignment.centerLeft,
        width: 400,
        color: AppColor.selected,
        height: Get.height,
        child: VStack(
          [
            24.heightBox,
            'APP LOG'.text.bold.make().pOnly(bottom: 12),

            VStack([
              Obx(() => '$applogText'.selectableText.make()),
            ]).scrollVertical().expand(),
            
            // Spacer(),
            ExButtonText(
              label: 'Clear',
              height: 32,
              width: double.infinity,
              onPressed: () => applogText.value = '',
            ),
          ],
        ).p12(),
      ),
    );
  }
}
