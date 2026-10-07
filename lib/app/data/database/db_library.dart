import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../models/library_entity.dart';
import '../models/videos_entity.dart';
import '_init_db.dart';
import 'db_videos.dart';

mixin DBLibrary {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _tableName = 'library';

  static List<Library> _toLibraries(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (index) => Library.fromJson(maps[index]));
  }

  static Future<bool> add(Library library, {DatabaseExecutor? executor}) async {
    if ((library.rootFolder ?? '').trim().isEmpty) return false;
    library.id = UuidV4().generate();
    library.createdAt = library.updatedAt = DateTime.now().toStringEx();
    library.totalVideo ??= 0;
    library.alias ??= '';
    try {
      await (executor ?? _db).insert(_tableName, library.toJson());
      return true;
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError('library.root_folder')) rethrow;
      AppLog.logW('Failed add library, duplicate root folder');
      return false;
    }
  }

  static Future<void> update(Library library, {DatabaseExecutor? executor}) async {
    if ((library.rootFolder ?? '').trim().isEmpty) throw ArgumentError('Library root is required');
    final now = DateTime.now().toStringEx();
    final values = library.toJson()..['updated_at'] = now;
    final changed = await (executor ?? _db).update(_tableName, values, where: 'id = ?', whereArgs: [library.id]);
    if (changed == 0) throw StateError('Library no longer exists');
    library.updatedAt = now;
  }

  static Future<int> commitScan(List<Library> snapshots, {
    List<Videos> additions = const [], List<Map<String, String>> moves = const [], List<String> deletedPaths = const [],
  }) async {
    final copies = snapshots.map((library) => Library.fromJson(library.toJson())..id = library.id).toList();
    final moved = await _db.transaction((txn) async {
      for (final library in copies) {
        if ((library.id ?? '').isEmpty) {
          if (!await add(library, executor: txn)) throw StateError('Library root is already registered');
        } else {
          await update(library, executor: txn);
        }
      }
      final moved = await DBVideos.moveVideoPaths(moves, executor: txn);
      await DBVideos.deleteByVideoPaths(deletedPaths, executor: txn);
      await DBVideos.addBulk(additions, executor: txn);
      return moved;
    });
    for (var i = 0; i < snapshots.length; i++) {
      snapshots[i].id = copies[i].id;
      snapshots[i].createdAt = copies[i].createdAt;
      snapshots[i].updatedAt = copies[i].updatedAt;
    }
    return moved;
  }

  static Future<void> delete(Library library) async {
    await _db.delete(_tableName, where: 'id = ?', whereArgs: [library.id]);
  }

  static Future<List<Library>> getAll() async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName);
    return _toLibraries(maps);
  }

  static Future<List<Library>> getByID(String id) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'id = ?', whereArgs: [id]);
    return _toLibraries(maps);
  }

  static Future<List<Library>> getByRootFolder(String rootFolder) async {
    final List<Map<String, dynamic>> maps = await _db.query(_tableName, where: 'root_folder = ?', whereArgs: [rootFolder]);
    return _toLibraries(maps);
  }

  static Future<int> getCount() async {
    final maps = await _db.rawQuery('SELECT COUNT(*) AS total FROM $_tableName');
    return maps.isNotEmpty ? (maps.first['total'] as int? ?? 0) : 0;
  }

  static Future<void> deleteAll() async => await _db.delete(_tableName);
}
