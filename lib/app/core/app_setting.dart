import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:overlayment/overlayment.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../env.g.dart';
import '../modules/home/home_controller.dart';
import '../modules/home/page_download/page_download_controller.dart';
import 'app_logging.dart';
import 'const.dart';


class AppSettingService extends GetxService {
  late String appPath;
  late GetSecureStorage pref;

  @override
  Future<void> onReady() async {
    super.onReady();
    await getApplicationDocumentsDirectory().then((s) {
      appPath = join(s.path, Env.appName);
      pref = GetSecureStorage(container: Env.appName, password: Env.appName, path: appPath);
    });


    await setupDesktop();
    await setupStorage();
    await setupExternalFiles();
    await setupHotkey();
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ checkAndApplyDefaultAppConfig
  // ────────────────────────────────────────────────────────────────
  Future<void> setupStorage() async {    
    await pref.writeIfNull(kIsDarkMode, true);
    await pref.writeIfNull(kCurrentLanguage, 'en');
    await pref.writeIfNull(kFirstOpenApp, DateTime.now().toStringEx());
    await pref.writeIfNull(kLastOpenApp, DateTime.now().toStringEx());
    await pref.writeIfNull(kDownloadDir, await getDownloadsDirectory());
    await pref.writeIfNull(kDownloadLang, 'en');
    
    await pref.write(kLastOpenApp, DateTime.now().toStringEx());
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ setup layout desktop
  // ────────────────────────────────────────────────────────────────
  Future<void> setupDesktop() async {
    final idealSize = Size(702, 650);
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = WindowOptions(
      title: Env.appName,
      size: idealSize,
      minimumSize: idealSize,
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

  //
  Future<void> setupExternalFiles() async {
    final assetFiles = ['psql2sqlite.py', 'dl'];

    for (final fileName in assetFiles) {
      final filePath = '$appPath/$fileName';
      final file = File(filePath);

      if (await file.exists()) continue;

      try {
        final byteData = await rootBundle.load('assets/$fileName');
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );

        await file.writeAsBytes(bytes);
      } catch (_) {}
    }
  }


  // ────────────────────────────────────────────────────────────────
  // ⵌ hotkey
  // ────────────────────────────────────────────────────────────────
  Future<void> setupHotkey() async {
    HotKey _hotKeyEsc = HotKey(key: PhysicalKeyboardKey.escape, modifiers: [], scope: HotKeyScope.inapp);
    HotKey _hotKeyX = HotKey(key: PhysicalKeyboardKey.keyX, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyR = HotKey(key: PhysicalKeyboardKey.keyR, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyD = HotKey(key: PhysicalKeyboardKey.keyD, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);

    HotKey _hotKey1 = HotKey(key: PhysicalKeyboardKey.digit1, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey2 = HotKey(key: PhysicalKeyboardKey.digit2, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey3 = HotKey(key: PhysicalKeyboardKey.digit3, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey4 = HotKey(key: PhysicalKeyboardKey.digit4, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey5 = HotKey(key: PhysicalKeyboardKey.digit5, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);

    HotKey _hotKeyArrowR = HotKey(key: PhysicalKeyboardKey.arrowRight, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.inapp);
    HotKey _hotKeyArrowL = HotKey(key: PhysicalKeyboardKey.arrowLeft, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.inapp);


    await hotKeyManager.register(_hotKeyEsc, keyUpHandler: (hotKey) {
      AppLog.logD('hotKeyEsc Pressed');
      try { Get.back(); Overlayment.dismissLast();
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyX, keyUpHandler: (hotKey) {
      AppLog.logD('hotKeyX Pressed');
      try { Get.back(); Overlayment.dismissLast();
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyR, keyUpHandler: (hotKey) {
      AppLog.logD('hotKeyR Pressed');
      try { Get.find<HomeController>().onRefreshAllContent();
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyD, keyUpHandler: (hotKey) {
      AppLog.logD('hotKeyD Pressed');
      try { Get.find<PageDownloadController>().openDialogDownload();
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKey1, keyUpHandler: (hotKey) {
      AppLog.logD('hotKey1 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuHome);
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKey2, keyUpHandler: (hotKey) {
      AppLog.logD('hotKey2 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuSearch);
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKey3, keyUpHandler: (hotKey) {
      AppLog.logD('hotKey3 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuExplore);
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKey4, keyUpHandler: (hotKey) {
      AppLog.logD('hotKey4 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuDownload);
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKey5, keyUpHandler: (hotKey) {
      AppLog.logD('hotKey5 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuSetting);
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyArrowR, keyUpHandler: (hotKey) {
      AppLog.logD('hotKeyArrowR Pressed');
      try { Get.find<PageDownloadController>().onNextPage();
      } catch (_) {}
    });

    await hotKeyManager.register(_hotKeyArrowL, keyUpHandler: (hotKey) {
      AppLog.logD('hotKeyArrowL Pressed');
      try { Get.find<PageDownloadController>().onPreviousPage();
      } catch (_) {}
    });
  }
}
