import 'package:get/get.dart';

import 'app_setting.dart';

mixin AppPref {
  static final _pref = Get.find<AppSettingService>().pref;

  // [app]
  static bool getAppIsDarkMode() => _pref.read(_kAppIsDarkMode) ?? true;
  static void setAppIsDarkMode(bool value) => _pref.write(_kAppIsDarkMode, value);
  // static void setAppIsDarkModeIfNull(bool value) => _pref.writeIfNull(_kAppIsDarkMode, value);

  static String getAppLanguage() => _pref.read(_kAppLanguage) ?? 'en';
  static void setAppLanguage(String value) => _pref.write(_kAppLanguage, value);
  // static void setAppLanguageIfNull(String value) => _pref.writeIfNull(_kAppLanguage, value);

  static String getAppFirstOpen() => _pref.read(_kAppFirstOpen) ?? '';
  static void setAppFirstOpen(String value) => _pref.write(_kAppFirstOpen, value);
  // static void setAppFirstOpenIfNull(String value) => _pref.writeIfNull(_kAppFirstOpen, value);

  static String getAppLastOpen() => _pref.read(_kAppLastOpen) ?? '';
  static void setAppLastOpen(String value) => _pref.write(_kAppLastOpen, value);
  // static void setAppLastOpenIfNull(String value) => _pref.writeIfNull(_kAppLastOpen, value);

  // [download]
  static String getDownloadPath() => _pref.read(_kDownloadPath) ?? '';
  static void setDownloadPath(String value) => _pref.write(_kDownloadPath, value);
  // static void setDownloadPathIfNull(String value) => _pref.writeIfNull(_kDownloadPath, value);

  static String getDownloadLang() => _pref.read(_kDownloadLang) ?? 'en';
  static void setDownloadLang(String value) => _pref.write(_kDownloadLang, value);
  // static void setDownloadLangIfNull(String value) => _pref.writeIfNull(_kDownloadLang, value);

  // [home]
  static bool getHomeSecNewRelease() => _pref.read(_kHomeSecNewRelease) ?? true;
  static void setHomeSecNewRelease(String value) => _pref.write(_kHomeSecNewRelease, value);
  // static void setHomeSecNewReleaseIfNull(String value) => _pref.writeIfNull(_kHomeSecNewRelease, value);

  static bool getHomeSecRandom() => _pref.read(_kHomeSecRandom) ?? true;
  static void setHomeSecRandom(String value) => _pref.write(_kHomeSecRandom, value);
  // static void setHomeSecRandomIfNull(String value) => _pref.writeIfNull(_kHomeSecRandom, value);

  static bool getHomeSecNewAdd() => _pref.read(_kHomeSecNewAdd) ?? true;
  static void setHomeSecNewAdd(String value) => _pref.write(_kHomeSecNewAdd, value);
  // static void setHomeSecNewAddIfNull(String value) => _pref.writeIfNull(_kHomeSecNewAdd, value);

  static bool getHomeSecNeverWatch() => _pref.read(_kHomeSecNeverWatch) ?? true;
  static void setHomeSecNeverWatch(String value) => _pref.write(_kHomeSecNeverWatch, value);
  // static void setHomeSecNeverWatchIfNull(String value) => _pref.writeIfNull(_kHomeSecNeverWatch, value);

  static bool getHomeSecOldest() => _pref.read(_kHomeSecOldest) ?? true;
  static void setHomeSecOldest(String value) => _pref.write(_kHomeSecOldest, value);
  // static void setHomeSecOldestIfNull(String value) => _pref.writeIfNull(_kHomeSecOldest, value);
}

const _kAppIsDarkMode = '_kAppIsDarkMode';
const _kAppLanguage = '_kAppLanguage';
const _kAppFirstOpen = '_kAppFirstOpen';
const _kAppLastOpen = '_kAppLastOpen';

const _kDownloadPath = '_kDownloadPath';
const _kDownloadLang = '_kDownloadLang';

const _kHomeSecNewRelease = '_kHomeSecNewRelease';
const _kHomeSecRandom = '_kHomeSecRandom';
const _kHomeSecNewAdd = '_kHomeSecNewAdd';
const _kHomeSecNeverWatch = '_kHomeSecNeverWatch';
const _kHomeSecOldest = '_kHomeSecOldest';
