import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../data/models/videos_entity.dart';
import 'app_setting.dart';

enum AppTheme {
  system('System'),
  schedule('Auto Schedule'),
  dark('Dark'),
  light('Light');

  const AppTheme(this.label);
  final String label;

  ThemeMode resolve([DateTime? now]) {
    switch (this) {
      case system: return ThemeMode.system;
      case dark: return ThemeMode.dark;
      case light: return ThemeMode.light;
      case schedule:
        final hour = (now ?? DateTime.now()).hour;
        return hour >= 6 && hour < 17 ? ThemeMode.light : ThemeMode.dark;
    }
  }
}

mixin AppPref {
  static final _pref = Get.find<AppSettingService>().pref;

  static String? getActiveChat() => _pref.read<String>('chat_active_id');
  static Future<void> setActiveChat(String id) => _pref.write('chat_active_id', id);
  static bool getChatSidebarVisible() => _pref.read<bool>('chat_sidebar_visible') ?? true;
  static Future<void> setChatSidebarVisible(bool value) => _pref.write('chat_sidebar_visible', value);

  static Map<String, dynamic> getSqlSnippets() => Map<String, dynamic>.from(_pref.read<Map>('sql_snippets') ?? {});
  static Future<void> setSqlSnippets(Map<String, dynamic> value) async {
    final previous = getSqlSnippets();
    try {
      await _pref.write('sql_snippets', value);
    } catch (_) {
      _pref.writeInMemory('sql_snippets', previous);
      rethrow;
    }
  }

  static Map<String, dynamic> getSqlTabs() => Map<String, dynamic>.from(_pref.read<Map>('sql_tabs') ?? {});
  static Future<void> setSqlTabs(Map<String, dynamic> value) async {
    final previous = getSqlTabs();
    try {
      await _pref.write('sql_tabs', value);
    } catch (_) {
      _pref.writeInMemory('sql_tabs', previous);
      rethrow;
    }
  }

  // ** [app]
  static void setAppLastOpen(String value) => _pref.write(_kAppLastOpen, value);

  static bool getAppHideSideMenu() => _pref.read(_kAppHideSideMenu) ?? false;
  static void setAppHideSideMenu(bool value) => _pref.write(_kAppHideSideMenu, value);

  static AppTheme getAppTheme() {
    final stored = _pref.read<String>('_kAppTheme');
    return AppTheme.values.firstWhere((theme) => theme.name == stored,
      orElse: () => (_pref.read<bool>('_kAppDarkMode') ?? true) ? AppTheme.dark : AppTheme.light);
  }
  static Future<void> setAppTheme(AppTheme value) async {
    final previous = _pref.read<String>('_kAppTheme');
    try {
      await _pref.write('_kAppTheme', value.name);
    } catch (_) {
      _pref.writeInMemory('_kAppTheme', previous);
      rethrow;
    }
  }

  static int getAppMaxColi() => _pref.read(_kAppMaxColi) ?? 2;
  static Future<void> setAppMaxColi(int value) async {
    if (value < 0) throw ArgumentError.value(value, 'value');
    final previous = getAppMaxColi();
    try {
      await _pref.write(_kAppMaxColi, value);
    } catch (_) {
      _pref.writeInMemory(_kAppMaxColi, previous);
      rethrow;
    }
  }

  static List<Videos> getAppCart() {
    final list = _pref.read<List>(_kAppCart);
    if (list == null) return <Videos>[];
    return list.map((e) => Videos.fromJson(Map<String, dynamic>.from(e))).toList();
  }
  static void setAppCart(List<Videos> value) => _pref.write(_kAppCart, value.map((e) => e.toJson()).toList());

  static String getFavoriteCoverURL() => _pref.read(_kFavoriteCoverURL) ?? 'https://www.zenra.net/imgcache/max-content-width/blog/10/best-debuts-and-honorable-mentions-xx-677ad45348fe4.png';
  static void setFavoriteCoverURL(String value) => _pref.write(_kFavoriteCoverURL, value);

  static String getDefaultSearchEngine() => _pref.read(_kDefaultSearchEngine) ?? 'NJAV';
  static void setDefaultSearchEngine(String value) => _pref.write(_kDefaultSearchEngine, value);

  static Map<String, dynamic> getSearchTabs() {
    final value = _pref.read(_kSearchTabs);
    return value is Map<String, dynamic> ? value : {};
  }
  static Future<void> setSearchTabs(Map<String, dynamic> value) => _pref.write(_kSearchTabs, value);

  static Map<String, dynamic> getExploreTabs() {
    final value = _pref.read(_kExploreTabs);
    return value is Map<String, dynamic> ? value : {};
  }
  static Future<void> setExploreTabs(Map<String, dynamic> value) => _pref.write(_kExploreTabs, value);

  static Map<String, dynamic> getDownloadTabs() {
    final value = _pref.read(_kDownloadTabs);
    return value is Map<String, dynamic> ? value : {};
  }
  static Future<void> setDownloadTabs(Map<String, dynamic> value) => _pref.write(_kDownloadTabs, value);

  static String getSemanticSearchModel() => _pref.read(_kSemanticSearchModel) ?? 'local-hash-v2';

  // ** [download]
  static Map<String, dynamic> getDownloadOptions() {
    final value = _pref.read('_kDownloadOptions');
    return value is Map<String, dynamic> ? value : {};
  }
  static Future<void> setDownloadOptions(Map<String, dynamic> value) => _pref.write('_kDownloadOptions', value);

  static String getDownloadPath() => _pref.read(_kDownloadPath) ?? '';
  static void setDownloadPath(String value) => _pref.write(_kDownloadPath, value);

  static int getDownloadWorker() => _pref.read(_kDownloadWorker) ?? 2;
  static void setDownloadWorker(int value) => _pref.write(_kDownloadWorker, value);

  // ** [home segment]
  static List<String> getHomeOrderList() {
    final list = _pref.read(_kHomeOrderList);
    return list != null ? List<String>.from(list) : <String>[];
  }
  static void setHomeOrderList(List<String> value) => _pref.write(_kHomeOrderList, value);

  static List<String> getExplorePins() => List<String>.from(_pref.read<List>(_kExplorePins) ?? []);
  static Future<void> setExplorePins(List<String> value) async {
    final previous = getExplorePins();
    try {
      await _pref.write(_kExplorePins, value);
    } catch (_) {
      _pref.writeInMemory(_kExplorePins, previous);
      rethrow;
    }
  }

  static const String homeSecNewRelease = _kHomeSecNewRelease;

  static const String homeSecRecommendation = _kHomeSecRecommendation;

  static const String homeSecFavorite= _kHomeSecFavorite;

  static const String homeSecNewAdd = _kHomeSecNewAdd;

  static const String homeSecMostWatch = _kHomeSecMostWatch;

  static const String homeSecNeverWatch = _kHomeSecNeverWatch;

  static const String homeSecRandom = _kHomeSecRandom;

  static const String homeSecOldest = _kHomeSecOldest;

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

  static bool getPlayerAudioNormalization() => _pref.read(_kPlayerAudioNormalization) ?? false;
  static void setPlayerAudioNormalization(bool value) => _pref.write(_kPlayerAudioNormalization, value);

  static bool hasPlayerCustomAdjustment() {
    final data = _pref.read<Map>(_kPlayerCustomAdjustment);
    return data != null && data.isNotEmpty;
  }

  static Map<String, double> getPlayerCustomAdjustment() {
    final data = _pref.read<Map>(_kPlayerCustomAdjustment);
    if (data == null) return {};
    final map = Map<String, dynamic>.from(data);
    return {
      'brightness': (map['brightness'] as num?)?.toDouble() ?? 0,
      'contrast': (map['contrast'] as num?)?.toDouble() ?? 0,
      'saturation': (map['saturation'] as num?)?.toDouble() ?? 0,
      'hue': (map['hue'] as num?)?.toDouble() ?? 0,
      'gamma': (map['gamma'] as num?)?.toDouble() ?? 0,
    };
  }

  static void setPlayerCustomAdjustment(Map<String, double> value) {
    _pref.write(_kPlayerCustomAdjustment, value);
  }

  // helper
  static bool getBool(String key) => _pref.read(key) ?? false;
  static void setBool(String key, bool value) => _pref.write(key, value);
}

const _kAppLastOpen = '_kAppLastOpen';
const _kAppHideSideMenu = '_kAppHideSideMenu';
const _kAppMaxColi = '_kAppMaxColi';
const _kAppCart = '_kAppCart';
const _kFavoriteCoverURL = '_kFavoriteCoverURL';
const _kDefaultSearchEngine = '_kDefaultSearchEngine';
const _kSearchTabs = '_kSearchTabs';
const _kExploreTabs = '_kExploreTabs';
const _kDownloadTabs = '_kDownloadTabs';
const _kSemanticSearchModel = '_kSemanticSearchModel';

const _kDownloadPath = '_kDownloadPath';
const _kDownloadWorker = '_kDownloadChunk';

const _kHomeOrderList = '_kHomeOrderList';
const _kExplorePins = '_kExplorePins';
const _kHomeSecNewRelease = '_kHomeSecNewRelease';
const _kHomeSecRecommendation = '_kHomeSecRecommendation';
const _kHomeSecFavorite = '_kHomeSecFavorite';
const _kHomeSecNewAdd = '_kHomeSecNewAdd';
const _kHomeSecMostWatch = '_kHomeSecMostWatch';
const _kHomeSecNeverWatch = '_kHomeSecNeverWatch';
const _kHomeSecRandom = '_kHomeSecRandom';
const _kHomeSecOldest = '_kHomeSecOldest';

// player
const _kDefaultPlayer = '_kDefaultPlayer';
const _kPlayerVolume = '_kPlayerVolume';
const _kPlayerSpeed = '_kPlayerSpeed';
const _kPlayerSeekShort = '_kPlayerSeekShort';
const _kPlayerSeekMid = '_kPlayerSeekMid';
const _kPlayerSeekLong = '_kPlayerSeekLong';
const _kPlayerAudioNormalization = '_kPlayerAudioNormalization';
const _kPlayerCustomAdjustment = '_kPlayerCustomAdjustment';
