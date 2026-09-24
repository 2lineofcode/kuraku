// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ui' show AppExitResponse;

import 'package:dio/dio.dart';
import 'package:ex_kit/ex.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';
import 'package:media_kit/src/player/native/utils/native_reference_holder.dart';
import 'package:process_run/process_run.dart' as shell;
import 'package:toastification/toastification.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/core/app_logging.dart';
import 'app/core/app_notification.dart';
import 'app/core/app_pref.dart';
import 'app/core/app_setting.dart';
import 'app/core/app_startup.dart';
import 'app/core/const.dart';
import 'app/data/database/_init_db.dart';
import 'app/modules/home/home_controller.dart';
import 'app/modules/home/page_chat/page_chat_controller.dart';
import 'app/routes/app_pages.dart';
import 'app/utils/helper_toast.dart';
import 'app/utils/watch_session_tracker.dart';
import 'env.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppStartup(initialize: _initializeApp, child: const JavIt()));
}

Future<void> _initializeApp() async {
  final sw = Stopwatch()..start();
  final settings = AppSettingService();
  await settings.setupDesktop();
  AppLog.logD('Startup window shown: ${sw.elapsedMilliseconds}ms');
  await _cleanupDanglingMediaKitPlayers();
  MediaKit.ensureInitialized();
  VideoPlayerMediaKit.ensureInitialized(macOS: true);
  await hotKeyManager.unregisterAll();
  await Get.putAsync(() => settings.init(), permanent: true);
  AppLog.logD('Startup settings ready: ${sw.elapsedMilliseconds}ms');
  await Get.putAsync(() => DBService().init(), permanent: true);
  AppLog.logD('Startup dependencies ready: ${sw.elapsedMilliseconds}ms');
}

class JavIt extends StatefulWidget {
  const JavIt({super.key});

  @override
  State<JavIt> createState() => _JavItState();
}

class _JavItState extends State<JavIt> with WindowListener {
  AppLifecycleListener? _lifecycle;
  bool _closing = false;

  Future<bool> _flushChat() async {
    if (Get.isRegistered<PageChatController>() && !Get.isPrepared<PageChatController>()) {
      final chat = Get.find<PageChatController>();
      await chat.stopResponse();
      return chat.flushDraft();
    }
    return true;
  }

  Future<bool> _flushBeforeExit() async {
    try {
      if (!await _flushChat()) return false;
      await WatchSessionTracker.flushAll();
      return true;
    } catch (e) {
      AppLog.logE('Could not save pending activity before exit: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _lifecycle = AppLifecycleListener(onExitRequested: () async => await _flushBeforeExit() ? AppExitResponse.exit : AppExitResponse.cancel);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: GetMaterialApp(
        enableLog: Env.logLvl == 'debug' ? true : false,
        title: Env.appName,
        initialRoute: AppPages.INITIAL,
        themeMode: AppPref.getAppDarkMode() ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
          textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Vx.blue300)),
        ),
        getPages: AppPages.routes,
        defaultTransition: Transition.fadeIn,
        debugShowCheckedModeBanner: false,
        onReady: () {
          unawaited(_initializeNotifications());
          unawaited(_checkApplicationIsReady());
        },
      ),
    );
  }

  @override
  void onWindowClose([int? windowId]) async {
    if (_closing) return;
    _closing = true;
    if (!await _flushBeforeExit()) {
      _closing = false;
      await HelperToast.error('Could not save pending activity or chat draft. Please try closing again.');
      return;
    }
    AppPref.setAppLastOpen(DateTime.now().toStringEx());
    AppLog.logD('onWindowClose');
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowEnterFullScreen([int? windowId]) {
    Get.forceAppUpdate();
    AppLog.logD('onWindowEnterFullScreen');
  }

  @override
  void onWindowLeaveFullScreen([int? windowId]) {
    Get.forceAppUpdate();
    AppLog.logD('onWindowLeaveFullScreen');
  }

  Future<void> _checkApplicationIsReady() async {
    var files = Glob('r18*.db').listSync(root: Get.find<AppSettingService>().appPath);
    files.sort((a, b) => b.path.compareTo(a.path));
    if (files.isEmpty) {
      AppLog.logW('!!! Database `r18` not found...');
      ExAlert.adaptive(
        isDismissible: false,
        title: Text('Ups'),
        content: Text('Database `r18` not found, to use all features of this app, click download & install first'),
        actions: [
          CupertinoDialogAction(
            child: Text('Download & Install', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              final sw = Stopwatch()..start();
              AppLog.logI('!!! Start Downloading R18 database & Install...');

              final appSetting = Get.find<AppSettingService>();
              final home = Get.find<HomeController>();
              Get.back();

              home.change(0, status: RxStatus.loading());
              home.loadingText.value = 'Preparing...';

              // ** download
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

                final serverUrl = Env.r18ServerUrl;
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
                      }

                      if (code == 0) {
                        await HelperToast.success('Task Done. Please restart app...');
                        home.footerText.value = 'Task Done. Please restart app...';
                        home.loadingText.value = 'Task Done \n\n Please restart app...';
                      }

                      home.change(0, status: RxStatus.error('Update completed. Please restart app...'));
                    });
                  },
                );

                AppLog.logI('!!! Downloading R18 database & Install completed: ${sw.elapsed.inSeconds} seconds');
              } catch (e) {
                AppLog.logE('R18 setup failed: $e');
              }
            },
          ),
        ],
      );
    } else {
      AppLog.logS('=== 💎 Application is ready, without any issue 💎 ===');
    }
  }
}

Future<void> _initializeNotifications() async {
  try {
    await AppNotification.initialize();
    await _requestNotificationPermissions();
  } catch (e, stackTrace) {
    AppLog.logE('Notification setup failed: $e\n$stackTrace');
  }
}

Future<void> _requestNotificationPermissions() async {
  final isGranted = await AppNotification.requestPermissions();
  if (isGranted == true) {
    AppLog.logI('Notification permissions granted');
  } else {
    AppLog.logI('Notification permissions denied');
  }
}

Future<void> _cleanupDanglingMediaKitPlayers() async {
  if (!kDebugMode) return;
  try {
    NativeLibrary.ensureInitialized();
    NativeReferenceHolder.ensureInitialized((references) {
      if (references.isEmpty) {
        return;
      }
      final mpv = generated.MPV(ffi.DynamicLibrary.open(NativeLibrary.path));
      final quitPtr = 'quit'.toNativeUtf8();
      try {
        for (final reference in references) {
          if (reference == ffi.nullptr) continue;
          final ctx = reference.cast<generated.mpv_handle>();
          mpv.mpv_set_wakeup_callback(ctx, ffi.nullptr, ffi.nullptr);
          mpv.mpv_command_string(ctx, quitPtr.cast());
        }
      } finally {
        calloc.free(quitPtr);
      }
    });
  } catch (e, stackTrace) {
    AppLog.logE('Failed to cleanup media_kit references: $e');
    AppLog.logE('$stackTrace');
  }
}
