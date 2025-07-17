import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../env.g.dart';
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
}
