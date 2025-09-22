import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_logging.dart';
import '../../core/app_setting.dart';
import '../../utils/helper_toast.dart';
import 'db_activity.dart';
import 'db_collection.dart';
import 'db_library.dart';
import 'db_videos.dart';

class DBService extends GetxService {
  late Database dbMain;
  late Database dbR18;
  late String appPath;

  @override
  Future<void> onReady() async {
    super.onReady();
    appPath = Get.find<AppSettingService>().appPath;
    dbMain = await _initializeDatabase();
    dbR18 = await _initializeR18Database();
  }

  Future<Database> _initializeDatabase() async {
    var path = join(appPath, 'javit.db');
    await Directory(appPath).create(recursive: true);
    return await openDatabase(
      path,
      version: 1,
      singleInstance: true,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onOpen: (db) async {
        AppLog.logD('== Main Database (javit.db) opened (version: ${await db.getVersion()}) ==');
      },
    );
  }

  Future<Database> _initializeR18Database() async {
    var files = Glob('r18*.db').listSync(root: appPath);
    files.sort((a, b) => b.path.compareTo(a.path));

    if (files.isEmpty) {
      return await _initializeDatabase();
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
          AppLog.logD('== R18 Database (r18.db) opened (version: ${await db.getVersion()}) ==');
        },
      );
    } else {
      return await _initializeDatabase();
    }
  }

  void _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  void _onCreate(Database db, int version) async {
    // Drop existing Test table (optional, only if you want to remove it)
    await db.execute('DROP TABLE IF EXISTS library');
    await db.execute('DROP TABLE IF EXISTS videos');
    await db.execute('DROP TABLE IF EXISTS activity');
    await db.execute('DROP TABLE IF EXISTS collection');

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

    // Create Activity table
    await db.execute('''
      CREATE TABLE activity (
        id                          TEXT PRIMARY KEY,
        type                        TEXT,               -- todo | download | relapse
        content                     TEXT,               -- dynamic (text/json)
        created_at                  TEXT,
        updated_at                  TEXT
      )
    ''');

    // Create Collection table
    await db.execute('''
      CREATE TABLE collection (
        id                          TEXT PRIMARY KEY,
        type                        TEXT,               -- playlist | actress_favorite
        name                        TEXT,
        cover                       TEXT,
        video_id                    TEXT,
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
    await DBActivity.deleteAll();
    await DBCollection.deleteAll();
    await vacumDB();
  }

  Future<void> vacumDB() async {
    try {
      await dbMain.rawQuery('VACUUM;');
      await HelperToast.success('Database optimized successfully');
    } catch (e) {
      AppLog.logE('Error vacuuming database: $e');
    }
  }

  Future<void> close() async {
    await dbMain.close();
    await dbR18.close();
  }
}
