import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/process_run.dart' as shell;
import 'package:sqflite/sqflite.dart';

import '../../../../env.g.dart';
import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_setting.dart';
import '../../../core/const.dart';
import '../../../data/database/_init_db.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_library.dart';
import '../../../data/database/db_r18.dart';
import '../../../data/database/db_videos.dart';
import '../../../utils/helper.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';
import '../home_panel/home_panel_log.dart';

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
  final tecDefaultSearchEngine = '${AppPref.getDefaultSearchEngine()}'.obs;
  final tecAppMaxColi = TextEditingController(text: AppPref.getAppMaxColi().toString());
  final tecPlayerSeekShort = TextEditingController(text: AppPref.getPlayerSeekShort().toString());
  final tecPlayerSeekMid = TextEditingController(text: AppPref.getPlayerSeekMid().toString());
  final tecPlayerSeekLong = TextEditingController(text: AppPref.getPlayerSeekLong().toString());

  // **
  final appMiniMode = false.obs;


  // ** storage
  final storageList = <StorageUsage>[].obs;
  final isLoadingStorage = false.obs;

  // ** app_log
  final appLogMode = false.obs;
  final appLogLevelSelected = 'ALL'.obs;
  final appLogKeyword = ''.obs;
  final appLogData = HomePanelAppLog.appLogRuntime;
  final tecAppLogFilter = TextEditingController();

  @override
  Future<void> onInit() async {
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();
    final r18db = Get.find<DBService>().dbR18;
    dbR18Version.value = r18db == null ? 0 : await r18db.getVersion();
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

    final _last = await DBActivity.getAllRelapse();
    
    if (_last.isNotEmpty) {
      lastRelapse.value = _last[0].createdAt?.reformatDate(to: 'MMM, d y HH:mm') ?? '';
    } else {
      lastRelapse.value = '-';
    }

    AppLog.logI('page settings ==> onInit called: ${sw.elapsedMilliseconds} ms');
  }

  @override
  void onClose() {
    tecAppMaxColi.dispose();
    tecPlayerSeekShort.dispose();
    tecPlayerSeekMid.dispose();
    tecPlayerSeekLong.dispose();
    tecAppLogFilter.dispose();
    super.onClose();
  }

  @override
  Future<void> onReady() async {
    super.onReady();
    await onRefreshStorage();
  }

  Future<void> onRefreshStorage() async {
    isLoadingStorage.value = true;
    try {
      storageList.value = await _scanStorage();
    } catch (e) {
      await HelperToast.error('Failed to read storage: $e');
    } finally {
      isLoadingStorage.value = false;
    }
  }

  Future<void> onOpenAppLog() async {
    appLogMode.value = true;
    appLogLevelSelected.value = 'ALL';
    appLogKeyword.value = '';
    tecAppLogFilter.clear();
    await Future.delayed(100.milliseconds);
  }

  List<AppLogRuntime> get filteredAppLogs {
    final selected = appLogLevelSelected.value.toUpperCase();
    final keyword = appLogKeyword.value.trim().toLowerCase();

    return appLogData.where((item) {
      final level = normalizeLogLevel(item.type);
      final passLevel = selected == 'ALL' || level == selected;
      if (!passLevel) return false;
      if (keyword.isEmpty) return true;

      final createdAt = (item.createdAt ?? '').toLowerCase();
      final content = (item.content ?? '').toLowerCase();
      final type = (item.type ?? '').toLowerCase();
      return createdAt.contains(keyword) || content.contains(keyword) || type.contains(keyword);
    }).toList();
  }

  String normalizeLogLevel(String? rawLevel) {
    final upper = (rawLevel ?? '').toUpperCase();
    if (upper == 'WARNING') return 'WARN';
    return upper;
  }

  void clearAppLog() {
    HomePanelAppLog.clear();
  }

  Future<void> onResetAll() async {
    await _openDialogConfirm(
      onYes: () async {
        Get.back();
        await Get.find<DBService>().deleteAllData();
        await Get.find<HomeController>().onRefreshAllContent();
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

      final dbVersionDate = dbR18Version.value > 0 ? DateTime.tryParse(dbR18Version.string) : null;
      final isOutdated = dbVersionDate == null || dbVersionDate.isBefore(lastUpdFromNow);

      ExAlert.adaptive(
        title: Text('Information', textAlign: TextAlign.left),
        content: VStack([
          12.heightBox,
          Text('Current Version\t: ${dbVersionDate?.toStringEx(format: kYMd) ?? '-'}').pOnly(bottom: 4),
          Text('Last Update\t\t\t\t\t\t\t: $lastUpdFromNowStr').pOnly(bottom: 4),
          !isOutdated ? Text('Next Update\t\t\t\t\t\t: ${lastUpdFromNow.add(7.days).toStringEx(format: kYMd)}').pOnly(bottom: 4) : 0.heightBox,
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
                    final dbService = Get.find<DBService>();
                    final dio = Dio();

                    final serverUrl = Env.r18ServerUrl;
                    String? outputFileName;
                    String? gzPath;
                    DioException? lastDownloadError;

                    for (var i = 0; i < 8; ) {
                      final candidateDate = lastUpdFromNow.subtract(Duration(days: i * 7));
                      final candidateDateStr = candidateDate.toStringEx(format: kYMd);
                      outputFileName = 'r18dotdev_dump_$candidateDateStr.sql.gz';
                      gzPath = '${appSetting.appPath}/$outputFileName';

                      try {
                        await dio.download(
                          '$serverUrl/$outputFileName',
                          gzPath,
                          onReceiveProgress: (received, total) {
                            final percent = total > 0 ? ((received / total) * 100).toStringAsFixed(0) : '0';
                            home.footerText.value = 'DO NOT CLOSE APP | Downloading ($percent%) ...';
                          },
                        );
                        break;
                      } on DioException catch (e) {
                        lastDownloadError = e;
                        final statusCode = e.response?.statusCode ?? 0;
                        if (statusCode == 404) {
                          await HelperToast.error('Version for $candidateDateStr not found, try update tommorow.');
                          return;
                        }
                        rethrow;
                      }
                    }

                    if (gzPath == null || File(gzPath).existsSync() == false) {
                      throw Exception('R18 dump not found on server (tried last 8 weekly versions). Last error: ${lastDownloadError?.message ?? 'unknown'}');
                    }

                    home.footerText.value = 'DO NOT CLOSE APP | Extracting...';
                    await shell.run('gunzip "$gzPath"');

                    // Release file lock so Python can rotate old r18*.db safely.
                    try {
                      await dbService.dbR18?.close();
                      dbService.dbR18 = null;
                    } catch (_) {}

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

  // ────────────────────────────────────────────────────────────────
  // Storage helpers
  // ────────────────────────────────────────────────────────────────
  Future<List<StorageUsage>> _scanStorage() async {
    final List<StorageUsage> result = [];

    final primary = await _readUsage(
      appSetting.appPath,
      label: Platform.isMacOS
          ? 'Macintosh HD'
          : Platform.isWindows && appSetting.appPath.length >= 2
              ? appSetting.appPath.substring(0, 2)
              : 'System Drive',
      isExternal: false,
    );
    if (primary != null) {
      result.add(primary);
    }

    final externalMounts = await _discoverExternalMounts();
    for (final mount in externalMounts) {
      final info = await _readUsage(
        mount,
        label: _labelFromPath(mount),
        isExternal: true,
      );
      if (info != null) {
        result.add(info);
      }
    }

    return result;
  }

  Future<StorageUsage?> _readUsage(
    String path, {
    required String label,
    required bool isExternal,
  }) async {
    try {
      if (Platform.isWindows) {
        final usage = await _readUsageWindows(path);
        if (usage == null) return null;
        return StorageUsage(
          label: label,
          path: path,
          totalBytes: usage['total'] ?? 0,
          freeBytes: usage['free'] ?? 0,
          isExternal: isExternal,
        );
      } else {
        final usage = await _readUsagePosix(path);
        if (usage == null) return null;
        return StorageUsage(
          label: label,
          path: path,
          totalBytes: usage['total'] ?? 0,
          freeBytes: usage['free'] ?? 0,
          isExternal: isExternal,
        );
      }
    } catch (e) {
      AppLog.logD('Storage usage read failed for $path: $e');
      return null;
    }
  }

  Future<Map<String, int>?> _readUsagePosix(String path) async {
    final result = await Process.run('df', ['-k', path]);
    if (result.exitCode != 0) return null;
    final lines = result.stdout.toString().trim().split('\n');
    if (lines.length < 2) return null;
    final parts = lines[1].split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length < 4) return null;

    final totalKb = int.tryParse(parts[1]);
    final availableKb = int.tryParse(parts[3]);
    if (totalKb == null || availableKb == null) return null;

    return {
      'total': totalKb * 1024,
      'free': availableKb * 1024,
    };
  }

  Future<Map<String, int>?> _readUsageWindows(String path) async {
    // fsutil output is stable across Windows versions
    final drive = path.length >= 2 ? path.substring(0, 2) : path;
    final result = await Process.run('fsutil', ['volume', 'diskfree', drive]);
    if (result.exitCode != 0) return null;

    final freeMatch = RegExp(r'Total # of avail free bytes\s*:\s*(\d+)').firstMatch(result.stdout.toString());
    final totalMatch = RegExp(r'Total # of bytes\s*:\s*(\d+)').firstMatch(result.stdout.toString());
    if (freeMatch == null || totalMatch == null) return null;

    return {
      'free': int.tryParse(freeMatch.group(1) ?? '') ?? 0,
      'total': int.tryParse(totalMatch.group(1) ?? '') ?? 0,
    };
  }

  Future<List<String>> _discoverExternalMounts() async {
    final mounts = <String>[];

    if (Platform.isMacOS) {
      final dir = Directory('/Volumes');
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is! Directory) continue;
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          if (name == 'Macintosh HD' || name == 'Macintosh HD - Data') continue;
          mounts.add(entity.path);
        }
      }
    } else if (Platform.isLinux) {
      for (final base in ['/media', '/mnt']) {
        final dir = Directory(base);
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(recursive: false)) {
          if (entity is Directory) {
            mounts.add(entity.path);
          }
        }
      }
    } else if (Platform.isWindows) {
      for (var codeUnit = 'D'.codeUnitAt(0); codeUnit <= 'Z'.codeUnitAt(0); codeUnit++) {
        final letter = String.fromCharCode(codeUnit);
        final drive = '$letter:\\\\';
        if (Directory(drive).existsSync()) {
          mounts.add(drive);
        }
      }
    }

    return mounts;
  }

  String _labelFromPath(String path) {
    if (Platform.isWindows) {
      return path.substring(0, 2);
    }
    final base = p.basename(path);
    return base.isNotEmpty ? base : path;
  }
}

class StorageUsage {
  StorageUsage({
    required this.label,
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
    required this.isExternal,
  });

  final String label;
  final String path;
  final int totalBytes;
  final int freeBytes;
  final bool isExternal;

  double get usedPct => totalBytes > 0 ? ((totalBytes - freeBytes) / totalBytes) * 100 : 0;
  double get freePct => totalBytes > 0 ? (freeBytes / totalBytes) * 100 : 0;
}
