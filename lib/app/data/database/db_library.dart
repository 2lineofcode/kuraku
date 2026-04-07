import 'package:ex_kit/ex.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../models/library_entity.dart';
import '_init_db.dart';

mixin DBLibrary {
  static Database get _db => Get.find<DBService>().dbMain;
  static const _tableName = 'library';

  static List<Library> _toLibraries(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (index) => Library.fromJson(maps[index]));
  }

  static Future<bool> _validation(Library library) async {
    final isDuplicateRootFolder = await getByRootFolder(library.rootFolder ?? '');
    if (isDuplicateRootFolder.isNotEmpty) return false;

    return true;
  }

  static Future<bool> add(Library library) async {
    library.id = UuidV4().generate();
    library.createdAt = DateTime.now().toStringEx();
    library.updatedAt = DateTime.now().toStringEx();
    final isOK = await _validation(library);
    if (isOK) {
      await _db.insert(_tableName, library.toJson());
      return true;
    }

    AppLog.logW('Failed add library, duplicate root folder: ${library.rootFolder}');
    return false;
  }

  static Future<void> update(Library library) async {
    library.updatedAt = DateTime.now().toStringEx();
    await _db.update(_tableName, library.toJson(), where: 'id = ?', whereArgs: [library.id]);
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
