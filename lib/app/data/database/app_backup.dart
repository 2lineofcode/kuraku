import 'dart:convert';
import 'dart:io';

import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/app_pref.dart';
import '../models/library_entity.dart';
import '../models/search_site.dart';
import '../models/videos_entity.dart';
import '_init_db.dart';
import '_update_db.dart';
import 'db_chat.dart';

class AppBackup {
  AppBackup._(this._data);
  final Map<String, dynamic> _data;

  static const tables = ['library', 'videos', 'playlist', 'playlist_item', 'watch_session', 'profile',
    'achievement_unlock', 'relapse_event', 'historical', 'todo', 'download_log', 'video_file_identity',
    'chat_conversation', 'chat_message', 'chat_translation', 'search_site'];
  static const _boolKeys = ['_kAppHideSideMenu', '_kAppDarkMode', '_kAppIsDarkMode', '_kPlayerAudioNormalization',
    '_kHomeSecNewRelease', '_kHomeSecRecommendation', '_kHomeSecFavorite', '_kHomeSecNewAdd',
    '_kHomeSecMostWatch', '_kHomeSecNeverWatch', '_kHomeSecRandom', '_kHomeSecOldest', '_kHomeSecImageAlbums', 'chat_sidebar_visible'];
  static const _intKeys = ['_kAppMaxColi', '_kDownloadChunk', '_kPlayerSeekShort', '_kPlayerSeekMid', '_kPlayerSeekLong', '_kAppAccent'];
  static const _stringKeys = ['_kAppLanguage', '_kAppTheme', '_kFavoriteCoverURL', '_kDefaultSearchEngine',
    '_kDefaultPlayer', '_kDownloadPath', '_kDownloadLang', '_kSemanticSearchModel'];
  static const settingKeys = [..._boolKeys, ..._intKeys, ..._stringKeys, '_kPlayerVolume', '_kPlayerSpeed',
    '_kHomeOrderList', '_kExplorePins', '_kPlayerCustomAdjustment', '_kDownloadOptions',
    ..._tabKeys, '_kAppCart', 'sql_snippets', 'chat_active_id'];
  static const _tabKeys = ['_kSearchTabs', '_kExploreTabs', '_kDownloadTabs', 'sql_tabs'];

  String get createdAt => _data['created_at'] as String;
  Map<String, dynamic> get _settings => _data['settings'] as Map<String, dynamic>;
  List<Map<String, Object?>> _rows(String table) => (_data['tables'][table] as List)
      .map((row) => Map<String, Object?>.from(row as Map)).toList();
  int count(String table) => (_data['tables'][table] as List).length;
  int get favorites => _rows('videos').where((row) => row['is_favorite'] == 1).length;
  int get settingsCount => _settings.values.where((value) => value != null).length;
  String encode() => jsonEncode(_data);

  static Future<AppBackup> capture(Database db, GetSecureStorage pref) async {
    final rows = await db.transaction((txn) async => {
      for (final table in tables) table: await txn.query(table, columns: table == 'download_log' ? ['id', 'payload', 'created_at', 'updated_at'] : null, orderBy: '1'),
    });
    return decode(jsonEncode({
      'format': 'kuraku-backup', 'version': 2, 'database_version': (await db.rawQuery('PRAGMA user_version')).single['user_version'],
      'created_at': DateTime.now().toUtc().toIso8601String(), 'tables': rows,
      'settings': {for (final key in settingKeys) key: pref.read(key)},
    }));
  }

  static AppBackup decode(String content) {
    if (utf8.encode(content).length > 128 * 1024 * 1024) throw const FormatException('Backup exceeds the 128 MB limit.');
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic> || data['format'] != 'kuraku-backup' || data['version'] != 2
        || ![18, DBUpdate.version].contains(data['database_version']) || data['created_at'] is! String
        || DateTime.tryParse(data['created_at']) == null) {
      throw const FormatException('Invalid backup or incompatible app/database version.');
    }
    final rows = data['tables'];
    final settings = data['settings'];
    if (data['database_version'] == 18 && rows is Map && !rows.containsKey('search_site')) {
      rows['search_site'] = SearchSite.defaults.map((site) => site.toJson()).toList();
      data['database_version'] = DBUpdate.version;
    }
    if (rows is! Map || rows.keys.any((table) => !tables.contains(table))
        || !tables.every((table) => rows[table] is List) || rows.values.any((value) => value is! List)
        || settings is! Map<String, dynamic> || settings.keys.any((key) => !settingKeys.contains(key))
        || !settingKeys.every(settings.containsKey)) {
      throw const FormatException('Backup tables or settings are missing or unsupported.');
    }
    for (final table in rows.keys) {
      for (final row in rows[table]) {
        if (row is! Map<String, dynamic> || row.isEmpty
            || row.values.any((value) => value != null && value is! String && value is! num)) {
          throw FormatException('Invalid row in $table.');
        }
      }
    }
    for (final entry in settings.entries) {
      final key = entry.key, value = entry.value;
      if (value == null) continue;
      var valid = _boolKeys.contains(key) ? value is bool
        : _intKeys.contains(key) ? value is int && value >= 0
        : _stringKeys.contains(key) ? value is String
        : key == 'chat_active_id' ? value is String
        : _tabKeys.contains(key) ? value is Map && (value['activeTab'] == null || value['activeTab'] is int && value['activeTab'] >= 0)
            && (value['tabs'] == null || value['tabs'] is List && (value['tabs'] as List).every((tab) => tab is Map<String, dynamic>))
        : key == 'sql_snippets' ? value is Map && value.values.every((group) => group is Map && group.values.every((sql) => sql is String))
        : key == '_kAppCart' ? value is List && value.every((video) => video is Map<String, dynamic>)
        : key == '_kPlayerVolume' ? value is num && value >= 0 && value <= 1
        : key == '_kPlayerSpeed' ? value is num && value > 0 && value <= 10
        : key == '_kHomeOrderList' || key == '_kExplorePins' ? value is List && value.every((item) => item is String)
        : key == '_kPlayerCustomAdjustment' && value is Map && value.entries.every((adjustment) =>
            ['brightness', 'contrast', 'saturation', 'hue', 'gamma'].contains(adjustment.key)
            && adjustment.value is num && (adjustment.value as num).isFinite);
      if (key == '_kDownloadOptions') valid = value is Map && value.entries.every((option) =>
        ['headless', 'allow_popups'].contains(option.key) ? option.value is bool
        : option.key == 'mode' ? ['extract', 'auto', 'hls', 'file', 'youtube'].contains(option.value)
        : ['directory', 'concurrency', 'retries', 'timeout', 'referer', 'user_agent', 'capture_duration', 'play_selector'].contains(option.key) && option.value is String);
      if (key == '_kAppAccent') valid = valid && (value as int) <= 0xffffffff;
      if (key == '_kAppLanguage') valid = ['en', 'id'].contains(value);
      if (key == '_kAppTheme') valid = ['system', 'schedule', 'dark', 'light'].contains(value);
      if (key == '_kDefaultPlayer') valid = ['In App', 'Default System'].contains(value);
      if (key == '_kDefaultSearchEngine') valid = (rows['search_site'] as List).any((site) => site['name'] == value);
      if (!valid) throw FormatException('Invalid setting: $key.');
      if (key == '_kAppCart') {
        try {
          for (final video in value as List) { Videos.fromJson(video as Map<String, dynamic>); }
        } catch (_) { throw const FormatException('Invalid cart video.'); }
      }
      if (key == '_kPlayerVolume' || key == '_kPlayerSpeed') settings[key] = (value as num).toDouble();
    }
    final sites = (rows['search_site'] as List).map((row) => SearchSite.fromJson(Map<String, Object?>.from(row))).toList();
    if (!SearchSite.defaults.every((site) => sites.any((item) => item.name == site.name))) {
      throw const FormatException('Backup is missing default search sites.');
    }
    if ((rows['profile'] as List).length != 1) throw const FormatException('Backup must contain one profile.');
    return AppBackup._(data);
  }

  static Future<AppBackup> read(File file) async {
    if (await file.length() > 128 * 1024 * 1024) throw const FormatException('Backup exceeds the 128 MB limit.');
    return decode(await file.readAsString());
  }

  Future<void> write(File file) async {
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(encode(), flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> validate({Database? database}) async {
    if (database != null) {
      await _validate(database);
      return;
    }
    final directory = await Directory.systemTemp.createTemp('kuraku-backup-');
    Database? scratch;
    try {
      scratch = await openDatabase(p.join(directory.path, 'validation.db'), version: DBUpdate.version,
        singleInstance: false, onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'), onCreate: DBService.onCreate);
      await _validate(scratch);
    } finally {
      await scratch?.close();
      await directory.delete(recursive: true);
    }
  }

  Future<void> _validate(Database db) async {
    await db.transaction<void>((txn) async {
      for (final table in tables) {
        final columns = await txn.rawQuery('PRAGMA table_info($table)');
        for (final row in _rows(table)) {
          if (row.length != columns.length || !columns.every((column) => row.containsKey(column['name']))) {
            throw FormatException('Invalid columns in $table.');
          }
          if (table == 'videos') Videos.fromJson(Map<String, dynamic>.from(row));
          if (table == 'library') Library.fromJson(Map<String, dynamic>.from(row));
          if (table == 'watch_session' && DateTime.tryParse(row['created_at'] as String? ?? '') == null) {
            throw const FormatException('Invalid watch session date.');
          }
          for (final column in columns) {
            final value = row[column['name']];
            if (value != null && (column['type'] == 'TEXT' ? value is! String : value is! int)) {
              throw FormatException('Invalid value in $table.${column['name']}.');
            }
          }
        }
      }
      await _replace(txn);
      if ((await txn.rawQuery('PRAGMA quick_check')).single.values.single != 'ok'
          || (await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('Backup database integrity check failed.');
      }
      // Validation must never commit into the supplied database.
      throw const _Validated();
    }).onError<_Validated>((_, _) {});
  }

  Future<void> _replace(DatabaseExecutor db) async {
    for (final table in tables.reversed) {
      await db.delete(table);
    }
    for (final table in tables) {
      for (final row in _rows(table)) await db.insert(table, row);
    }
  }

  Future<void> apply(Database db, GetSecureStorage pref) async {
    final previous = {for (final key in settingKeys) key: pref.read(key)};
    try {
      await db.transaction((txn) async {
        await _replace(txn);
        await DBChat.recoverInterrupted(txn);
        await AppPref.savePreferences(pref, _settings);
      });
    } catch (_) {
      await AppPref.savePreferences(pref, previous);
      rethrow;
    }
  }

  // Apply before controllers/watchers start; the journal rolls back interrupted restores.
  static Future<void> applyPending(String appPath, Database db, GetSecureStorage pref) async {
    final pending = File(p.join(appPath, 'pending-restore.json'));
    final journal = File(p.join(appPath, 'restore-journal.json'));
    if (await journal.exists()) {
      final previous = await read(journal);
      await previous.validate();
      await previous.apply(db, pref);
      await journal.delete();
    }
    if (!await pending.exists()) return;
    final backup = await read(pending);
    await backup.validate();
    final previous = await capture(db, pref);
    final recovery = File(p.join(appPath, 'recovery-${DateTime.now().microsecondsSinceEpoch}.kuraku-backup.json'));
    await previous.write(recovery);
    await previous.write(journal);
    await backup.apply(db, pref);
    await journal.delete();
    await pending.delete();
  }
}

class _Validated implements Exception {
  const _Validated();
}
