import 'dart:async';
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
import '../modules/home/home_panel/home_panel_cart.dart';
import '../modules/home/home_panel/home_panel_log.dart';
import '../modules/home/home_panel/home_panel_playlist.dart';
import '../modules/home/home_panel/home_panel_relapse.dart';
import '../modules/home/page_download/page_download_controller.dart';
import '../modules/home/page_settings/page_settings_controller.dart';
import '../modules/home/page_tools/page_tools_controller.dart';
import '../routes/app_pages.dart';
import '../utils/helper_opener.dart';
import '../utils/local_semantic_worker.dart';
import 'app_identity.dart';
import 'app_logging.dart';
import 'app_pref.dart';


class AppSettingService extends GetxService {
  late String appPath;
  late String bundledAssetsPath = Platform.isMacOS
      ? join(dirname(dirname(Platform.resolvedExecutable)), 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets')
      : join(dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets');
  late GetSecureStorage pref;
  Timer? _themeTimer;

  void refreshTheme() {
    _themeTimer?.cancel();
    final theme = AppPref.getAppTheme();
    final now = DateTime.now();
    final mode = theme.resolve(now);
    if (Get.rootController.themeMode != mode) Get.changeThemeMode(mode);
    if (theme != AppTheme.schedule) return;
    final next = DateTime(now.year, now.month, now.day + (now.hour >= 17 ? 1 : 0), now.hour < 6 || now.hour >= 17 ? 6 : 17);
    _themeTimer = Timer(next.difference(now), refreshTheme);
  }

  Future<AppSettingService> init() async {
    final directory = await getApplicationDocumentsDirectory();
    appPath = join(directory.path, AppIdentity.displayName);
    pref = GetSecureStorage(container: Env.appName.toLowerCase(), password: Env.appName, path: appPath);
    await pref.initStorage;


    await setupAppPref();
    return this;
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ checkAndApplyDefaultAppConfig
  // ────────────────────────────────────────────────────────────────
  Future<void> setupAppPref() async {
    // app
    await pref.writeIfNull('_kAppIsDarkMode', true);
    await pref.writeIfNull('_kAppLanguage', 'en');
    await pref.writeIfNull('_kAppFirstOpen', DateTime.now().toStringEx());
    await pref.writeIfNull('_kAppLastOpen', DateTime.now().toStringEx());
    await pref.writeIfNull('_kAppHideSideMenu', true);


    // download
    await pref.writeIfNull('_kDownloadPath', '');
    await pref.writeIfNull('_kDownloadLang', 'en');

    // home_sec
    await pref.writeIfNull('_kHomeOrderList', <String>[
      AppPref.homeSecNewRelease,
      AppPref.homeSecRecommendation,
      AppPref.homeSecRandom,
      AppPref.homeSecMostWatch,
      AppPref.homeSecFavorite,
      AppPref.homeSecNewAdd,
      AppPref.homeSecNeverWatch,
      AppPref.homeSecOldest,
      AppPref.homeSecImageAlbums,
    ]);
    await pref.writeIfNull(AppPref.homeSecNewRelease, true);
    await pref.writeIfNull(AppPref.homeSecRecommendation, true);
    await pref.writeIfNull(AppPref.homeSecRandom, true);
    await pref.writeIfNull(AppPref.homeSecMostWatch, true);
    await pref.writeIfNull(AppPref.homeSecFavorite, true);
    await pref.writeIfNull(AppPref.homeSecNewAdd, true);
    await pref.writeIfNull(AppPref.homeSecNeverWatch, true);
    await pref.writeIfNull(AppPref.homeSecOldest, true);
    await pref.writeIfNull(AppPref.homeSecImageAlbums, true);

    final storedHomeOrder = pref.read<List>('_kHomeOrderList');
    final homeOrder = storedHomeOrder == null ? <String>[] : List<String>.from(storedHomeOrder);
    if (!homeOrder.contains(AppPref.homeSecImageAlbums)) {
      homeOrder.add(AppPref.homeSecImageAlbums);
      await pref.write('_kHomeOrderList', homeOrder);
    }
    if (homeOrder.contains(AppPref.homeSecRecommendation) == false) {
      homeOrder.insert(1, AppPref.homeSecRecommendation);
      await pref.write('_kHomeOrderList', homeOrder);
    }
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ setup layout desktop
  // ────────────────────────────────────────────────────────────────
  Future<void> setupDesktop() async {
    final idealSize = Size(746, 700);
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      title: AppIdentity.displayName,
      size: idealSize,
      minimumSize: idealSize,
      maximumSize: Platform.isWindows ? idealSize : null,
      titleBarStyle: Platform.isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
      alwaysOnTop: Platform.isWindows ? true : false,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
    await windowManager.show();
    await windowManager.focus();
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ hotkey
  // ────────────────────────────────────────────────────────────────
  bool _handleKeyboardShortcutsShortcut(KeyEvent event) {
    if (event is! KeyDownEvent || !const SingleActivator(LogicalKeyboardKey.slash, meta: true).accepts(event, HardwareKeyboard.instance)) return false;
    unawaited(HelperOpener.openKeyboardShortcuts());
    return true;
  }

  bool _handleSearchShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final commandF = const SingleActivator(LogicalKeyboardKey.keyF, meta: true).accepts(event, HardwareKeyboard.instance);
    if (!commandF && !const SingleActivator(LogicalKeyboardKey.slash).accepts(event, HardwareKeyboard.instance)) return false;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context?.widget is EditableText || context?.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    if (!Get.isRegistered<HomeController>()) return false;
    final home = Get.find<HomeController>();
    if (commandF && home.currentMenuSelected.value == kMenuChat && (Get.currentRoute == Routes.HOME || Get.currentRoute == Routes.ROOT)) return false;
    home.focusTopNavSearch();
    return true;
  }

  @override
  void onClose() {
    _themeTimer?.cancel();
    LocalSemanticWorker.cancelSetup();
    LocalSemanticWorker.stop();
    HardwareKeyboard.instance.removeHandler(_handleKeyboardShortcutsShortcut);
    HardwareKeyboard.instance.removeHandler(_handleSearchShortcut);
    super.onClose();
  }

  Future<void> setupHotkey() async {
    HardwareKeyboard.instance.removeHandler(_handleKeyboardShortcutsShortcut);
    HardwareKeyboard.instance.removeHandler(_handleSearchShortcut);
    HardwareKeyboard.instance.addHandler(_handleSearchShortcut);
    HardwareKeyboard.instance.addHandler(_handleKeyboardShortcutsShortcut);
    void _logHotkeyError(String action, Object e, StackTrace stackTrace) {
      AppLog.logE('Hotkey action failed [$action]: $e');
      AppLog.logE('$stackTrace');
    }

    HotKey _hotKeyEsc = HotKey(key: PhysicalKeyboardKey.escape, modifiers: [], scope: HotKeyScope.inapp);
    HotKey _hotKeyE = HotKey(key: PhysicalKeyboardKey.keyE, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyP = HotKey(key: PhysicalKeyboardKey.keyP, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyL = HotKey(key: PhysicalKeyboardKey.keyL, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyR = HotKey(key: PhysicalKeyboardKey.keyR, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyD = HotKey(key: PhysicalKeyboardKey.keyD, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyT = HotKey(key: PhysicalKeyboardKey.keyT, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyShiftT = HotKey(key: PhysicalKeyboardKey.keyT, modifiers: [HotKeyModifier.meta, HotKeyModifier.shift], scope: HotKeyScope.inapp);
    HotKey _hotKeyB = HotKey(key: PhysicalKeyboardKey.keyB, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyDot = HotKey(key: PhysicalKeyboardKey.period, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);

    HotKey _hotKey1 = HotKey(key: PhysicalKeyboardKey.digit1, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey2 = HotKey(key: PhysicalKeyboardKey.digit2, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey3 = HotKey(key: PhysicalKeyboardKey.digit3, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey4 = HotKey(key: PhysicalKeyboardKey.digit4, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKey5 = HotKey(key: PhysicalKeyboardKey.digit5, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);
    HotKey _hotKeyComma = HotKey(key: PhysicalKeyboardKey.comma, modifiers: [HotKeyModifier.meta], scope: HotKeyScope.inapp);

    await hotKeyManager.register(_hotKeyEsc, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyEsc Pressed');
      try { 
        if (Get.currentRoute == Routes.HOME || Get.currentRoute == Routes.ROOT) {
          Get.back(); return;
        }

        if (Overlayment.count > 0)  Overlayment.dismissLast();

      } catch (e, stackTrace) {
        _logHotkeyError('esc', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyE, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyE Pressed');
      try { HomePanelCart.open(); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+e', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyP, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyP Pressed');
      try { HomePanelPlaylist.open(); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+p', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyL, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyL Pressed');
      try { HomePanelAppLog.open(); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+l', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyR, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyR Pressed');
      try { Get.find<HomeController>().onRefreshAllContent(); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+r', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyD, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyD Pressed');
      try { Get.find<PageDownloadController>().openDialogDownload(); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+d', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyT, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyT Pressed');
      try { Get.find<PageToolsController>().addTodo(); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+t', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyShiftT, keyUpHandler: (hotKey) async {
      try { await Get.find<PageSettingsController>().setTheme(Get.isDarkMode ? AppTheme.light : AppTheme.dark); }
      catch (e, stackTrace) {
        _logHotkeyError('meta+shift+t', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyB, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyB Pressed');
      final current = Get.find<HomeController>().sideMenuWidth.value;
      if (current == 65) {
        Get.find<HomeController>().sideMenuWidth.value = 180;
        AppPref.setAppHideSideMenu(false);
      } else {
        Get.find<HomeController>().sideMenuWidth.value = 65;
        AppPref.setAppHideSideMenu(true);
      }
    });

    await hotKeyManager.register(_hotKeyDot, keyUpHandler: (hotKey) async {
      // AppLog.logD('hotKeyDot Pressed');
      try { await HomePanelRelapse.open(); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+.', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKey1, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKey1 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuHome); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+1', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKey2, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKey2 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuSearch); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+2', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKey3, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKey3 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuExplore); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+3', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKey4, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKey4 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuDownload); }
      catch (e, stackTrace) {
        _logHotkeyError('meta+4', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKey5, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKey5 Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuTools); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+5', e, stackTrace);
      }
    });

    await hotKeyManager.register(_hotKeyComma, keyUpHandler: (hotKey) {
      // AppLog.logD('hotKeyComma Pressed');
      try { Get.find<HomeController>().onMenuChange(kMenuSetting); } 
      catch (e, stackTrace) {
        _logHotkeyError('meta+,', e, stackTrace);
      }
    });

  }
}
