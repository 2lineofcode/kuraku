import 'package:get/get.dart';

import 'app_setting.dart';

mixin AppPref {
  static final _pref = Get.find<AppSettingService>().pref;

  // ** [app]
  static bool getAppIsDarkMode() => _pref.read(_kAppIsDarkMode) ?? true;
  static void setAppIsDarkMode(bool value) => _pref.write(_kAppIsDarkMode, value);

  static String getAppLanguage() => _pref.read(_kAppLanguage) ?? 'en';
  static void setAppLanguage(String value) => _pref.write(_kAppLanguage, value);

  static String getAppFirstOpen() => _pref.read(_kAppFirstOpen) ?? '';
  static void setAppFirstOpen(String value) => _pref.write(_kAppFirstOpen, value);

  static String getAppLastOpen() => _pref.read(_kAppLastOpen) ?? '';
  static void setAppLastOpen(String value) => _pref.write(_kAppLastOpen, value);

  static bool getAppHideSideMenu() => _pref.read(_kAppHideSideMenu) ?? false;
  static void setAppHideSideMenu(bool value) => _pref.write(_kAppHideSideMenu, value);

  // ** [download]
  static String getDownloadPath() => _pref.read(_kDownloadPath) ?? '';
  static void setDownloadPath(String value) => _pref.write(_kDownloadPath, value);

  static String getDownloadLang() => _pref.read(_kDownloadLang) ?? 'en';
  static void setDownloadLang(String value) => _pref.write(_kDownloadLang, value);

  static String getDownloadMode() => _pref.read(_kDownloadMode) ?? 'net';
  static void setDownloadMode(String value) => _pref.write(_kDownloadMode, value);


  // ** [home segment]
  static bool getHomeSecNewRelease() => _pref.read(_kHomeSecNewRelease) ?? true;
  static void setHomeSecNewRelease(String value) => _pref.write(_kHomeSecNewRelease, value);

  static bool getHomeSecRandom() => _pref.read(_kHomeSecRandom) ?? true;
  static void setHomeSecRandom(String value) => _pref.write(_kHomeSecRandom, value);

  static bool getHomeSecNewAdd() => _pref.read(_kHomeSecNewAdd) ?? true;
  static void setHomeSecNewAdd(String value) => _pref.write(_kHomeSecNewAdd, value);

  static bool getHomeSecNeverWatch() => _pref.read(_kHomeSecNeverWatch) ?? true;
  static void setHomeSecNeverWatch(String value) => _pref.write(_kHomeSecNeverWatch, value);

  static bool getHomeSecOldest() => _pref.read(_kHomeSecOldest) ?? true;
  static void setHomeSecOldest(String value) => _pref.write(_kHomeSecOldest, value);
}

const _kAppIsDarkMode = '_kAppIsDarkMode';
const _kAppLanguage = '_kAppLanguage';
const _kAppFirstOpen = '_kAppFirstOpen';
const _kAppLastOpen = '_kAppLastOpen';
const _kAppHideSideMenu = '_kAppHideSideMenu';

const _kDownloadPath = '_kDownloadPath';
const _kDownloadLang = '_kDownloadLang';
const _kDownloadMode = '_kDownloadMode';

const _kHomeSecNewRelease = '_kHomeSecNewRelease';
const _kHomeSecRandom = '_kHomeSecRandom';
const _kHomeSecNewAdd = '_kHomeSecNewAdd';
const _kHomeSecNeverWatch = '_kHomeSecNeverWatch';
const _kHomeSecOldest = '_kHomeSecOldest';
