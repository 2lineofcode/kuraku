import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../env.g.dart';
import '../modules/home/home_controller.dart';
import 'const.dart';

/// handy call sharedpref
final pref = GetStorage();

class AppSettingService extends GetxService {
  late Directory appDir;

  @override
  Future<void> onInit() async {
    super.onInit();
    appDir = await getApplicationDocumentsDirectory();
    await checkAndApplyDefaultAppConfig();
    await initForDesktop();
    await hotkey();
  }

  /// ------------------------------------------------------------------------
  /// ! setup default app config [for new user]
  /// ------------------------------------------------------------------------
  Future<void> checkAndApplyDefaultAppConfig() async {
    if (!pref.hasData(kIsDarkMode)) {
      await pref.write(kIsDarkMode, true);
      logI('-- CONFIG CREATED --');
    }
  }

  /// ------------------------------------------------------------------------
  /// ! initForDesktop
  /// ------------------------------------------------------------------------
  Future<void> initForDesktop() async {
    final idealSize = Size(690, 700);
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = WindowOptions(
      title: Env.appName,
      size: idealSize,
      minimumSize: kReleaseMode ? idealSize : null,
      maximumSize: Platform.isWindows ? idealSize : null,
      titleBarStyle: Platform.isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
      alwaysOnTop: Platform.isWindows ? true : false,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<void> hotkey() async {
    HotKey _hotKeyEsc = HotKey(key: PhysicalKeyboardKey.escape, modifiers: [], scope: HotKeyScope.inapp);
    HotKey _hotKeyComma = HotKey(key: PhysicalKeyboardKey.comma, modifiers: [], scope: HotKeyScope.inapp);
    HotKey _hotKeyS = HotKey(key: PhysicalKeyboardKey.keyS, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyE = HotKey(key: PhysicalKeyboardKey.keyE, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);

    await hotKeyManager.register(_hotKeyEsc, keyDownHandler: (hotKey) {
      try {
        Get.back();
        Overlayment.dismissLast();
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyComma, keyDownHandler: (hotKey) {
      try {
        Get.back();
        Overlayment.dismissLast();
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyS, keyDownHandler: (hotKey) {
      try {
        Get.find<HomeController>().onMenuChange(kMenuSearch);
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyE, keyDownHandler: (hotKey) {
      try {
        Get.find<HomeController>().onMenuChange(kMenuExplore);
      } catch (_) {}
    });
  }
}
