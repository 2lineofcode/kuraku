import 'package:get/get.dart';

import 'app_logging.dart';
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

  static int getAppMaxColi() => _pref.read(_kAppMaxColi) ?? 2;
  static void setAppMaxColi(int value) => _pref.write(_kAppMaxColi, value);


  // ** [download]
  static String getDownloadPath() => _pref.read(_kDownloadPath) ?? '';
  static void setDownloadPath(String value) => _pref.write(_kDownloadPath, value);

  static String getDownloadLang() => _pref.read(_kDownloadLang) ?? 'en';
  static void setDownloadLang(String value) => _pref.write(_kDownloadLang, value);

  static String getDownloadMode() => _pref.read(_kDownloadMode) ?? 'net';
  static void setDownloadMode(String value) => _pref.write(_kDownloadMode, value);

  static int getDownloadWorker() => _pref.read(_kDownloadWorker) ?? 2;
  static void setDownloadWorker(int value) => _pref.write(_kDownloadWorker, value);


  // ** [home segment]
  static List<String> getHomeOrderList() {
    final list = _pref.read(_kHomeOrderList);
    return list != null ? List<String>.from(list) : <String>[];
  }
  static void setHomeOrderList(List<String> value) => _pref.write(_kHomeOrderList, value);


  static bool getHomeSecNewRelease() => _pref.read(_kHomeSecNewRelease) ?? true;
  static void setHomeSecNewRelease(bool value) => _pref.write(_kHomeSecNewRelease, value);
  static const String homeSecNewRelease = _kHomeSecNewRelease;

  static bool getHomeSecFavorite() => _pref.read(_kHomeSecFavorite) ?? true;
  static void setHomeSecFavorite(bool value) => _pref.write(_kHomeSecFavorite, value);
  static const String homeSecFavorite= _kHomeSecFavorite;

  static bool getHomeSecNewAdd() => _pref.read(_kHomeSecNewAdd) ?? true;
  static void setHomeSecNewAdd(bool value) => _pref.write(_kHomeSecNewAdd, value);
  static const String homeSecNewAdd = _kHomeSecNewAdd;

  static bool getHomeSecMostWatch() => _pref.read(_kHomeSecMostWatch) ?? true;
  static void setHomeSecMostWatch(bool value) => _pref.write(_kHomeSecMostWatch, value);
  static const String homeSecMostWatch = _kHomeSecMostWatch;

  static bool getHomeSecNeverWatch() => _pref.read(_kHomeSecNeverWatch) ?? true;
  static void setHomeSecNeverWatch(bool value) => _pref.write(_kHomeSecNeverWatch, value);
  static const String homeSecNeverWatch = _kHomeSecNeverWatch;

  static bool getHomeSecRandom() => _pref.read(_kHomeSecRandom) ?? true;
  static void setHomeSecRandom(bool value) => _pref.write(_kHomeSecRandom, value);
  static const String homeSecRandom = _kHomeSecRandom;

  static bool getHomeSecOldest() => _pref.read(_kHomeSecOldest) ?? true;
  static void setHomeSecOldest(bool value) => _pref.write(_kHomeSecOldest, value);
  static const String homeSecOldest = _kHomeSecOldest;

  static bool getHomeSecCollection() => _pref.read(_kHomeSecCollection) ?? true;
  static void setHomeSecCollection(bool value) => _pref.write(_kHomeSecCollection, value);
  static const String homeSecCollection = _kHomeSecCollection;


  // ** player
  static String getDefaultPlayer() => _pref.read(_kDefaultPlayer) ?? 'In App'; // In App | Default System
  static void setDefaultPlayer(String value) => _pref.write(_kDefaultPlayer, value);

  static double getPlayerVolume() => _pref.read(_kPlayerVolume) ?? 0.1;
  static void setPlayerVolume(double value) => _pref.write(_kPlayerVolume, value);

  static double getPlayerSpeed() => _pref.read(_kPlayerSpeed) ?? 1.0;
  static void setPlayerSpeed(double value) => _pref.write(_kPlayerSpeed, value);

  static int getPlayerSeekShort() => _pref.read(_kPlayerSeekShort) ?? 5;
  static void setPlayerSeekShort(int value) => _pref.write(_kPlayerSeekShort, value);

  static int getPlayerSeekMid() => _pref.read(_kPlayerSeekMid) ?? 30;
  static void setPlayerSeekMid(int value) => _pref.write(_kPlayerSeekMid, value);

  static int getPlayerSeekLong() => _pref.read(_kPlayerSeekLong) ?? 60;
  static void setPlayerSeekLong(int value) => _pref.write(_kPlayerSeekLong, value);

  // helper
  static bool getBool(String key) => _pref.read(key) ?? false;
  static void setBool(String key, bool value) => _pref.write(key, value);

  static Future<void> printAllPref() async {
    AppLog.logS('### AppPref ===');
    _pref.getKeys().forEach((key) => AppLog.logS('${key.replaceAll('_k', ' ')} = ${_pref.read(key)}'));
    await 200.milliseconds.delay();
    AppLog.logS('### --------------------');
  }
}

const _kAppIsDarkMode = '_kAppIsDarkMode';
const _kAppLanguage = '_kAppLanguage';
const _kAppFirstOpen = '_kAppFirstOpen';
const _kAppLastOpen = '_kAppLastOpen';
const _kAppHideSideMenu = '_kAppHideSideMenu';
const _kAppMaxColi = '_kAppMaxColi';


const _kDownloadPath = '_kDownloadPath';
const _kDownloadLang = '_kDownloadLang';
const _kDownloadMode = '_kDownloadMode';
const _kDownloadWorker = '_kDownloadChunk';


const _kHomeOrderList = '_kHomeOrderList';
const _kHomeSecNewRelease = '_kHomeSecNewRelease';
const _kHomeSecFavorite = '_kHomeSecFavorite';
const _kHomeSecNewAdd = '_kHomeSecNewAdd';
const _kHomeSecMostWatch = '_kHomeSecMostWatch';
const _kHomeSecNeverWatch = '_kHomeSecNeverWatch';
const _kHomeSecRandom = '_kHomeSecRandom';
const _kHomeSecOldest = '_kHomeSecOldest';
const _kHomeSecCollection = '_kHomeSecCollection';

// player
const _kDefaultPlayer = '_kDefaultPlayer';
const _kPlayerVolume = '_kPlayerVolume';
const _kPlayerSpeed = '_kPlayerSpeed';
const _kPlayerSeekShort = '_kPlayerSeekShort';
const _kPlayerSeekMid = '_kPlayerSeekMid';
const _kPlayerSeekLong = '_kPlayerSeekLong';
