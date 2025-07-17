import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_logging.dart';

class DB extends GetxService {
  late Database dbMain;
  late Database dbR18;

  @override
  Future<void> onInit() async {
    super.onInit();
    dbMain = await _initializeDatabase();
    dbR18 = await _initializeR18Database();
  }

  Future<Database> _initializeDatabase() async {
    var databasesPath = await getDatabasesPath();
    var path = join(databasesPath, 'javit.db');
    await Directory(databasesPath).create(recursive: true);
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
    var databasesPath = await getDatabasesPath();
    var path = join(databasesPath, 'r18.db'); // Nama database R18 di perangkat
    await Directory(databasesPath).create(recursive: true);

    bool dbExists = await databaseExists(path);

    if (!dbExists) {
      AppLog.log('== R18 Database (r18.db) does not exist, copying from assets ==');
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}

      // Load database from assets
      ByteData data = await rootBundle.load(join('assets', 'r18.db'));
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      // Write the copied data to the local database file
      await File(path).writeAsBytes(bytes, flush: true);
      AppLog.log('== R18 Database copied from assets successfully ==');
    }

    return await openDatabase(
      path,
      version: 1,
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
        videos                      TEXT -- Stored as JSON string
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
        director                         TEXT,
        series                           TEXT,
        screenshot                       TEXT, -- Stored as JSON string
        view_count                       INTEGER,
        site                             TEXT
      )
    ''');
  }

  Database get mainDatabase => dbMain;
  Database get r18Database => dbR18;

  Future<void> close() async {
    await dbMain.close();
    await dbR18.close();
  }
}
