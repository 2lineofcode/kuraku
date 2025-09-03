import 'package:dio/dio.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:process_run/process_run.dart' as shell;
import 'package:sqflite/sqlite_api.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_setting.dart';
import '../../../core/const.dart';
import '../../../data/database/_init_db.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_relapse.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';

class PageSettingsController extends GetxController {
  final appSetting = Get.find<AppSettingService>();
  final dbR18Version = 0.obs;

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
    dbR18Version.value = await Get.find<DBService>().dbR18.getVersion();
    totalLibrary.value = await DBLibrary.getCount();
    totalVideos.value = await DBVideos.getCount();
    r18TotalVideo.value = await DBR18.getCountAllVideos();
    lastRelapse.value = await DBRelapse.getLastRelapse();
    if (lastRelapse.value.isNotBlank) {
      lastRelapse.value = lastRelapse.value.ago(format: kYMd);
    }
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
    try {
      _getNextUpdate(DateTime lastUpdate, int intervalDays, DateTime today) {
        final diffDays = today.difference(lastUpdate).inDays;
        final times = diffDays ~/ intervalDays;
        final lastUpdateFromNow = lastUpdate.add(Duration(days: times * intervalDays));
        return lastUpdateFromNow;
      }

      final lastUpdate = DateTime(2025, 9, 2);
      final intervalDays = 7;
      final today = DateTime.now();

      final lastUpdFromNow = _getNextUpdate(lastUpdate, intervalDays, today);
      final lastUpdFromNowStr = lastUpdFromNow.toStringEx(format: kYMd);

      final isOutdated = lastUpdFromNow.isBefore(DateTime.parse(dbR18Version.string));

      ExAlert.adaptive(
        title: Text('Information', textAlign: TextAlign.left),
        content: VStack([
          12.heightBox,
          Text('Current Version\t: ${DateTime.parse(dbR18Version.string).toStringEx(format: kYMd)}').pOnly(bottom: 4),
          Text('Last Update\t\t\t\t\t\t\t: $lastUpdFromNowStr'),
          isOutdated ? 0.heightBox : Text('You using lastest version 🔥').pOnly(top: 24),
        ]).p4(),
        actions: [
          isOutdated
              ? CupertinoDialogAction(
                  child: Text('Update', style: TextStyle(color: Vx.red500, fontSize: 13)),
                  onPressed: () async {
                    Get.back();
                    final appSetting = Get.find<AppSettingService>();
                    final home = Get.find<HomeController>();

                    home.change(0, status: RxStatus.loading());
                    home.loadingText.value = 'Preparing...';

                    final serverUrl = 'https://r18dotdev.s3.eu-west-1.wasabisys.com/dumps';
                    final outputFileName = 'r18dotdev_dump_$lastUpdFromNowStr.sql.gz';

                    await Dio().download(
                      '$serverUrl/$outputFileName',
                      '${appSetting.appPath}/$outputFileName',
                      onReceiveProgress: (received, total) {
                        final percent = ((received / total) * 100).toStringAsFixed(0);
                        home.footerText.value = 'DO NOT CLOSE APP | Downloading ($percent%) ...';
                        home.loadingText.value = 'DO NOT CLOSE APP \n\n Downloading ($percent%) ...';
                      },
                    );

                    home.footerText.value = 'DO NOT CLOSE APP | Extracting...';
                    home.loadingText.value = 'DO NOT CLOSE APP \n\n Extracting...';
                    await shell.run('gunzip "${appSetting.appPath}/$outputFileName"');

                    home.footerText.value = 'DO NOT CLOSE APP | Importing... will take 4-15 minutes..';
                    home.loadingText.value = 'DO NOT CLOSE APP \n\n Importing... will take 4-15 minutes..\n converting psql into sqlite3';
                    await shell.run(
                      'python3 ${appSetting.appPath}/r18_to_javit.py -d "${appSetting.appPath}"',
                      onProcess: (process) async {
                        await process.exitCode.then((code) async {
                          if (code == 1) {
                            home.footerText.value = 'Task Failed. Please restart app...';
                            home.change(0, status: RxStatus.error());
                          }

                          if (code == 0) {
                            await HelperToast.success('Task Done. Please restart app...');
                            home.footerText.value = 'Task Done. Please restart app...';
                            home.loadingText.value = 'Task Done \n\n Please restart app...';
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
}
