import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_logging.dart';
import '../../core/app_setting.dart';
import '../../utils/helper_toast.dart';
import 'db_history.dart';
import 'db_library.dart';
import 'db_playlist.dart';
import 'db_videos.dart';

class DBService extends GetxService {
  late Database dbMain;
  late Database dbR18;
  late String appPath;

  @override
  Future<void> onInit() async {
    super.onInit();
    appPath = Get.find<AppSettingService>().appDir.path;
    dbMain = await _initializeDatabase();
    dbR18 = await _initializeR18Database();
  }

  Future<Database> _initializeDatabase() async {
    var path = join(appPath, 'javit.db');
    await Directory(appPath).create(recursive: true);
    return await openDatabase(
      path,
      version: 1,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onOpen: (db) async {
        AppLog.log('== Main Database (javit.db) opened (version: ${await db.getVersion()}) ==');
      },
    );
  }

  Future<Database> _initializeR18Database() async {
    var path = join(appPath, 'r18.db');
    await Directory(appPath).create(recursive: true);
    return await openDatabase(
      path,
      version: 20250715,
      onConfigure: _onConfigure,
      onOpen: (db) async {
        AppLog.log('== R18 Database (r18.db) opened (version: ${await db.getVersion()}) ==');
      },
    );
  }

  void _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  void _onCreate(Database db, int version) async {
    // Drop existing Test table (optional, only if you want to remove it)
    await db.execute('DROP TABLE IF EXISTS Library');
    await db.execute('DROP TABLE IF EXISTS Videos');

    // Create Library table
    await db.execute('''
      CREATE TABLE Library (
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
    // Note: 'actors', 'genre', 'screenshot' will be stored as TEXT (JSON string)
    await db.execute('''
      CREATE TABLE Videos (
        id                               TEXT PRIMARY KEY,
        root_path                        TEXT, 
        video_path                       TEXT,
        poster_path                      TEXT,
        cover_path                       TEXT,
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
        created_at                       TEXT,
        updated_at                       TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_video_path ON Videos(video_path);');
    await db.execute('CREATE INDEX idx_video_code ON Videos(video_code);');
    await db.execute('CREATE INDEX idx_title ON Videos(title);');
    await db.execute('CREATE INDEX idx_actress ON Videos(actress);');
    await db.execute('CREATE INDEX idx_category ON Videos(category);');
    await db.execute('CREATE INDEX idx_release_date ON Videos(release_date);');
    await db.execute('CREATE INDEX idx_duration ON Videos(duration);');
    await db.execute('CREATE INDEX idx_studio ON Videos(studio);');
    await db.execute('CREATE INDEX idx_label ON Videos(label);');
    await db.execute('CREATE INDEX idx_director ON Videos(director);');
    await db.execute('CREATE INDEX idx_series ON Videos(series);');

    // Create History table
    await db.execute('''
      CREATE TABLE History (
        id                          TEXT PRIMARY KEY,
        video                       TEXT, -- json
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');

    // Create PlaylistHeader table
    await db.execute('''
      CREATE TABLE PlaylistHeader (
        id                          TEXT PRIMARY KEY,
        name                        TEXT,
        cover                       TEXT,
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');

    // Create PlaylistItem table
    await db.execute('''
      CREATE TABLE PlaylistItem (
        id                          TEXT PRIMARY KEY,
        header_id                   TEXT,
        video                       TEXT, -- json
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');

    // Create Relapse table
    await db.execute('''
      CREATE TABLE Relapse (
        id                          TEXT PRIMARY KEY,
        date                        TEXT,
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');
  }

  Database get mainDatabase => dbMain;
  Database get r18Database => dbR18;

  Future<void> deleteAllData() async {
    await DBLibrary.deleteAll();
    await DBVideos.deleteAll();
    await DBHistory.deleteAll();
    await DBPlaylist.deleteAllHeader();
    // await DBRelapse.deleteAll();
    await vacumDB();
  }

  Future<void> vacumDB() async {
    try {
      await dbMain.rawQuery('VACUUM;');
      await HelperToast.success('Database optimized successfully');
    } catch (e) {
      print('Error vacuuming database: $e');
    }
  }

  Future<void> close() async {
    await dbMain.close();
    await dbR18.close();
  }
}
