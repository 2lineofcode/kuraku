import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/app_logging.dart';
import '../../core/app_setting.dart';
import '../../utils/watch_session_tracker.dart';
import '_update_db.dart';
import 'db_chat.dart';
import 'db_profile.dart';

class DBService extends GetxService {
  // Database name
  final dbName = 'kuraku.db';

  // MAIN DB
  late Database dbMain;

  // R18 DB
  Database? dbR18;

  // Global App Path
  late String appPath;

  Future<DBService> init() async {
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    appPath = Get.find<AppSettingService>().appPath;
    dbMain = await _initializeDatabase();
    dbR18 = await _initializeR18Database();
    return this;
  }

  Future<Database> _initializeDatabase() async {
    var path = join(appPath, '$dbName');
    await Directory(appPath).create(recursive: true);
    return await openDatabase(
      path,
      version: DBUpdate.version,
      singleInstance: true,
      onConfigure: _onConfigure,
      onCreate: onCreate,
      onUpgrade: DBUpdate.onUpgrade,
      onDowngrade: DBUpdate.onDowngrade,
      onOpen: (db) async {
        await DBChat.recoverInterrupted(db);
        AppLog.logD('== Main Database ($dbName) opened (version: ${await db.getVersion()}) ==');
      },
    );
  }

  Future<Database?> _initializeR18Database() async {
    var files = Glob('r18*.db').listSync(root: appPath);
    files.sort((a, b) => b.path.compareTo(a.path));

    if (files.isEmpty) {
      AppLog.logW('R18 database not found at startup');
      return null;
    }

    final r18SqlFile = files.first.path;

    final date = r18SqlFile.allBetween('r18_', '.db').replaceAll('_', '').toInt();
    var path = join(appPath, r18SqlFile);

    // check is file exist?
    final file = File(path);
    if (await file.exists()) {
      await Directory(appPath).create(recursive: true);
      return await openDatabase(
        path,
        version: date ?? 1,
        onConfigure: _onConfigure,
        singleInstance: true,
        onOpen: (db) async {
          await prepareR18VideoCodes(db);
          AppLog.logD('== R18 Database (r18.db) opened (version: ${await db.getVersion()}) ==');
        },
      );
    } else {
      AppLog.logW('R18 database file missing: $path');
      return null;
    }
  }

  static Future<void> prepareR18VideoCodes(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(derived_video)');
    if (!columns.any((column) => column['name'] == 'video_code')) {
      final script = await rootBundle.loadString('assets/sql/r18_video_code_migration.sql');
      AppLog.logD('Preparing R18 video codes');
      await db.transaction((txn) async {
        for (final statement in script.split(';')) {
          if (statement.trim().isNotEmpty) await txn.execute(statement);
        }
      });
      AppLog.logD('R18 video codes ready');
    }
    final prepared = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE name = 'kuraku_catalog_groups_v2'");
    if (prepared.isNotEmpty) return;
    final catalog = await rootBundle.loadString('assets/sql/r18_catalog_setup.sql');
    AppLog.logD('Preparing R18 catalog queries');
    await db.transaction((txn) async {
      for (final statement in catalog.split(';')) {
        if (statement.trim().isNotEmpty) await txn.execute(statement);
      }
    });
    AppLog.logD('R18 catalog queries ready');
  }

  Future<void> activateR18Database(String path, int version) async {
    final next = await openDatabase(path, version: version, onConfigure: _onConfigure);
    try {
      await prepareR18VideoCodes(next);
    } catch (_) {
      if (next != dbR18) await next.close();
      rethrow;
    }
    final previous = dbR18;
    dbR18 = next;
    try {
      await previous?.close();
      if (previous != null && previous.path != path) await File(previous.path).delete();
    } catch (e) {
      AppLog.logW('Could not clean up previous R18 database: $e');
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.rawQuery('PRAGMA busy_timeout = 5000');
    final mode = await db.rawQuery('PRAGMA journal_mode');
    if (mode.single['journal_mode'] != 'delete') {
      final changed = await db.rawQuery('PRAGMA journal_mode = DELETE');
      if (changed.single['journal_mode'] != 'delete') throw StateError('Could not enable single-file database mode');
    }
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // Frozen v1 baseline; later schema changes belong in DBUpdate.
  static Future<void> onCreate(Database db, int version) async {
    // Create Library table
    await db.execute('''
      CREATE TABLE library (
        id                          TEXT PRIMARY KEY,
        total_video                 INTEGER,
        alias                       TEXT,
        root_folder                 TEXT,
        sub_folder                  TEXT, -- Stored as JSON string
        videos                      TEXT, -- Stored as JSON string
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');

    // Create Videos table
    // Note: 'actress', 'category', 'screenshot' will be stored as TEXT (JSON string)
    await db.execute('''
      CREATE TABLE videos (
        id                               TEXT PRIMARY KEY,
        root_path                        TEXT, 
        video_path                       TEXT,
        video_code                       TEXT,
        title                            TEXT,
        title_ja                         TEXT,
        description                      TEXT,
        fan_art                          TEXT,
        poster                           TEXT,
        trailer                          TEXT,
        actress                          TEXT, -- Stored as JSON string
        category                         TEXT, -- Stored as JSON string
        release_date                     TEXT,
        release_date_formated            TEXT,
        duration                         INTEGER,
        duration_formated                TEXT,
        studio                           TEXT,
        label                            TEXT,
        director                         TEXT, -- NOT NULL DEFAULT '',
        series                           TEXT,
        screenshot                       TEXT, -- Stored as JSON string
        view_count                       INTEGER,
        site                             TEXT,
        is_favorite                      INTEGER,
        filesize                         INTEGER,  -- mb/gb
        quality                          TEXT,  -- 4k | 2k | fhd | hd | sd
        created_at                       TEXT,
        updated_at                       TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_video_path ON videos(video_path);');
    await db.execute('CREATE INDEX idx_video_code ON videos(video_code);');
    await db.execute('CREATE INDEX idx_title ON videos(title);');
    await db.execute('CREATE INDEX idx_actress ON videos(actress);');
    await db.execute('CREATE INDEX idx_category ON videos(category);');
    await db.execute('CREATE INDEX idx_release_date ON videos(release_date);');
    await db.execute('CREATE INDEX idx_duration ON videos(duration);');
    await db.execute('CREATE INDEX idx_studio ON videos(studio);');
    await db.execute('CREATE INDEX idx_label ON videos(label);');
    await db.execute('CREATE INDEX idx_director ON videos(director);');
    await db.execute('CREATE INDEX idx_series ON videos(series);');

    // Legacy v1 activity; v14 splits storage into domain tables and keeps a read-only view.
    await db.execute('''
      CREATE TABLE activity (
        id                          TEXT PRIMARY KEY,
        type                        TEXT,               -- todo | download | relapse
        content                     TEXT,               -- dynamic (text/json)
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE profile (
        id                          TEXT PRIMARY KEY,
        name                        TEXT,
        total_watch_duration        INTEGER,
        badge_for_watch_duration    TEXT,
        badge_for_collection        TEXT,
        created_at                  TEXT,
        updated_at                  TEXT
      )

    ''');

    await db.execute('''
      INSERT INTO profile 
        (id, name, total_watch_duration, badge_for_watch_duration, badge_for_collection, created_at, updated_at) 
      VALUES 
        ('1', 'Newbie', 0, '', '', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
    ''');

    // Create Collection table
    await db.execute('''
      CREATE TABLE collection (
        id                          TEXT PRIMARY KEY,
        type                        TEXT,               -- collection | actress_favorite
        name                        TEXT,
        cover                       TEXT,
        video_id                    TEXT,
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');

    await DBUpdate.onUpgrade(db, 1, version);
  }

  Database get mainDatabase => dbMain;
  Database? get r18Database => dbR18;

  Future<void> deleteAllData() async {
    await WatchSessionTracker.resetHistory(() => dbMain.transaction((txn) async {
      for (final table in ['playlist', 'video_embeddings', 'videos', 'library', 'todo', 'download_log', 'relapse_event',
        'watch_session', 'achievement_unlock', 'historical', 'chat_conversation', 'chat_translation']) {
        await txn.delete(table);
      }
      await txn.update('profile', {
        'total_watch_duration': 0, 'badge_for_watch_duration': DBProfile.watchDurationBadge(0),
        'badge_for_collection': 'Noobless',
      }, where: 'id = ?', whereArgs: ['1']);
    }));
    await vacumDB();
  }

  Future<bool> vacumDB() async {
    try {
      await dbMain.execute('VACUUM;');
      return true;
    } catch (e) {
      AppLog.logE('Error vacuuming database: $e');
      return false;
    }
  }

  Future<void> close() async {
    await dbMain.close();
    await dbR18?.close();
  }
}
