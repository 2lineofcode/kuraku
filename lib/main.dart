// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ui' show AppExitResponse;

import 'package:ex_kit/ex.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';
import 'package:media_kit/src/player/native/utils/native_reference_holder.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';

import 'app/core/app_logging.dart';
import 'app/core/app_notification.dart';
import 'app/core/app_pin.dart';
import 'app/core/app_pref.dart';
import 'app/core/app_scroll_behavior.dart';
import 'app/core/app_setting.dart';
import 'app/core/app_startup.dart';
import 'app/core/app_translations.dart';
import 'app/data/database/_init_db.dart';
import 'app/data/database/app_backup.dart';
import 'app/modules/home/home_controller.dart';
import 'app/modules/home/page_chat/page_chat_controller.dart';
import 'app/modules/widgets/widget_style.dart';
import 'app/modules/widgets/widget_surfaces.dart';
import 'app/routes/app_pages.dart';
import 'app/utils/helper_toast.dart';
import 'app/utils/r18_updater.dart';
import 'app/utils/watch_session_tracker.dart';
import 'env.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppStartup(
    initialize: _initializeApp,
    child: const AppPinGate(child: JavIt()),
  ));
}

Future<void> _initializeApp() async {
  final sw = Stopwatch()..start();
  final settings = AppSettingService();
  await settings.setupDesktop();
  AppLog.logD('Startup window shown: ${sw.elapsedMilliseconds}ms');
  await _cleanupDanglingMediaKitPlayers();
  MediaKit.ensureInitialized();
  await hotKeyManager.unregisterAll();
  await Get.putAsync(() => settings.init(), permanent: true);
  AppLog.logD('Startup settings ready: ${sw.elapsedMilliseconds}ms');
  final database = await Get.putAsync(() => DBService().init(), permanent: true);
  await AppBackup.applyPending(settings.appPath, database.dbMain, settings.pref);
  AppLog.logD('Startup dependencies ready: ${sw.elapsedMilliseconds}ms');
}

Future<void> _initializeHotkeys() async {
  try {
    await Get.find<AppSettingService>().setupHotkey();
  } catch (e) {
    AppLog.logE('Hotkey setup failed: $e');
  }
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
    if (R18Updater.busy.value) {
      await HelperToast.info('Please wait for the R18 update to finish.'.tr);
      return false;
    }
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
    _lifecycle = AppLifecycleListener(
      onResume: Get.find<AppSettingService>().refreshTheme,
      onExitRequested: () async => await _flushBeforeExit() ? AppExitResponse.exit : AppExitResponse.cancel,
    );
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
        scrollBehavior: appScrollBehavior,
        enableLog: Env.logLvl == 'debug' ? true : false,
        title: Env.appName,
        translations: AppTranslations(),
        locale: Locale(AppPref.getAppLanguage()),
        fallbackLocale: AppTranslations.fallbackLocale,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: AppTranslations.languages.keys.map((code) => Locale(code)).toList(),
        initialRoute: AppPages.INITIAL,
        themeMode: AppPref.getAppTheme().resolve(),
        theme: AppStyle.theme(Brightness.light),
        darkTheme: AppStyle.theme(Brightness.dark),
        getPages: AppPages.routes,
        defaultTransition: Transition.fadeIn,
        debugShowCheckedModeBanner: false,
        onReady: () {
          Get.find<AppSettingService>().refreshTheme();
          unawaited(_initializeHotkeys());
          unawaited(_initializeNotifications());
          unawaited(_checkApplicationIsReady());
        },
      ),
    );
  }

  @override
  void onWindowFocus() {
    Get.find<AppSettingService>().refreshTheme();
  }

  @override
  void onWindowClose([int? windowId]) async {
    if (_closing) return;
    _closing = true;
    if (!await _flushBeforeExit()) {
      _closing = false;
      await HelperToast.error('Could not save pending activity or chat draft. Please try closing again.'.tr);
      return;
    }
    AppPref.setAppLastOpen(DateTime.now().toStringEx());
    AppLog.logD('onWindowClose');
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowEnterFullScreen([int? windowId]) {
    WidgetsBinding.instance.addPostFrameCallback((_) => Get.forceAppUpdate());
    WidgetsBinding.instance.ensureVisualUpdate();
    AppLog.logD('onWindowEnterFullScreen');
  }

  @override
  void onWindowLeaveFullScreen([int? windowId]) {
    WidgetsBinding.instance.addPostFrameCallback((_) => Get.forceAppUpdate());
    WidgetsBinding.instance.ensureVisualUpdate();
    AppLog.logD('onWindowLeaveFullScreen');
  }

  Future<void> _checkApplicationIsReady() async {
    if (Get.find<DBService>().dbR18 == null) {
      AppLog.logW('!!! Database `r18` not found...');
      AppConfirmDialog.show(
        isDismissible: false,
        title: Text('Ups'.tr),
        content: Text('Database `r18` not found, to use all features of this app, click download & install first'.tr),
        actions: [
          AppDialogAction(
            child: Text('Download & Install'.tr, style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              if (R18Updater.busy.value) return;
              Get.back();
              final home = Get.find<HomeController>();
              home.change(0, status: RxStatus.loading());
              try {
                await R18Updater.update(onStatus: (message) {
                  home.footerText.value = message;
                  home.loadingText.value = message;
                });
                home.change(200, status: RxStatus.success());
                await home.onRefreshAllContent();
                home.footerText.value = R18Updater.status.value;
              } catch (e) {
                home.change(200, status: RxStatus.success());
                await HelperToast.error('${R18Updater.status.value}\n$e');
              }
            },
          ),
        ],
      );
    } else {
      AppLog.logS('=== Application is ready, without any issue ===');
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
